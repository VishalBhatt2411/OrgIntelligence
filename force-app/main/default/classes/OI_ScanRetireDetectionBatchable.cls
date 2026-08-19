/**
 * Purpose: Governor-safe retirement of a large missing-key wave for a full-snapshot
 *          metadata type (Sprint 9.1, second pass — ADR-0004 amendment) — the retire-
 *          detection counterpart of OI_ScanComponentIngestBatchable/
 *          OI_ScanRelationshipIngestBatchable, replacing MS-4b's Queueable-paged retire
 *          resume (which shared, and re-triggered, the Developer Edition Queueable
 *          chain-depth ceiling this whole fix exists to remove).
 * Responsibilities: Retire exactly the missingKeys list (already identified, read-only,
 *                    by OI_MutationGenerator.findMissingKeys before this job was
 *                    dispatched) in CHUNK_SIZE-sized scopes via
 *                    OI_MutationGenerator.retireKeys; on finish(), hand off to
 *                    OI_ScanOrchestratorQueueable.completeTypeAndAdvance.
 * Dependencies: OI_MutationGenerator, OI_ScanOrchestratorQueueable (CHUNK_SIZE,
 *               completeTypeAndAdvance, failTaskAndAdvance).
 * Limitations: missingKeys is materialized up front by the caller (finalizeTypeAfterIngest)
 *              via one read-only pass — safe regardless of size since it issues no DML,
 *              only the same paginated reads getCurrentActiveKeysByType always bounds. A
 *              chunk-retirement failure is isolated to this Scan Task, matching the
 *              existing per-task retry granularity (MetadataScanner.md §14) — the failed
 *              scope is not retried.
 */
public without sharing class OI_ScanRetireDetectionBatchable implements Database.Batchable<String>, Database.Stateful {
    private final Id scanRunId;
    private final Id scanTaskId;
    private final String metadataTypeApiName;
    private final List<String> missingKeys;
    private final Integer recordsScanned;
    private final List<String> remainingMetadataTypes;

    private Boolean hadFailure = false;
    private Exception failure;

    public OI_ScanRetireDetectionBatchable(
        Id scanRunId,
        Id scanTaskId,
        String metadataTypeApiName,
        List<String> missingKeys,
        Integer recordsScanned,
        List<String> remainingMetadataTypes
    ) {
        this.scanRunId = scanRunId;
        this.scanTaskId = scanTaskId;
        this.metadataTypeApiName = metadataTypeApiName;
        this.missingKeys = missingKeys;
        this.recordsScanned = recordsScanned;
        this.remainingMetadataTypes = remainingMetadataTypes;
    }

    public Iterable<String> start(Database.BatchableContext bc) {
        return missingKeys;
    }

    public void execute(Database.BatchableContext bc, List<String> scope) {
        if (hadFailure) {
            return;
        }
        try {
            new OI_MutationGenerator().retireKeys(scope, scanRunId);
        } catch (Exception e) {
            hadFailure = true;
            failure = e;
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (hadFailure) {
            OI_ScanOrchestratorQueueable.failTaskAndAdvance(scanRunId, scanTaskId, metadataTypeApiName, remainingMetadataTypes, failure);
            return;
        }
        OI_ScanOrchestratorQueueable.completeTypeAndAdvance(scanRunId, scanTaskId, metadataTypeApiName, recordsScanned, true, remainingMetadataTypes);
    }
}
