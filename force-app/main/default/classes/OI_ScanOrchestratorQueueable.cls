/**
 * Purpose: The scan orchestration mechanism (MetadataScanner.md §14, ADR-0004) — a chain
 *          of Queueable hops, one per enabled metadata type, driving Scan Run / Scan Task
 *          lifecycle and handing each type's Discovery Batch to OI_MutationGenerator. Also
 *          the scan-lifecycle read/write surface OI_ScanController calls (startScan,
 *          getScanStatus, getScanHistory, cancelScan — API.md §2.4) — no separate Service
 *          class exists for this domain; the Orchestrator has been that surface since
 *          Sprint 8, and Sprint 9/9.1 extend it rather than introducing a parallel one.
 * Responsibilities: Read the Scanner Registry (OI_Metadata_Type_Config__mdt) for enabled
 *                    types; enforce the single-flight guard (MetadataScanner.md §13 — only
 *                    one Running scan at a time); create/track OI_Scan_Run__c and one
 *                    OI_Scan_Task__c per type; resolve and invoke that type's
 *                    OI_IMetadataScanner via Type.forName/newInstance; dispatch a large
 *                    batch's component/relationship chunking to OI_ScanComponentIngestBatchable
 *                    / OI_ScanRelationshipIngestBatchable, and a large retire-detection wave
 *                    to OI_ScanRetireDetectionBatchable (Sprint 9.1, ADR-0004 amendment) —
 *                    every chunking concern in this subsystem is Batch-Apex-driven, none of
 *                    it Queueable-chained; publish OI_Scan_Progress__e at meaningful
 *                    lifecycle points; isolate a scanner or ingestion/retire failure to its
 *                    own Scan Task and continue the chain; complete the Scan Run with an
 *                    accurate aggregate status; support best-effort cooperative
 *                    cancellation (a Cancelled run stops chaining after its current
 *                    in-flight hop finishes, per API.md §2.4).
 * Dependencies: OI_Metadata_Type_Config__mdt, OI_Scan_Run__c, OI_Scan_Task__c,
 *               OI_Scan_Progress__e, OI_IMetadataScanner, OI_MutationGenerator,
 *               OI_ScanComponentIngestBatchable, OI_ScanRelationshipIngestBatchable,
 *               OI_ScanRetireDetectionBatchable, OI_LoggerService, OI_SecurityService.
 * Limitations: Per-type cadence (Min_Rescan_Interval_Minutes__c) and incremental
 *              watermarking are not applied — every hop runs a full scan for every enabled
 *              type (Phase 3 scope, not Sprint 9). Records_Changed__c on OI_Scan_Task__c
 *              and Edge_Count__c on OI_Scan_Run__c are not populated — no data path exists
 *              yet for either (documented since Sprint 8; still true). Cancellation is
 *              cooperative and checked once at the start of each hop — a hop already
 *              mid-execution runs to completion before the check on the next hop takes
 *              effect, matching API.md §2.4's own "best-effort" framing exactly.
 *              Developer Edition and trial orgs enforce a real, low ceiling on total
 *              *chained Queueable* depth. Sprint 9.1 (first pass) moved ingestion chunking
 *              off that chain but left retire-detection's paging on it (MS-4b) — a real
 *              rescan against this org's Developer Edition sandbox immediately proved that
 *              scoping wrong: retire-detection's read side pages proportionally to how many
 *              Active keys already exist, regardless of whether anything is actually
 *              missing, so any rescan of an org with existing data re-triggers the exact
 *              same ceiling. Sprint 9.1 (second pass, this version) moves retire-detection
 *              to OI_ScanRetireDetectionBatchable too — every chunking concern in this
 *              subsystem is now Batch-Apex-driven, and the Queueable chain is once again
 *              exactly ADR-0004's original invariant: one hop per configured type, nothing
 *              else. Confirmed by a real scan against this same Developer Edition sandbox
 *              reaching every enabled type with no chain-depth failure (Sprint 9.1
 *              deliverables report). The ceiling can still, in principle, be approached by
 *              an org with more enabled metadata *types* than it allows hops for;
 *              production/sandbox orgs (Enterprise/Unlimited/Performance/Professional) do
 *              not enforce it at all. Every enqueue/executeBatch call site is defensive: a
 *              failure to advance never leaves a run stuck Running — it is force-completed
 *              as CompletedWithErrors instead, so the single-flight guard can never be
 *              permanently deadlocked by a broken chain.
 */
