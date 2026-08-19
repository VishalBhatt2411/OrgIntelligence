/**
 * Purpose: Verifies OI_ScanRetireDetectionBatchable retires exactly its scoped
 *          missingKeys (Sprint 9.1, second pass) and finalizes the Scan Task/Run via
 *          OI_ScanOrchestratorQueueable.completeTypeAndAdvance — the fix for the real
 *          rescan finding that retire-detection's original Queueable-paged design
 *          re-triggered the Developer Edition chain-depth ceiling this sprint exists to
 *          remove.
 */
@isTest
private class OI_ScanRetireDetectionBatchableTest {
    @isTest
    static void testRetireDetectionBatchRetiresOnlyTheMissingKeyAndLeavesTheObservedKeyActive() {
        OI_Scan_Run__c run = OI_TestDataFactory.newScanRun();
        run.Status__c = 'Running';
        insert run;
        OI_Scan_Task__c task = new OI_Scan_Task__c(Scan_Run__c = run.Id, Metadata_Type__c = 'FakeKind', Status__c = 'Running');
        insert task;

        String keptComponentKey = OI_ComponentKeyUtil.build('FakeKind', null, 'Kept');
        String removedComponentKey = OI_ComponentKeyUtil.build('FakeKind', null, 'Removed');
        List<OI_DiscoveredComponent> firstScanComponents = new List<OI_DiscoveredComponent>{
            new OI_DiscoveredComponent(keptComponentKey, 'FakeKind', 'Kept', null, 'Fake', new Map<String, Object>(), 'k', null, null),
            new OI_DiscoveredComponent(removedComponentKey, 'FakeKind', 'Removed', null, 'Fake', new Map<String, Object>(), 'r', null, null)
        };
        Set<String> firstScanObserved = new OI_MutationGenerator().translateAndIngest(
            new OI_DiscoveryBatch(task.Id, 'FakeKind', firstScanComponents, new List<OI_DiscoveredRelationship>(), false, 0)
        );
        System.assertEquals(2, firstScanObserved.size());

        // translateAndIngest returns real nodeKeys (SHA-256 digests), not the raw componentKey
        // strings used above to construct OI_DiscoveredComponent — query the persisted rows to
        // get the actual identity findMissingKeys compares against.
        String keptKey = [SELECT Node_Key__c FROM OI_Graph_Node__c WHERE Node_Type__c = 'SalesforceMetadata.FakeKind' AND Secondary_Key__c = 'Kept' AND Is_Current__c = true LIMIT 1].Node_Key__c;
        String removedKey = [SELECT Node_Key__c FROM OI_Graph_Node__c WHERE Node_Type__c = 'SalesforceMetadata.FakeKind' AND Secondary_Key__c = 'Removed' AND Is_Current__c = true LIMIT 1].Node_Key__c;

        Set<String> secondScanObserved = new Set<String>{ keptKey };
        List<String> missingKeys = new OI_MutationGenerator().findMissingKeys('FakeKind', secondScanObserved);
        System.assertEquals(1, missingKeys.size());
        System.assertEquals(removedKey, missingKeys[0]);

        Test.startTest();
        Database.executeBatch(new OI_ScanRetireDetectionBatchable(run.Id, task.Id, 'FakeKind', missingKeys, secondScanObserved.size(), new List<String>()), 60);
        Test.stopTest();

        OI_Scan_Task__c completedTask = [SELECT Status__c, Records_Scanned__c, Is_Full_Snapshot__c, Error_Message__c FROM OI_Scan_Task__c WHERE Id = :task.Id];
        System.assertEquals('Succeeded', completedTask.Status__c, 'Error_Message__c: ' + completedTask.Error_Message__c);
        System.assertEquals(1, completedTask.Records_Scanned__c, 'Records_Scanned__c must reflect the caller-supplied recordsScanned (the second scan\'s observed count), not missingKeys.size().');
        System.assertEquals(true, completedTask.Is_Full_Snapshot__c);
        System.assertEquals('Completed', [SELECT Status__c FROM OI_Scan_Run__c WHERE Id = :run.Id].Status__c);

        System.assertEquals('Stale', [SELECT State__c FROM OI_Graph_Node__c WHERE Node_Key__c = :removedKey AND Is_Current__c = true].State__c);
        System.assertEquals('Active', [SELECT State__c FROM OI_Graph_Node__c WHERE Node_Key__c = :keptKey AND Is_Current__c = true].State__c);
    }
}
