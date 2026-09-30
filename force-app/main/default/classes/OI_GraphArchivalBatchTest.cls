/**
 * Purpose: Verifies OI_GraphArchivalBatch archives then purges only superseded versions past
 *          the cutoff, never a current version, and chains its four phases in order
 *          (ADR-0031). The Big Object side is the in-memory fake — insertImmediate cannot run
 *          in Apex tests — while the live side is the real Custom Object provider.
 */
@isTest
private class OI_GraphArchivalBatchTest {
  private static final Datetime FUTURE_CUTOFF = Datetime.now().addHours(1);

  @isTest
  static void testArchiveNodesPhaseCopiesSupersededVersionsAndKeepsLiveRows() {
    insertNodeVersions();
    OI_FakeGraphStorageProvider archive = new OI_FakeGraphStorageProvider();

    Test.startTest();
    Database.executeBatch(
      batch(OI_GraphArchivalBatch.Phase.ARCHIVE_NODES, archive),
      OI_GraphArchivalBatch.BATCH_SIZE
    );
    Test.stopTest();

    System.assertEquals(
      new Set<String>{ 'n1::v1', 'n2::v1' },
      OI_FakeGraphStorageProvider.writesByVersionKeyAcrossInstances.keySet(),
      'Only superseded versions are archived.'
    );
    System.assertEquals(
      4,
      [SELECT COUNT() FROM OI_Graph_Node__c],
      'The archive phase must not delete anything.'
    );
  }

  @isTest
  static void testPurgeNodesPhaseDeletesSupersededVersionsOnly() {
    insertNodeVersions();

    Test.startTest();
    Database.executeBatch(
      batch(
        OI_GraphArchivalBatch.Phase.PURGE_NODES,
        new OI_FakeGraphStorageProvider()
      ),
      OI_GraphArchivalBatch.BATCH_SIZE
    );
    Test.stopTest();

    List<OI_Graph_Node__c> remaining = [
      SELECT Node_Version_Key__c, Is_Current__c
      FROM OI_Graph_Node__c
    ];
    System.assertEquals(2, remaining.size());
    for (OI_Graph_Node__c row : remaining) {
      System.assertEquals(
        true,
        row.Is_Current__c,
        'A current version must never be purged.'
      );
    }
  }

  @isTest
  static void testCutoffInThePastLeavesRecentSupersededVersionsAlone() {
    insertNodeVersions();

    Test.startTest();
    Database.executeBatch(
      new OI_GraphArchivalBatch(
        Datetime.now().addDays(-1),
        OI_GraphArchivalBatch.Phase.PURGE_NODES,
        new OI_GraphRepository(
          new OI_CustomObjectStorageProvider(),
          new OI_FakeGraphStorageProvider()
        )
      ),
      OI_GraphArchivalBatch.BATCH_SIZE
    );
    Test.stopTest();

    System.assertEquals(
      4,
      [SELECT COUNT() FROM OI_Graph_Node__c],
      'Versions superseded inside the retention window stay.'
    );
  }