public without sharing class OI_ScanOrchestratorQueueable implements Queueable {
    private static final String DEFAULT_STARTING_STATUS = 'Running';
    private static final String STATUS_CANCELLED = 'Cancelled';
    private static final String STATUS_RUNNING = 'Running';

    /**
     * commitVersion cannot be bulked across different keys without losing its atomicity
     * guarantee (GraphRepository.md §11) — each new/changed key costs its own Savepoint +
     * insert (~2 DML statements). 60 per hop/batch-scope (~123 statements incl. the bulk
     * getCurrentVersions read and touchLiveness call every chunk also issues) leaves
     * comfortable headroom under the platform's 150-statement-per-transaction ceiling.
     * Also used as the Batch Apex scope size for OI_ScanComponentIngestBatchable /
     * OI_ScanRelationshipIngestBatchable / OI_ScanRetireDetectionBatchable (Sprint 9.1) for
     * the identical governor-safety reason — each retirement is itself a commitVersion
     * call. Public: read by the Batchable classes so chunk/scope sizing has one source of
     * truth.
     */
    public static final Integer CHUNK_SIZE = 60;

    /**
     * Test-only seam (GraphRepository.md/CodingStandards.md's established constructor-
     * injection-for-testability pattern, applied here via a static override since the
     * Scanner is resolved dynamically via Type.forName rather than injected). Empty in
     * production — has zero effect unless a test populates it. Exists because this real
     * org alone has 796 deployed Apex classes; letting the real OI_ApexClassScanner run
     * through the Orchestrator inside a test would reach Database.executeBatch from within
     * a Queueable's execute() — which throws "No more than one executeBatch can be called
     * from within a test method" once drained via Test.stopTest() (a genuine, confirmed
     * Apex-test-harness-only restriction; see OI_ScanOrchestratorQueueableTest's class doc
     * for the full explanation). Scanner correctness against real org metadata is proven
     * independently and directly (OI_ObjectScannerTest/OI_FieldScannerTest/
     * OI_ApexClassScannerTest call scan() once, synchronously, with no chaining involved);
     * this seam lets Orchestrator lifecycle tests stay fast without duplicating that
     * coverage.
     */
    @TestVisible
    private static Map<String, OI_IMetadataScanner> testScannerOverrides = new Map<String, OI_IMetadataScanner>();

    /**
     * A hop never carries in-progress ingestion or retire-detection state (Sprint 9.1,
     * second pass) — both are fully delegated to Batch Apex (OI_ScanComponentIngestBatchable/
     * OI_ScanRelationshipIngestBatchable/OI_ScanRetireDetectionBatchable), which carry
     * their own chunk-loop state via Database.Stateful instance fields instead. A hop's
     * only job is "begin the next configured type, or complete the run" — exactly
     * ADR-0004's original chain model.
     */
    private final Id scanRunId;
    private final List<String> remainingMetadataTypes;

    public OI_ScanOrchestratorQueueable(Id scanRunId, List<String> remainingMetadataTypes) {
        this.scanRunId = scanRunId;
        this.remainingMetadataTypes = remainingMetadataTypes;
    }

    /**
     * Creates the Scan Run, resolves the enabled (optionally overridden) type list from
     * the Scanner Registry, and enqueues the first hop. Backs OI_ScanController.startScan
     * (API.md §2.4). Enforces the single-flight guard (MetadataScanner.md §13): rejects a
     * new scan while one is already Running, protecting the shared API budget from two
     * runs consuming it simultaneously in an unpredictable order.
     */
    public static Id startScan(String scanType, List<String> metadataTypeOverride) {
        OI_SecurityService.assertPermission('OI_Run_Scan');
        assertNoScanCurrentlyRunning();

        List<OI_Metadata_Type_Config__mdt> configs = loadEnabledConfigs(metadataTypeOverride);

        OI_Scan_Run__c run = new OI_Scan_Run__c(
            Status__c = DEFAULT_STARTING_STATUS,
            Scan_Type__c = String.isBlank(scanType) ? 'Full' : scanType,
            Started_At__c = Datetime.now(),
            Triggered_By__c = UserInfo.getUserId(),
            Metadata_Types_Included__c = joinTypeNames(configs)
        );
        insert run;
        publishProgress(run.Id, STATUS_RUNNING, null, 'Scan started.');

        List<String> orderedTypes = new List<String>();
        for (OI_Metadata_Type_Config__mdt config : configs) {
            orderedTypes.add(config.Metadata_Type_Api_Name__c);
        }

        if (orderedTypes.isEmpty()) {
            completeRun(run.Id);
        } else {
            try {
                System.enqueueJob(new OI_ScanOrchestratorQueueable(run.Id, orderedTypes));
            } catch (Exception e) {
                logChainFailure(run.Id, e);
                safelyCompleteRun(run.Id);
            }
        }
        return run.Id;
    }

    /** Backs OI_ScanController.getScanStatus (API.md §2.4). */
    public static OI_Scan_Run__c getScanStatus(Id scanRunId) {
        OI_SecurityService.assertPermission('OI_Run_Scan');
        List<OI_Scan_Run__c> runs = [
            SELECT Id, Status__c, Scan_Type__c, Started_At__c, Completed_At__c, Node_Count__c, Edge_Count__c, Error_Count__c, Metadata_Types_Included__c
            FROM OI_Scan_Run__c
            WHERE Id = :scanRunId
            LIMIT 1
        ];
        if (runs.isEmpty()) {
            throw new OI_ValidationException('No scan run found for Id ' + scanRunId + '.');
        }
        return runs[0];
    }

    /** Backs OI_ScanController.getScanHistory (API.md §2.4). pageCursor is the CreatedDate of the last row of the previous page. */
    public static List<OI_Scan_Run__c> getScanHistory(Integer pageSize, String pageCursor) {
        OI_SecurityService.assertPermission('OI_Run_Scan');
        Integer effectivePageSize = pageSize == null ? 20 : pageSize;
        if (String.isBlank(pageCursor)) {
            return [
                SELECT Id, Status__c, Scan_Type__c, Started_At__c, Completed_At__c, Node_Count__c, Edge_Count__c, Error_Count__c, Metadata_Types_Included__c
                FROM OI_Scan_Run__c
                ORDER BY CreatedDate DESC
                LIMIT :effectivePageSize
            ];
        }
        Datetime cursorDatetime = Datetime.valueOf(pageCursor);
        return [
            SELECT Id, Status__c, Scan_Type__c, Started_At__c, Completed_At__c, Node_Count__c, Edge_Count__c, Error_Count__c, Metadata_Types_Included__c
            FROM OI_Scan_Run__c
            WHERE CreatedDate < :cursorDatetime
            ORDER BY CreatedDate DESC
            LIMIT :effectivePageSize
        ];
    }

    /**
     * Backs OI_ScanController.cancelScan (API.md §2.4) — best-effort: the in-flight
     * chained Queueable hop completes; the next hop checks this run's status at the top of
     * execute() and stops chaining rather than continuing.
     */
    public static void cancelScan(Id scanRunId) {
        OI_SecurityService.assertPermission('OI_Run_Scan');
        List<OI_Scan_Run__c> runs = [SELECT Status__c FROM OI_Scan_Run__c WHERE Id = :scanRunId LIMIT 1];
        if (runs.isEmpty()) {
            throw new OI_ValidationException('No scan run found for Id ' + scanRunId + '.');
        }
        if (runs[0].Status__c != STATUS_RUNNING) {
            throw new OI_ValidationException('Only a Running scan can be cancelled (current status: ' + runs[0].Status__c + ').');
        }
        update new OI_Scan_Run__c(Id = scanRunId, Status__c = STATUS_CANCELLED, Completed_At__c = Datetime.now());
        publishProgress(scanRunId, STATUS_CANCELLED, null, 'Scan cancelled by user request.');
    }

    public void execute(QueueableContext context) {
        if (isRunCancelled()) {
            return;
        }
        if (remainingMetadataTypes == null || remainingMetadataTypes.isEmpty()) {
            completeRun(scanRunId);
            return;
        }
        List<String> workingList = remainingMetadataTypes.clone();
        String metadataTypeApiName = workingList.remove(0);
        beginScanTask(metadataTypeApiName, workingList);
    }

    /** A Cancelled run simply stops chaining — no further type is begun. Any type already dispatched to a Batchable runs to completion (best-effort, API.md §2.4). */
    private Boolean isRunCancelled() {
        List<OI_Scan_Run__c> runs = [SELECT Status__c FROM OI_Scan_Run__c WHERE Id = :scanRunId LIMIT 1];
        return !runs.isEmpty() && runs[0].Status__c == STATUS_CANCELLED;
    }

    /**
     * Runs the Scanner once (one bounded unit of Describe/SOQL work). A batch that
     * already fits within one CHUNK_SIZE-bounded commit unit is ingested inline, in this
     * same hop — avoiding an unnecessary extra async round-trip for the common case (most
     * metadata types, most orgs). A batch whose components or relationships exceed
     * CHUNK_SIZE is dispatched to OI_ScanComponentIngestBatchable (Sprint 9.1) — Batch Apex
     * execute()/finish() invocations are not tracked by the same chain-depth counter
     * Queueable's System.enqueueJob-from-execute() recursion is, so a type of any
     * real-world size no longer consumes the inter-type Queueable chain's depth budget.
     * This is exactly the "very large individual metadata types may additionally use
     * Batch Apex... for record-level chunking" allowance ADR-0004 already made, realized
     * at the Orchestrator layer. Retire-detection (finalizeTypeAfterIngest, below) gets the
     * identical treatment for the identical reason.
     */
    private void beginScanTask(String metadataTypeApiName, List<String> remainingTypesAfterThis) {
        OI_Scan_Task__c task = new OI_Scan_Task__c(Scan_Run__c = scanRunId, Metadata_Type__c = metadataTypeApiName, Status__c = STATUS_RUNNING);
        try {
            insert task;
        } catch (Exception e) {
            // No task row exists to mark Failed (the insert itself is what failed — e.g.
            // STORAGE_LIMIT_EXCEEDED, a validation rule, any DML failure) — this real
            // rescan found this uncaught exception would otherwise escape execute()
            // entirely, permanently deadlocking the single-flight guard exactly like the
            // enqueue-call-site gaps Sprint 9 already fixed. Log and advance instead.
            logChainFailure(scanRunId, e);
            advanceToNextType(scanRunId, remainingTypesAfterThis);
            return;
        }
        publishProgress(scanRunId, STATUS_RUNNING, metadataTypeApiName, 'Scanning ' + metadataTypeApiName + '...');

        try {
            OI_Metadata_Type_Config__mdt config = loadConfig(metadataTypeApiName);
            OI_IMetadataScanner scanner = resolveScanner(metadataTypeApiName, config.Scanner_Class__c);
            Integer batchSize = config.Batch_Size__c == null ? 100 : Integer.valueOf(config.Batch_Size__c);
            OI_DiscoveryBatch batch = scanner.scan(new OI_ScanContext(task.Id, batchSize, null, config.Preferred_Api__c));

            if (batch.components.size() <= CHUNK_SIZE && batch.relationships.size() <= CHUNK_SIZE) {
                ingestSmallBatchThenAdvance(metadataTypeApiName, task.Id, batch, remainingTypesAfterThis);
                return;
            }

            Database.executeBatch(
                new OI_ScanComponentIngestBatchable(
                    scanRunId,
                    task.Id,
                    metadataTypeApiName,
                    batch.components,
                    batch.relationships,
                    batch.isFullSnapshot,
                    remainingTypesAfterThis
                ),
                CHUNK_SIZE
            );
        } catch (Exception e) {
            failTaskAndAdvance(scanRunId, task.Id, metadataTypeApiName, remainingTypesAfterThis, e);
        }
    }

    /** The single-hop-inline path: ingest, then attempt retire-detection's first page inline before deciding whether another hop is needed. */
    private void ingestSmallBatchThenAdvance(String metadataTypeApiName, Id scanTaskId, OI_DiscoveryBatch batch, List<String> remainingTypesAfterThis) {
        OI_DiscoveryBatch noAutoRetireBatch = new OI_DiscoveryBatch(batch.scanTaskId, batch.componentKind, batch.components, batch.relationships, false, batch.apiCallsConsumed);
        OI_MutationGenerator generator = new OI_MutationGenerator();
        Set<String> observed = generator.translateAndIngest(noAutoRetireBatch);
        invalidateImpactCacheFor(generator.consumeIngestDelta());
        finalizeTypeAfterIngest(scanRunId, scanTaskId, metadataTypeApiName, observed, batch.isFullSnapshot, remainingTypesAfterThis);
    }

    /**
     * DE-7: drops cached Impact Analysis results that this ingest just made stale.
     *
     * Called at each ingest site rather than threaded through to the shared completion tail,
     * because the Batch Apex paths construct a fresh OI_MutationGenerator per execute() scope —
     * an instance-accumulated delta cannot survive to finish(), and per-scope invalidation is
     * both correct and idempotent anyway.
     *
     * Deliberately best-effort: a failure to evict cache rows must never fail the scan that
     * produced the data. The cost of a swallowed failure here is a stale cached impact row that
     * still expires on its own TTL; the cost of propagating would be a failed scan task and lost
     * metadata. Logged rather than silently discarded, so the degradation is observable — this
     * is the one place in this class where swallowing is the correct call, and it is narrow.
     */
    public static void invalidateImpactCacheFor(OI_IngestDelta delta) {
        if (delta == null || delta.impactedNodeKeys.isEmpty()) {
            return;
        }
        try {
            new OI_DependencyEngineService().invalidateForScanDelta(delta.impactedNodeKeys);
        } catch (Exception e) {
            new OI_LoggerService().error(
                'Impact Analysis cache invalidation failed for ' + delta.impactedNodeKeys.size() + ' changed node(s): ' + e.getMessage(),
                'OI_ScanOrchestratorQueueable',
                null,
                e.getStackTraceString()
            );
        }
    }

    /**
     * Shared finalization for a type whose components/relationships have been fully
     * ingested (inline, or by OI_ScanComponentIngestBatchable/OI_ScanRelationshipIngestBatchable's
     * finish()). For a full-snapshot batch, determines the missing-key set up front (a
     * read-only pass — OI_MutationGenerator.findMissingKeys pages internally but issues no
     * DML, so it is safe to run in this same transaction no matter how large the Active-key
     * population is) and, only if anything is actually missing, dispatches the DML-costly
     * retire step to OI_ScanRetireDetectionBatchable (Sprint 9.1) rather than a further
     * Queueable hop — mirroring beginScanTask's own ingestion dispatch. The common case
     * (nothing missing) completes and advances with zero extra async hops. Public so the
     * two ingestion Batchable classes (Sprint 9.1) can call it from finish() without
     * duplicating this logic.
     */
    public static void finalizeTypeAfterIngest(
        Id scanRunId,
        Id scanTaskId,
        String metadataTypeApiName,
        Set<String> observedNodeKeys,
        Boolean isFullSnapshot,
        List<String> remainingMetadataTypes
    ) {
        try {
            if (isFullSnapshot == true) {
                List<String> missingKeys = new OI_MutationGenerator().findMissingKeys(metadataTypeApiName, observedNodeKeys);
                if (!missingKeys.isEmpty()) {
                    Database.executeBatch(
                        new OI_ScanRetireDetectionBatchable(scanRunId, scanTaskId, metadataTypeApiName, missingKeys, observedNodeKeys.size(), remainingMetadataTypes),
                        CHUNK_SIZE
                    );
                    return;
                }
            }
            completeTypeAndAdvance(scanRunId, scanTaskId, metadataTypeApiName, observedNodeKeys.size(), isFullSnapshot, remainingMetadataTypes);
        } catch (Exception e) {
            failTaskAndAdvance(scanRunId, scanTaskId, metadataTypeApiName, remainingMetadataTypes, e);
        }
    }

    /**
     * The tail every successful path (inline, ingestion-Batchable, or
     * OI_ScanRetireDetectionBatchable) converges on: mark the task Succeeded, publish
     * progress, advance the chain. Public so OI_ScanRetireDetectionBatchable's finish()
     * can call it directly once retirement is done, without re-running retire-detection
     * (which finalizeTypeAfterIngest itself would do if called again).
     */
    public static void completeTypeAndAdvance(Id scanRunId, Id scanTaskId, String metadataTypeApiName, Integer recordsScanned, Boolean isFullSnapshot, List<String> remainingMetadataTypes) {
        completeTask(scanTaskId, isFullSnapshot, recordsScanned);
        publishProgress(scanRunId, STATUS_RUNNING, metadataTypeApiName, metadataTypeApiName + ' scan complete.');
        advanceToNextType(scanRunId, remainingMetadataTypes);
    }

    private static void completeTask(Id scanTaskId, Boolean isFullSnapshot, Integer recordsScanned) {
        update new OI_Scan_Task__c(Id = scanTaskId, Status__c = 'Succeeded', Is_Full_Snapshot__c = isFullSnapshot, Records_Scanned__c = recordsScanned);
    }

    /**
     * Never lets a failure to advance escape uncaught (Sprint 9 validation finding):
     * Developer Edition/trial orgs enforce a real, low ceiling on total chained Queueable
     * depth. Production/sandbox orgs (Enterprise/Unlimited/Performance/Professional — what
     * this package actually ships to) do not enforce this ceiling, but ANY transient
     * failure to advance (governor limit, platform hiccup) would hit the identical failure
     * mode regardless of edition. Left uncaught, the run stays Running forever, which would
     * permanently block the single-flight guard (§13) from ever allowing another scan —
     * a genuinely serious robustness gap, not just an edition-specific inconvenience. Public
     * so the Batchable classes' finish() methods share this exact recovery path.
     */
    public static void advanceToNextType(Id scanRunId, List<String> remainingTypes) {
        if (remainingTypes == null || remainingTypes.isEmpty()) {
            safelyCompleteRun(scanRunId);
            return;
        }
        try {
            System.enqueueJob(new OI_ScanOrchestratorQueueable(scanRunId, remainingTypes));
        } catch (Exception e) {
            logChainFailure(scanRunId, e);
            safelyCompleteRun(scanRunId);
        }
    }

    /** completeRun's own DML is a straightforward query+update — failure here is not the scenario this guards against, but the "never leave it stuck" guarantee should hold regardless of why. */
    private static void safelyCompleteRun(Id scanRunId) {
        try {
            completeRun(scanRunId);
        } catch (Exception e) {
            logChainFailure(scanRunId, e);
        }
    }

    private static void logChainFailure(Id scanRunId, Exception e) {
        new OI_LoggerService().error(
            'Scan run ' + scanRunId + ' could not continue: ' + e.getMessage(),
            'OI_ScanOrchestratorQueueable',
            String.valueOf(scanRunId),
            e.getStackTraceString()
        );
    }

    /**
     * Marks the task Failed, logs it, and advances the chain so one type's failure never
     * blocks the rest of the run — the same isolation guarantee MetadataScanner.md §14 has
     * always required, now shared by the Queueable path and both Batchable classes' catch
     * blocks (Sprint 9.1) via this single entry point. Updates only Id + the status fields
     * — deliberately never reuses a fully-populated OI_Scan_Task__c instance, since Apex
     * DML sends every field ever assigned on an sObject instance (a real bug closed during
     * Sprint 8 validation — reusing the insert()-ed instance re-sent Scan_Run__c, the
     * Master-Detail field, on every failure update, producing an FLS error).
     */
    public static void failTaskAndAdvance(Id scanRunId, Id scanTaskId, String metadataTypeApiName, List<String> remainingTypes, Exception e) {
        update new OI_Scan_Task__c(Id = scanTaskId, Status__c = 'Failed', Error_Message__c = e.getMessage());
        publishProgress(scanRunId, STATUS_RUNNING, metadataTypeApiName, metadataTypeApiName + ' scan failed.');
        new OI_LoggerService().error(
            'Scan task ' + scanTaskId + ' failed: ' + e.getMessage(),
            'OI_ScanOrchestratorQueueable',
            String.valueOf(scanRunId),
            e.getStackTraceString()
        );
        advanceToNextType(scanRunId, remainingTypes);
    }

    private OI_IMetadataScanner resolveScanner(String metadataTypeApiName, String scannerClassName) {
        if (testScannerOverrides.containsKey(metadataTypeApiName)) {
            return testScannerOverrides.get(metadataTypeApiName);
        }
        Type scannerType = Type.forName(scannerClassName);
        if (scannerType == null) {
            throw new OI_ServiceException('Scanner_Class__c "' + scannerClassName + '" could not be resolved via Type.forName.');
        }
        return (OI_IMetadataScanner) scannerType.newInstance();
    }

    private OI_Metadata_Type_Config__mdt loadConfig(String metadataTypeApiName) {
        List<OI_Metadata_Type_Config__mdt> configs = [
            SELECT Scanner_Class__c, Batch_Size__c, Preferred_Api__c
            FROM OI_Metadata_Type_Config__mdt
            WHERE Metadata_Type_Api_Name__c = :metadataTypeApiName AND Enabled__c = true
            LIMIT 1
        ];
        if (configs.isEmpty()) {
            throw new OI_ServiceException('No enabled OI_Metadata_Type_Config__mdt record found for "' + metadataTypeApiName + '".');
        }
        return configs[0];
    }

    private static void assertNoScanCurrentlyRunning() {
        List<OI_Scan_Run__c> runningRuns = [SELECT Id FROM OI_Scan_Run__c WHERE Status__c = :STATUS_RUNNING LIMIT 1];
        if (!runningRuns.isEmpty()) {
            throw new OI_ServiceException('A scan is already running. Wait for it to complete, or cancel it, before starting a new one.');
        }
    }

    /** Completes the Scan Run with an aggregate status — CompletedWithErrors if any task failed, Completed otherwise. */
    private static void completeRun(Id scanRunId) {
        List<OI_Scan_Task__c> tasks = [SELECT Status__c, Records_Scanned__c FROM OI_Scan_Task__c WHERE Scan_Run__c = :scanRunId];
        Boolean anyFailed = false;
        Integer totalScanned = 0;
        Integer errorCount = 0;
        for (OI_Scan_Task__c completedTask : tasks) {
            if (completedTask.Status__c == 'Failed') {
                anyFailed = true;
                errorCount++;
            }
            if (completedTask.Records_Scanned__c != null) {
                totalScanned += Integer.valueOf(completedTask.Records_Scanned__c);
            }
        }
        String finalStatus = anyFailed ? 'CompletedWithErrors' : 'Completed';
        update new OI_Scan_Run__c(
            Id = scanRunId,
            Status__c = finalStatus,
            Completed_At__c = Datetime.now(),
            Node_Count__c = totalScanned,
            Error_Count__c = errorCount
        );
        publishProgress(scanRunId, finalStatus, null, anyFailed ? 'Scan completed with errors.' : 'Scan completed.');
    }

    private static List<OI_Metadata_Type_Config__mdt> loadEnabledConfigs(List<String> metadataTypeOverride) {
        List<OI_Metadata_Type_Config__mdt> configs = [
            SELECT Metadata_Type_Api_Name__c, Priority__c
            FROM OI_Metadata_Type_Config__mdt
            WHERE Enabled__c = true
            ORDER BY Priority__c ASC NULLS LAST
        ];
        if (metadataTypeOverride == null || metadataTypeOverride.isEmpty()) {
            return configs;
        }
        Set<String> overrideSet = new Set<String>(metadataTypeOverride);
        List<OI_Metadata_Type_Config__mdt> filtered = new List<OI_Metadata_Type_Config__mdt>();
        for (OI_Metadata_Type_Config__mdt config : configs) {
            if (overrideSet.contains(config.Metadata_Type_Api_Name__c)) {
                filtered.add(config);
            }
        }
        return filtered;
    }

    private static String joinTypeNames(List<OI_Metadata_Type_Config__mdt> configs) {
        List<String> names = new List<String>();
        for (OI_Metadata_Type_Config__mdt config : configs) {
            names.add(config.Metadata_Type_Api_Name__c);
        }
        return String.join(names, ', ');
    }

    /** Minimal payload by design (Sprint 9 scope) — this is a UI progress signal, not an audit log. */
    private static void publishProgress(Id scanRunId, String status, String metadataType, String message) {
        EventBus.publish(
            new OI_Scan_Progress__e(Scan_Run_Id__c = String.valueOf(scanRunId), Status__c = status, Metadata_Type__c = metadataType, Message__c = message)
        );
    }
}
