/**
 * Purpose: Verifies OI_ScanRelationshipIngestBatchable ingests its scoped relationships,
 *          carries the incoming observedNodeKeys through unchanged (Sprint 9.1 — a
 *          relationships-only ingest never derives new nodeKeys, MetadataScanner.md §15),
 *          and finalizes the Scan Task/Run.
 */
@isTest
private class OI_ScanRelationshipIngestBatchableTest {
    @isTest
    static void testRelationshipBatchIngestsAndPreservesCarriedOverObservedNodeKeys() {
        OI_Scan_Run__c run = OI_TestDataFactory.newScanRun();
        run.Status__c = 'Running';
        insert run;
        OI_Scan_Task__c task = new OI_Scan_Task__c(Scan_Run__c = run.Id, Metadata_Type__c = 'FakeKind', Status__c = 'Running');
        insert task;

        String parentKey = OI_ComponentKeyUtil.build('FakeKind', null, 'Parent');
        String childKey = OI_ComponentKeyUtil.build('FakeKind', null, 'Child');
        List<OI_DiscoveredComponent> seedComponents = new List<OI_DiscoveredComponent>{
            new OI_DiscoveredComponent(parentKey, 'FakeKind', 'Parent', null, 'Fake', new Map<String, Object>(), 'p', null, null),
            new OI_DiscoveredComponent(childKey, 'FakeKind', 'Child', null, 'Fake', new Map<String, Object>(), 'c', null, null)
        };
        Set<String> observedNodeKeys = new OI_MutationGenerator().translateAndIngest(new OI_DiscoveryBatch(task.Id, 'FakeKind', seedComponents, new List<OI_DiscoveredRelationship>(), false, 0));
        System.assertEquals(2, observedNodeKeys.size(), 'Precondition: the component phase observed exactly the 2 seeded nodeKeys.');

        List<OI_DiscoveredRelationship> relationships = new List<OI_DiscoveredRelationship>{
            new OI_DiscoveredRelationship('rk1', 'FAKE_RELATES_TO', parentKey, childKey, new Map<String, Object>())
        };

        Test.startTest();
        Database.executeBatch(new OI_ScanRelationshipIngestBatchable(run.Id, task.Id, 'FakeKind', relationships, false, observedNodeKeys, new List<String>()), 60);
        Test.stopTest();

        OI_Scan_Task__c completedTask = [SELECT Status__c, Records_Scanned__c, Error_Message__c FROM OI_Scan_Task__c WHERE Id = :task.Id];
        System.assertEquals('Succeeded', completedTask.Status__c, 'Error_Message__c: ' + completedTask.Error_Message__c);
        System.assertEquals(2, completedTask.Records_Scanned__c, 'Records_Scanned__c must reflect the carried-over observedNodeKeys, not the relationship count.');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM OI_Graph_Edge__c WHERE Edge_Type__c = 'SalesforceMetadata.FAKE_RELATES_TO' AND Is_Current__c = true]
        );
        System.assertEquals('Completed', [SELECT Status__c FROM OI_Scan_Run__c WHERE Id = :run.Id].Status__c);
    }
}
