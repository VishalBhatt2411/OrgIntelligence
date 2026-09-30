/**
 * Purpose: Verifies OI_CustomObjectStorageProvider's read/write mapping round-trips
 *          correctly against real Custom Object DML (GraphRepository.md §8).
 */
@isTest
private class OI_CustomObjectStorageProviderTest {
  @isTest
  static void testWriteVersionThenReadCurrentRoundTripsNode() {
    OI_CustomObjectStorageProvider provider = new OI_CustomObjectStorageProvider();
    provider.writeVersion(
      OI_TestDataFactory.newNodeVersionRecord('node1', 1, 'checksumA'),
      true
    );
    Map<String, OI_VersionRecord> results = provider.readCurrent(
      new Set<String>{ 'node1' },
      false
    );
    System.assertEquals(1, results.size());
    System.assertEquals('checksumA', results.get('node1').checksum);
  }

  @isTest
  static void testWriteVersionThenReadCurrentRoundTripsEdge() {
    OI_CustomObjectStorageProvider provider = new OI_CustomObjectStorageProvider();
    provider.writeVersion(
      OI_TestDataFactory.newEdgeVersionRecord('edge1', 'src1', 'tgt1', 1),
      true
    );
    Map<String, OI_VersionRecord> results = provider.readCurrent(
      new Set<String>{ 'edge1' },
      true
    );
    System.assertEquals(1, results.size());
    System.assertEquals('src1', results.get('edge1').sourceKey);
  }

  @isTest
  static void testMarkSupersededFlipsIsCurrentOnNode() {
    OI_CustomObjectStorageProvider provider = new OI_CustomObjectStorageProvider();
    OI_VersionRecord v1 = OI_TestDataFactory.newNodeVersionRecord(
      'node2',
      1,
      'c1'
    );
    provider.writeVersion(v1, true);
    provider.markSuperseded(v1.versionKey, false);
    System.assertEquals(
      0,
      provider.readCurrent(new Set<String>{ 'node2' }, false).size(),
      'Superseded row must no longer be current.'
    );
  }

  @isTest
  static void testTouchLivenessUpdatesLastSeenRun() {
    insert OI_TestDataFactory.newScanRun();
    Id runId = [SELECT Id FROM OI_Scan_Run__c LIMIT 1].Id;
    OI_CustomObjectStorageProvider provider = new OI_CustomObjectStorageProvider();
    provider.writeVersion(
      OI_TestDataFactory.newNodeVersionRecord('node3', 1, 'c1'),
      true
    );
    provider.touchLiveness(new Set<String>{ 'node3' }, runId, false);
    OI_Graph_Node__c row = [
      SELECT Last_Seen_Run__c
      FROM OI_Graph_Node__c
      WHERE Node_Key__c = 'node3'
    ];
    System.assertEquals(runId, row.Last_Seen_Run__c);
  }

  @isTest
  static void testMoveToArchiveDeletesOnlyNonCurrentRows() {
    insert new List<OI_Graph_Node__c>{
      archivalNode('arc1', 'arc1::v1', false),
      archivalNode('arc1', 'arc1::v2', true)
    };
    insert new OI_Graph_Edge__c(
      Edge_Key__c = 'arcE',
      Edge_Version_Key__c = 'arcE::v1',
      Version_Number__c = 1,
      Edge_Type__c = 'Test.EdgeType',
      Source_Node_Key__c = 'arc1',
      Target_Node_Key__c = 'arc2',
      State__c = 'Active',
      Is_Current__c = false
    );
    OI_CustomObjectStorageProvider provider = new OI_CustomObjectStorageProvider();
    List<OI_VersionRecord> records = provider.readSupersededByVersionKeys(
      new Set<String>{ 'arc1::v1', 'arc1::v2' },
      false
    );
    records.addAll(
      provider.readSupersededByVersionKeys(new Set<String>{ 'arcE::v1' }, true)
    );
    System.assertEquals(
      2,
      records.size(),
      'Only the non-current node version and the edge are superseded.'
    );

    System.assertEquals(2, provider.moveToArchive(records));
    System.assertEquals(
      1,
      [SELECT COUNT() FROM OI_Graph_Node__c WHERE Node_Key__c = 'arc1'],
      'The current version survives.'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM OI_Graph_Edge__c WHERE Edge_Key__c = 'arcE']
    );
    System.assertEquals(
      0,
      provider.moveToArchive(new List<OI_VersionRecord>())
    );
  }

  private static OI_Graph_Node__c archivalNode(
    String key,
    String versionKey,
    Boolean isCurrent
  ) {
    return new OI_Graph_Node__c(
      Node_Key__c = key,
      Node_Version_Key__c = versionKey,
      Version_Number__c = versionKey.endsWith('v1') ? 1 : 2,
      Node_Type__c = 'Test.NodeType',
      State__c = 'Active',
      Is_Current__c = isCurrent
    );
  }
}
