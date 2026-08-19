/**
 * Purpose: Verifies OI_CustomObjectStorageProvider's read/write mapping round-trips
 *          correctly against real Custom Object DML (GraphRepository.md §8).
 */
@isTest
private class OI_CustomObjectStorageProviderTest {
    @isTest
    static void testWriteVersionThenReadCurrentRoundTripsNode() {
        OI_CustomObjectStorageProvider provider = new OI_CustomObjectStorageProvider();
        provider.writeVersion(OI_TestDataFactory.newNodeVersionRecord('node1', 1, 'checksumA'), true);
        Map<String, OI_VersionRecord> results = provider.readCurrent(new Set<String>{ 'node1' }, false);
        System.assertEquals(1, results.size());
        System.assertEquals('checksumA', results.get('node1').checksum);
    }

    @isTest
    static void testWriteVersionThenReadCurrentRoundTripsEdge() {
        OI_CustomObjectStorageProvider provider = new OI_CustomObjectStorageProvider();
        provider.writeVersion(OI_TestDataFactory.newEdgeVersionRecord('edge1', 'src1', 'tgt1', 1), true);
        Map<String, OI_VersionRecord> results = provider.readCurrent(new Set<String>{ 'edge1' }, true);
        System.assertEquals(1, results.size());
        System.assertEquals('src1', results.get('edge1').sourceKey);
    }

    @isTest
    static void testMarkSupersededFlipsIsCurrentOnNode() {
        OI_CustomObjectStorageProvider provider = new OI_CustomObjectStorageProvider();
        OI_VersionRecord v1 = OI_TestDataFactory.newNodeVersionRecord('node2', 1, 'c1');
        provider.writeVersion(v1, true);
        provider.markSuperseded(v1.versionKey, false);
        System.assertEquals(0, provider.readCurrent(new Set<String>{ 'node2' }, false).size(), 'Superseded row must no longer be current.');
    }

    @isTest
    static void testTouchLivenessUpdatesLastSeenRun() {
        insert OI_TestDataFactory.newScanRun();
        Id runId = [SELECT Id FROM OI_Scan_Run__c LIMIT 1].Id;
        OI_CustomObjectStorageProvider provider = new OI_CustomObjectStorageProvider();
        provider.writeVersion(OI_TestDataFactory.newNodeVersionRecord('node3', 1, 'c1'), true);
        provider.touchLiveness(new Set<String>{ 'node3' }, runId, false);
        OI_Graph_Node__c row = [SELECT Last_Seen_Run__c FROM OI_Graph_Node__c WHERE Node_Key__c = 'node3'];
        System.assertEquals(runId, row.Last_Seen_Run__c);
    }

    @isTest
    static void testMoveToArchiveThrowsNotImplementedThisSprint() {
        try {
            new OI_CustomObjectStorageProvider().moveToArchive(new List<OI_VersionRecord>());
            System.assert(false, 'Expected OI_ServiceException.');
        } catch (OI_ServiceException e) {
            System.assert(true);
        }
    }
}
