/**
 * Purpose: Verifies OI_ScanOrchestratorQueueable's Scan Run / Scan Task lifecycle,
 *          metadataTypeOverride filtering, and no-op behavior when nothing is enabled
 *          (MetadataScanner.md §14, Sprint 8 objective §8).
 * Limitations: Every test here injects OI_FakeMetadataScanner via
 *              OI_ScanOrchestratorQueueable.testScannerOverrides with a small component
 *              count (well under CHUNK_SIZE), rather than letting the real, registered
 *              OI_ApexClassScanner run (this org alone has 796 deployed Apex classes) or
 *              driving a batch large enough to reach OI_ScanComponentIngestBatchable
 *              (Sprint 9.1) — confirmed empirically while building this suite:
 *              Database.executeBatch, called from within an already-executing Queueable's
 *              execute() (beginScanTask), throws "No more than one executeBatch can be
 *              called from within a test method" once that Queueable is drained via
 *              Test.stopTest(). This is a genuine Apex-test-harness-only restriction on
 *              the Queueable-calls-executeBatch combination specifically — it does not
 *              describe production behavior (Queueable-to-Batch-Apex handoff is standard,
 *              unrestricted platform behavior outside test context), and calling
 *              Database.executeBatch directly from a test method's own top-level code
 *              (including from a chained finish()) is unaffected, see
 *              OI_ScanComponentIngestBatchableTest/OI_ScanRelationshipIngestBatchableTest,
 *              which exercise exactly that and pass. Multi-scope ingestion correctness is
 *              proven directly against those Batchable classes;
 *              beginScanTask's dispatch decision itself (batch.components.size() >
 *              CHUNK_SIZE -> Database.executeBatch) is proven by code inspection plus the
 *              mandatory real sandbox scan (Sprint 9.1 deliverables report) — mirroring
 *              exactly how Sprint 8/9 handled the analogous Queueable
 *              chain-depth-in-tests limitation for the design this replaces.
 *              Real-Scanner correctness against actual org metadata is proven
 *              independently and directly, with no chaining involved
 *              (OI_ObjectScannerTest/OI_FieldScannerTest/OI_ApexClassScannerTest each call
 *              scan() once, synchronously); this class exists purely to prove Orchestrator
 *              lifecycle mechanics, which are Scanner-implementation-agnostic by design
 *              (MetadataScanner.md §14). A forced, deterministic scanner-failure path
 *              (Failed task -> CompletedWithErrors run) is not exercised here — flagged as
 *              a Sprint 10 testability follow-up alongside per-type cadence and incremental
 *              watermarking.
 */
@isTest
private class OI_ScanOrchestratorQueueableTest {
    @isTest
    static void testStartScanCompletesTheRunWithMetadataTypesIncludedRecorded() {
        OI_ScanOrchestratorQueueable.testScannerOverrides.put('ApexClass', new OI_FakeMetadataScanner(5, true));

        Test.startTest();
        Id runId = OI_ScanOrchestratorQueueable.startScan('Full', new List<String>{ 'ApexClass' });
        Test.stopTest();

        OI_Scan_Run__c run = [SELECT Status__c, Completed_At__c, Metadata_Types_Included__c FROM OI_Scan_Run__c WHERE Id = :runId];
        System.assertEquals('Completed', run.Status__c);
        System.assertNotEquals(null, run.Completed_At__c);
        System.assertEquals('ApexClass', run.Metadata_Types_Included__c);

        OI_Scan_Task__c task = [SELECT Metadata_Type__c, Status__c FROM OI_Scan_Task__c WHERE Scan_Run__c = :runId LIMIT 1];
        System.assertEquals('ApexClass', task.Metadata_Type__c);
    }

    @isTest
    static void testMetadataTypeOverrideRestrictsTheScanToOnlyThatType() {
        OI_ScanOrchestratorQueueable.testScannerOverrides.put('ApexClass', new OI_FakeMetadataScanner(3, true));

        Test.startTest();
        Id runId = OI_ScanOrchestratorQueueable.startScan('Full', new List<String>{ 'ApexClass' });
        Test.stopTest();

        List<OI_Scan_Task__c> tasks = [SELECT Metadata_Type__c FROM OI_Scan_Task__c WHERE Scan_Run__c = :runId];
        System.assertEquals(1, tasks.size());
        System.assertEquals('ApexClass', tasks[0].Metadata_Type__c);
    }

    @isTest
    static void testOverrideMatchingNoEnabledTypeCompletesImmediatelyWithNoTasks() {
        Id runId = OI_ScanOrchestratorQueueable.startScan('Full', new List<String>{ 'DoesNotExistType' });

        OI_Scan_Run__c run = [SELECT Status__c FROM OI_Scan_Run__c WHERE Id = :runId];
        System.assertEquals('Completed', run.Status__c);
        System.assertEquals(0, [SELECT COUNT() FROM OI_Scan_Task__c WHERE Scan_Run__c = :runId]);
    }

    @isTest
    static void testSuccessfulTaskRecordsIsFullSnapshotAndRecordsScanned() {
        OI_ScanOrchestratorQueueable.testScannerOverrides.put('ApexClass', new OI_FakeMetadataScanner(7, true));

        Test.startTest();
        Id runId = OI_ScanOrchestratorQueueable.startScan('Full', new List<String>{ 'ApexClass' });
        Test.stopTest();

        OI_Scan_Task__c task = [
            SELECT Status__c, Is_Full_Snapshot__c, Records_Scanned__c, Error_Message__c
            FROM OI_Scan_Task__c
            WHERE Scan_Run__c = :runId
            LIMIT 1
        ];
        System.assertEquals('Succeeded', task.Status__c, 'Error_Message__c: ' + task.Error_Message__c);
        System.assertEquals(true, task.Is_Full_Snapshot__c);
        System.assertEquals(7, task.Records_Scanned__c);
    }

