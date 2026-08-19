/**
 * Purpose: Verifies OI_ScanController's thin permission-check -> call -> DTO-map contract
 *          (API.md §2.4, CodingStandards.md §6/§8).
 * Note: startScan is never wrapped in Test.startTest()/stopTest() here — doing so would
 *       flush the Queueable chain, and this class only needs to verify the synchronous
 *       return value (the Scan Run is created and returned before any hop executes).
 *       Orchestrator lifecycle/chaining behavior is OI_ScanOrchestratorQueueableTest's job.
 *       Every startScan call here injects a small OI_FakeMetadataScanner override for
 *       'ApexClass' (Sprint 9.1) rather than letting the real, 796-class
 *       OI_ApexClassScanner be reachable — confirmed empirically that letting the
 *       Queueable's enqueued job resolve to a batch large enough to reach
 *       OI_ScanComponentIngestBatchable's Database.executeBatch call, even without this
 *       test ever calling Test.stopTest(), triggers "No more than one executeBatch can be
 *       called from within a test method." See OI_ScanOrchestratorQueueableTest's class
 *       doc for the full explanation — this is a test-harness-only restriction, not a
 *       production concern.
 */
@isTest
private class OI_ScanControllerTest {
    @isTest
    static void testStartScanReturnsRunningStatusImmediately() {
        OI_ScanOrchestratorQueueable.testScannerOverrides.put('ApexClass', new OI_FakeMetadataScanner(3, true));
        OI_ScanRunSummaryDTO result = OI_ScanController.startScan('Full', new List<String>{ 'ApexClass' });
        System.assertNotEquals(null, result.scanRunId);
        System.assertEquals('Running', result.status);
        System.assertEquals('ApexClass', result.metadataTypesIncluded);
    }

    @isTest
    static void testStartScanWhileAlreadyRunningThrowsAuraHandledException() {
        OI_ScanOrchestratorQueueable.testScannerOverrides.put('ApexClass', new OI_FakeMetadataScanner(3, true));
        OI_ScanController.startScan('Full', new List<String>{ 'ApexClass' });
        try {
            OI_ScanController.startScan('Full', new List<String>{ 'ApexClass' });
            System.assert(false, 'Expected the single-flight guard to reject a second concurrent scan.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testGetScanStatusReturnsCorrectDto() {
        OI_ScanOrchestratorQueueable.testScannerOverrides.put('ApexClass', new OI_FakeMetadataScanner(3, true));
        OI_ScanRunSummaryDTO started = OI_ScanController.startScan('Full', new List<String>{ 'ApexClass' });
        OI_ScanRunSummaryDTO status = OI_ScanController.getScanStatus(started.scanRunId);
        System.assertEquals(started.scanRunId, status.scanRunId);
        System.assertEquals('Running', status.status);
    }

    @isTest
    static void testGetScanStatusForUnknownIdThrowsAuraHandledException() {
        OI_Scan_Run__c placeholder = OI_TestDataFactory.newScanRun();
        insert placeholder;
        Id fakeId = placeholder.Id;
        delete placeholder;
        try {
            OI_ScanController.getScanStatus(fakeId);
            System.assert(false, 'Expected AuraHandledException for a scan run that no longer exists.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testGetScanHistoryReturnsMostRecentFirst() {
        OI_ScanOrchestratorQueueable.testScannerOverrides.put('ApexClass', new OI_FakeMetadataScanner(3, true));
        OI_ScanController.startScan('Full', new List<String>{ 'ApexClass' });
        List<OI_ScanRunSummaryDTO> history = OI_ScanController.getScanHistory(10, null);
        System.assert(!history.isEmpty());
    }

    @isTest
    static void testCancelScanTransitionsRunningToCancelled() {
        OI_ScanOrchestratorQueueable.testScannerOverrides.put('ApexClass', new OI_FakeMetadataScanner(3, true));
        OI_ScanRunSummaryDTO started = OI_ScanController.startScan('Full', new List<String>{ 'ApexClass' });
        OI_ScanController.cancelScan(started.scanRunId);
        OI_ScanRunSummaryDTO status = OI_ScanController.getScanStatus(started.scanRunId);
        System.assertEquals('Cancelled', status.status);
    }

    @isTest
    static void testCancelScanOnAlreadyTerminalRunThrowsAuraHandledException() {
        OI_Scan_Run__c completedRun = OI_TestDataFactory.newScanRun();
        completedRun.Status__c = 'Completed';
        insert completedRun;
        try {
            OI_ScanController.cancelScan(completedRun.Id);
            System.assert(false, 'Expected AuraHandledException — only a Running scan can be cancelled.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testStartScanWithoutPermissionThrowsAuraHandledException() {
        User unprivileged = createUnprivilegedTestUser();
        System.runAs(unprivileged) {
            try {
                OI_ScanController.startScan('Full', new List<String>{ 'ApexClass' });
                System.assert(false, 'Expected AuraHandledException when OI_Run_Scan is not assigned.');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    private static User createUnprivilegedTestUser() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniqueSuffix = String.valueOf(Crypto.getRandomInteger()).right(8);
        User u = new User(
            FirstName = 'OI Test',
            LastName = 'Unprivileged' + uniqueSuffix,
            Email = 'oi.test.' + uniqueSuffix + '@example.invalid',
            Username = 'oi.test.' + uniqueSuffix + '@example.invalid',
            Alias = 'oitst' + uniqueSuffix.left(3),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = standardProfile.Id
        );
        insert u;
        return u;
    }
}
