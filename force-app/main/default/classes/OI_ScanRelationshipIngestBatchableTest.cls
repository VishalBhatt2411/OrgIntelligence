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
    OI_Scan_Task__c task = new OI_Scan_Task__c(
      Scan_Run__c = run.Id,
      Metadata_Type__c = 'FakeKind',
      Status__c = 'Running'
    );
    insert task;

    String parentKey = OI_ComponentKeyUtil.build('FakeKind', null, 'Parent');
    String childKey = OI_ComponentKeyUtil.build('FakeKind', null, 'Child');
    List<OI_DiscoveredComponent> seedComponents = new List<OI_DiscoveredComponent>{
      new OI_DiscoveredComponent(
        parentKey,
        'FakeKind',
        'Parent',
        null,
        'Fake',
        new Map<String, Object>(),
        'p',
        null,
        null
      ),
      new OI_DiscoveredComponent(
        childKey,
        'FakeKind',
        'Child',
        null,
        'Fake',
        new Map<String, Object>(),
        'c',
        null,
        null
      )
    };
    Set<String> observedNodeKeys = new OI_MutationGenerator()
      .translateAndIngest(
        new OI_DiscoveryBatch(
          task.Id,
          'FakeKind',
          seedComponents,
          new List<OI_DiscoveredRelationship>(),
          false,
          0
        )
      );
    System.assertEquals(
      2,
      observedNodeKeys.size(),
      'Precondition: the component phase observed exactly the 2 seeded nodeKeys.'
    );

    List<OI_DiscoveredRelationship> relationships = new List<OI_DiscoveredRelationship>{
      new OI_DiscoveredRelationship(
        'rk1',
        'FAKE_RELATES_TO',
        parentKey,
        childKey,
        new Map<String, Object>()
      )
    };

    Test.startTest();
    Database.executeBatch(
      new OI_ScanRelationshipIngestBatchable(
        run.Id,
        task.Id,
        'FakeKind',
        relationships,
        false,
        observedNodeKeys,
        new List<String>()
      ),
      60
    );
    Test.stopTest();

    OI_Scan_Task__c completedTask = [
      SELECT Status__c, Records_Scanned__c, Error_Message__c
      FROM OI_Scan_Task__c
      WHERE Id = :task.Id
    ];
    System.assertEquals(
      'Succeeded',
      completedTask.Status__c,
      'Error_Message__c: ' + completedTask.Error_Message__c
    );
    System.assertEquals(
      2,
      completedTask.Records_Scanned__c,
      'Records_Scanned__c must reflect the carried-over observedNodeKeys, not the relationship count.'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM OI_Graph_Edge__c
        WHERE
          Edge_Type__c = 'SalesforceMetadata.FAKE_RELATES_TO'
          AND Is_Current__c = TRUE
      ]
    );
    System.assertEquals(
      'Completed',
      [SELECT Status__c FROM OI_Scan_Run__c WHERE Id = :run.Id].Status__c
    );
  }

  /**
   * Sprint 9.1 addition: mirrors OI_ScanComponentIngestBatchableTest's multi-scope
   * progress-reporting test — proves the periodic call to
   * OI_ScanOrchestratorQueueable.recordRelationshipIngestProgress (fired mid-run here) is
   * purely an interim signal that never writes Records_Scanned__c, so the carried-over
   * observedNodeKeys count from the component phase still survives untouched through to
   * completion.
   *
   * Drives start()/execute()/finish() directly rather than via Database.executeBatch, for
   * the same reason as OI_ScanComponentIngestBatchableTest's multi-scope test: a
   * plain-List Iterable that needs more than one execute() scope trips the Apex test
   * harness's "No more than one executeBatch can be called from within a test method"
   * restriction — confirmed by running this test through Database.executeBatch first.
   */
  @isTest
  static void testRelationshipBatchAcrossMultipleScopesReportsInterimProgressAndPreservesTheFinalObservedNodeKeyCount() {
    OI_Scan_Run__c run = OI_TestDataFactory.newScanRun();
    run.Status__c = 'Running';
    insert run;
    OI_Scan_Task__c task = new OI_Scan_Task__c(
      Scan_Run__c = run.Id,
      Metadata_Type__c = 'FakeKind',
      Status__c = 'Running'
    );
    insert task;

    String parentKey = OI_ComponentKeyUtil.build('FakeKind', null, 'Parent');
    List<OI_DiscoveredComponent> seedComponents = new List<OI_DiscoveredComponent>{
      new OI_DiscoveredComponent(
        parentKey,
        'FakeKind',
        'Parent',
        null,
        'Fake',
        new Map<String, Object>(),
        'p',
        null,
        null
      )
    };
    // One distinct child per relationship, so every scope links real, distinct edges.
    List<String> childKeys = new List<String>();
    for (Integer i = 0; i < 55; i++) {
      String childKey = OI_ComponentKeyUtil.build(
        'FakeKind',
        null,
        'Child' + i
      );
      childKeys.add(childKey);
      seedComponents.add(
        new OI_DiscoveredComponent(
          childKey,
          'FakeKind',
          'Child' + i,
          null,
          'Fake',
          new Map<String, Object>(),
          'c' + i,
          null,
          null
        )
      );
    }
    Set<String> observedNodeKeys = new OI_MutationGenerator()
      .translateAndIngest(
        new OI_DiscoveryBatch(
          task.Id,
          'FakeKind',
          seedComponents,
          new List<OI_DiscoveredRelationship>(),
          false,
          0
        )
      );
    System.assertEquals(
      56,
      observedNodeKeys.size(),
      'Precondition: the component phase observed the parent and all 55 children.'
    );

    List<OI_DiscoveredRelationship> relationships = new List<OI_DiscoveredRelationship>();
    for (Integer i = 0; i < 55; i++) {
      relationships.add(
        new OI_DiscoveredRelationship(
          'rk' + i,
          'FAKE_RELATES_TO',
          parentKey,
          childKeys[i],
          new Map<String, Object>()
        )
      );
    }

    OI_ScanRelationshipIngestBatchable batchable = new OI_ScanRelationshipIngestBatchable(
      run.Id,
      task.Id,
      'FakeKind',
      relationships,
      false,
      observedNodeKeys,
      new List<String>()
    );

    Test.startTest();
    Integer scopeSize = 10;
    for (
      Integer offset = 0; offset < relationships.size(); offset += scopeSize
    ) {
      Integer endIndex = Math.min(offset + scopeSize, relationships.size());
      List<OI_DiscoveredRelationship> scope = new List<OI_DiscoveredRelationship>();
      for (Integer i = offset; i < endIndex; i++) {
        scope.add(relationships[i]);
      }
      batchable.execute(null, scope);
      if (offset / scopeSize + 1 == 5) {
        Decimal interim = [
          SELECT Records_Scanned__c
          FROM OI_Scan_Task__c
          WHERE Id = :task.Id
        ]
        .Records_Scanned__c;
        System.assert(
          interim == null || interim == 0,
          'The relationship phase must never write Records_Scanned__c, got ' +
          interim
        );
      }
    }
    batchable.finish(null);
    Test.stopTest();

    OI_Scan_Task__c completedTask = [
      SELECT Status__c, Records_Scanned__c, Error_Message__c
      FROM OI_Scan_Task__c
      WHERE Id = :task.Id
    ];
    System.assertEquals(
      'Succeeded',
      completedTask.Status__c,
      'Error_Message__c: ' + completedTask.Error_Message__c
    );
    System.assertEquals(
      56,
      completedTask.Records_Scanned__c,
      'Records_Scanned__c must still reflect the carried-over observedNodeKeys, not the relationship count, even after several interim progress reports.'
    );
    System.assertEquals(
      55,
      [
        SELECT COUNT()
        FROM OI_Graph_Edge__c
        WHERE
          Edge_Type__c = 'SalesforceMetadata.FAKE_RELATES_TO'
          AND Is_Current__c = TRUE
      ],
      'Every scope must have linked its own distinct edges.'
    );
    System.assertEquals(
      'Completed',
      [SELECT Status__c FROM OI_Scan_Run__c WHERE Id = :run.Id].Status__c
    );
  }
}