    // --- Sprint 9 additions: single-flight guard, cancellation, status/history reads ---

    @isTest
    static void testStartScanWhileAnotherIsRunningThrowsServiceException() {
        OI_ScanOrchestratorQueueable.testScannerOverrides.put('ApexClass', new OI_FakeMetadataScanner(3, true));
        OI_ScanOrchestratorQueueable.startScan('Full', new List<String>{ 'ApexClass' });

        try {
            OI_ScanOrchestratorQueueable.startScan('Full', new List<String>{ 'ApexClass' });
            System.assert(false, 'Expected the single-flight guard to reject a second concurrent scan.');
        } catch (OI_ServiceException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testStartScanSucceedsAfterThePreviousRunHasCompleted() {
        OI_ScanOrchestratorQueueable.testScannerOverrides.put('ApexClass', new OI_FakeMetadataScanner(3, true));
        Test.startTest();
        Id firstRunId = OI_ScanOrchestratorQueueable.startScan('Full', new List<String>{ 'ApexClass' });
        Test.stopTest();

        Id secondRunId = OI_ScanOrchestratorQueueable.startScan('Full', new List<String>{ 'ApexClass' });
        System.assertNotEquals(firstRunId, secondRunId);
    }

    /**
     * Calls execute() directly rather than via System.enqueueJob/Test.stopTest() — safe
     * here specifically because a Cancelled run's execute() returns immediately without
     * enqueueing anything further (see OI_ScanOrchestratorQueueable.execute), so this
     * exercises the real cancellation-check code path with zero chain-depth risk.
     */
    @isTest
    static void testExecuteOnCancelledRunDoesNotStartAnyScanTask() {
        OI_Scan_Run__c run = OI_TestDataFactory.newScanRun();
        run.Status__c = 'Cancelled';
        insert run;

        OI_ScanOrchestratorQueueable orchestrator = new OI_ScanOrchestratorQueueable(run.Id, new List<String>{ 'ApexClass' });
        orchestrator.execute(null);

        System.assertEquals(0, [SELECT COUNT() FROM OI_Scan_Task__c WHERE Scan_Run__c = :run.Id], 'A cancelled run must not start any new scan task.');
    }

    @isTest
    static void testCancelScanTransitionsRunningRunToCancelled() {
        OI_ScanOrchestratorQueueable.testScannerOverrides.put('ApexClass', new OI_FakeMetadataScanner(3, true));
        Id runId = OI_ScanOrchestratorQueueable.startScan('Full', new List<String>{ 'ApexClass' });

        OI_ScanOrchestratorQueueable.cancelScan(runId);

        System.assertEquals('Cancelled', OI_ScanOrchestratorQueueable.getScanStatus(runId).Status__c);
    }

    @isTest
    static void testCancelScanOnNonRunningRunThrowsValidationException() {
        OI_Scan_Run__c completedRun = OI_TestDataFactory.newScanRun();
        completedRun.Status__c = 'Completed';
        insert completedRun;

        try {
            OI_ScanOrchestratorQueueable.cancelScan(completedRun.Id);
            System.assert(false, 'Expected OI_ValidationException — only a Running scan can be cancelled.');
        } catch (OI_ValidationException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testGetScanStatusThrowsForUnknownId() {
        OI_Scan_Run__c placeholder = OI_TestDataFactory.newScanRun();
        insert placeholder;
        Id fakeId = placeholder.Id;
        delete placeholder;

        try {
            OI_ScanOrchestratorQueueable.getScanStatus(fakeId);
            System.assert(false, 'Expected OI_ValidationException for a scan run that does not exist.');
        } catch (OI_ValidationException e) {
            System.assert(true);
        }
    }

    /**
     * Uses a deliberately-future and deliberately-past cursor rather than chaining off a
     * just-inserted row's own CreatedDate — records inserted moments apart within the same
     * test transaction can legitimately share an identical CreatedDate timestamp, which
     * would make a strict "<" comparison against one row's own timestamp flaky.
     */
    @isTest
    static void testGetScanHistoryFiltersStrictlyOlderThanTheCursor() {
        insert OI_TestDataFactory.newScanRun();
        insert OI_TestDataFactory.newScanRun();

        List<OI_Scan_Run__c> allRows = OI_ScanOrchestratorQueueable.getScanHistory(10, null);
        System.assertEquals(2, allRows.size());

        String futureCursor = String.valueOf(Datetime.now().addDays(1));
        List<OI_Scan_Run__c> pageBeforeFutureCursor = OI_ScanOrchestratorQueueable.getScanHistory(10, futureCursor);
        System.assertEquals(2, pageBeforeFutureCursor.size(), 'A cursor in the future must include every existing row.');

        String pastCursor = String.valueOf(Datetime.newInstanceGmt(2000, 1, 1, 0, 0, 0));
        List<OI_Scan_Run__c> pageAfterPastCursor = OI_ScanOrchestratorQueueable.getScanHistory(10, pastCursor);
        System.assertEquals(0, pageAfterPastCursor.size(), 'A cursor before every row must exclude everything.');
    }
}