  @isTest
  static void testEdgePhasesArchiveThenPurgeSupersededEdges() {
    insert new List<OI_Graph_Edge__c>{
      edge('e1::v1', false),
      edge('e1::v2', true)
    };
    OI_FakeGraphStorageProvider archive = new OI_FakeGraphStorageProvider();

    Test.startTest();
    Database.executeBatch(
      batch(OI_GraphArchivalBatch.Phase.ARCHIVE_EDGES, archive),
      OI_GraphArchivalBatch.BATCH_SIZE
    );
    Test.stopTest();

    System.assertEquals(
      new Set<String>{ 'e1::v1' },
      OI_FakeGraphStorageProvider.writesByVersionKeyAcrossInstances.keySet()
    );
    System.assertEquals(
      true,
      OI_FakeGraphStorageProvider.writesByVersionKeyAcrossInstances.get(
          'e1::v1'
        )
        .isEdge()
    );
    System.assertEquals(2, [SELECT COUNT() FROM OI_Graph_Edge__c]);

    System.assertEquals(
      1,
      new OI_GraphRepository(new OI_CustomObjectStorageProvider(), archive)
        .purgeArchivedVersions(new Set<String>{ 'e1::v1', 'e1::v2' }, true)
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM OI_Graph_Edge__c WHERE Is_Current__c = TRUE]
    );
  }

  @isTest
  static void testBulkArchiveOfAFullChunk() {
    List<OI_Graph_Node__c> rows = new List<OI_Graph_Node__c>();
    for (Integer i = 0; i < OI_GraphArchivalBatch.BATCH_SIZE; i++) {
      rows.add(node('bulk' + i, 'bulk' + i + '::v1', false));
    }
    insert rows;
    OI_FakeGraphStorageProvider archive = new OI_FakeGraphStorageProvider();

    Test.startTest();
    Database.executeBatch(
      batch(OI_GraphArchivalBatch.Phase.ARCHIVE_NODES, archive),
      OI_GraphArchivalBatch.BATCH_SIZE
    );
    Test.stopTest();

    System.assertEquals(
      OI_GraphArchivalBatch.BATCH_SIZE,
      OI_FakeGraphStorageProvider.writesByVersionKeyAcrossInstances.size(),
      'A full chunk archives in one execute (a test may run only one).'
    );
  }

  @isTest
  static void testPhasesChainInOrderAndEnd() {
    System.assertEquals(
      OI_GraphArchivalBatch.Phase.PURGE_NODES,
      OI_GraphArchivalBatch.nextPhase(OI_GraphArchivalBatch.Phase.ARCHIVE_NODES)
    );
    System.assertEquals(
      OI_GraphArchivalBatch.Phase.ARCHIVE_EDGES,
      OI_GraphArchivalBatch.nextPhase(OI_GraphArchivalBatch.Phase.PURGE_NODES)
    );
    System.assertEquals(
      OI_GraphArchivalBatch.Phase.PURGE_EDGES,
      OI_GraphArchivalBatch.nextPhase(OI_GraphArchivalBatch.Phase.ARCHIVE_EDGES)
    );
    System.assertEquals(
      null,
      OI_GraphArchivalBatch.nextPhase(OI_GraphArchivalBatch.Phase.PURGE_EDGES)
    );
  }

  @isTest
  static void testResolveCutoffUsesTheShippedRetention() {
    Datetime cutoff = OI_GraphArchivalBatch.resolveCutoff();
    System.assert(
      cutoff <= Datetime.now(),
      'The cutoff is never in the future.'
    );
    System.assert(
      cutoff > Datetime.now().addDays(-400),
      'The cutoff follows a days-scale retention setting.'
    );
  }

  @isTest
  static void testLaunchStartsTheChain() {
    Test.startTest();
    Id jobId = OI_GraphArchivalBatch.launch();
    Test.stopTest();
    System.assertNotEquals(null, jobId);
  }

  private static OI_GraphArchivalBatch batch(
    OI_GraphArchivalBatch.Phase startPhase,
    OI_FakeGraphStorageProvider archive
  ) {
    return new OI_GraphArchivalBatch(
      FUTURE_CUTOFF,
      startPhase,
      new OI_GraphRepository(new OI_CustomObjectStorageProvider(), archive)
    );
  }

  private static void insertNodeVersions() {
    insert new List<OI_Graph_Node__c>{
      node('n1', 'n1::v1', false),
      node('n1', 'n1::v2', true),
      node('n2', 'n2::v1', false),
      node('n2', 'n2::v2', true)
    };
  }

  private static OI_Graph_Node__c node(
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

  private static OI_Graph_Edge__c edge(String versionKey, Boolean isCurrent) {
    return new OI_Graph_Edge__c(
      Edge_Key__c = 'e1',
      Edge_Version_Key__c = versionKey,
      Version_Number__c = versionKey.endsWith('v1') ? 1 : 2,
      Edge_Type__c = 'Test.EdgeType',
      Source_Node_Key__c = 'n1',
      Target_Node_Key__c = 'n2',
      State__c = 'Active',
      Is_Current__c = isCurrent
    );
  }
}
