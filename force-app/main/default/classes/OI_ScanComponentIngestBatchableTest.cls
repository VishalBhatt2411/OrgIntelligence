/**
 * Purpose: Verifies OI_ScanComponentIngestBatchable's finish()-time branching (Sprint
 *          9.1) — chaining to OI_ScanRelationshipIngestBatchable when relationships are
 *          present, or completing the task directly when they are not — independent of
 *          the full OI_ScanOrchestratorQueueable.startScan entry point (already covered
 *          end-to-end by OI_ScanOrchestratorQueueableTest).
 * Limitations: A forced execute()-time ingestion failure is not exercised here — the same
 *              accepted gap OI_ScanOrchestratorQueueableTest documents for the Queueable
 *              path (Sprint 10 testability follow-up), since neither path has an injection
 *              seam for a failing OI_MutationGenerator/OI_GraphEngine today.
 */
@isTest
private class OI_ScanComponentIngestBatchableTest {
  @isTest
  static void testComponentBatchWithNoRelationshipsCompletesTheTaskDirectly() {
    OI_Scan_Run__c run = OI_TestDataFactory.newScanRun();
    run.Status__c = 'Running';
    insert run;
    OI_Scan_Task__c task = new OI_Scan_Task__c(
      Scan_Run__c = run.Id,
      Metadata_Type__c = 'FakeKind',
      Status__c = 'Running'
    );
    insert task;

    List<OI_DiscoveredComponent> components = new List<OI_DiscoveredComponent>();
    for (Integer i = 0; i < 5; i++) {
      String fqn = 'Component' + i;
      components.add(
        new OI_DiscoveredComponent(
          OI_ComponentKeyUtil.build('FakeKind', null, fqn),
          'FakeKind',
          fqn,
          null,
          'Fake',
          new Map<String, Object>(),
          'c' + i,
          null,
          null
        )
      );
    }

    Test.startTest();
    Database.executeBatch(
      new OI_ScanComponentIngestBatchable(
        run.Id,
        task.Id,
        'FakeKind',
        components,
        new List<OI_DiscoveredRelationship>(),
        false,
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
    System.assertEquals(5, completedTask.Records_Scanned__c);
    System.assertEquals(
      'Completed',
      [SELECT Status__c FROM OI_Scan_Run__c WHERE Id = :run.Id].Status__c
    );
  }

  @isTest
  static void testComponentBatchWithRelationshipsChainsToRelationshipBatchAndPersistsTheEdge() {
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
    List<OI_DiscoveredComponent> components = new List<OI_DiscoveredComponent>{
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
      new OI_ScanComponentIngestBatchable(
        run.Id,
        task.Id,
        'FakeKind',
        components,
        relationships,
        false,
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
    System.assertEquals(2, completedTask.Records_Scanned__c);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM OI_Graph_Edge__c
        WHERE
          Edge_Type__c = 'SalesforceMetadata.FAKE_RELATES_TO'
          AND Is_Current__c = TRUE
      ],
      'The relationship batch chained from finish() must have ingested the edge.'
    );
  }

  /**
   * Sprint 9.1 addition: proves the periodic PROGRESS_REPORT_INTERVAL call to
   * OI_ScanOrchestratorQueueable.recordComponentIngestProgress (fired mid-run, on the 5th
   * of 6 scopes here) is purely an interim signal — it must not corrupt or short-circuit
   * the authoritative final Records_Scanned__c that completeTask writes once every scope
   * has actually run.
   *
   * Drives start()/execute()/finish() directly rather than via Database.executeBatch: a
   * plain-List (non-QueryLocator) Iterable that needs more than one execute() scope trips
   * the Apex test harness's "No more than one executeBatch can be called from within a
   * test method" restriction the moment Test.stopTest() tries to process a second scope —
   * confirmed by running this test through Database.executeBatch first. Calling the
   * interface methods directly on one instance sidesteps that restriction while still
   * exercising the exact same Database.Stateful accumulation (observedNodeKeys,
   * scopesProcessed) a real multi-scope run relies on. Database.BatchableContext is safe
   * to pass as null here since neither method reads it.
   */
  @isTest
  static void testComponentBatchAcrossMultipleScopesReportsInterimProgressAndStillCompletesWithTheCorrectFinalCount() {
    OI_Scan_Run__c run = OI_TestDataFactory.newScanRun();
    run.Status__c = 'Running';
    insert run;
    OI_Scan_Task__c task = new OI_Scan_Task__c(
      Scan_Run__c = run.Id,
      Metadata_Type__c = 'FakeKind',
      Status__c = 'Running'
    );
    insert task;

    List<OI_DiscoveredComponent> components = new List<OI_DiscoveredComponent>();
    for (Integer i = 0; i < 55; i++) {
      String fqn = 'Component' + i;
      components.add(
        new OI_DiscoveredComponent(
          OI_ComponentKeyUtil.build('FakeKind', null, fqn),
          'FakeKind',
          fqn,
          null,
          'Fake',
          new Map<String, Object>(),
          'c' + i,
          null,
          null
        )
      );
    }

    OI_ScanComponentIngestBatchable batchable = new OI_ScanComponentIngestBatchable(
      run.Id,
      task.Id,
      'FakeKind',
      components,
      new List<OI_DiscoveredRelationship>(),
      false,
      new List<String>()
    );

    Test.startTest();
    Integer scopeSize = 10;
    for (Integer offset = 0; offset < components.size(); offset += scopeSize) {
      Integer endIndex = Math.min(offset + scopeSize, components.size());
      List<OI_DiscoveredComponent> scope = new List<OI_DiscoveredComponent>();
      for (Integer i = offset; i < endIndex; i++) {
        scope.add(components[i]);
      }
      batchable.execute(null, scope);
      Integer scopesRun = offset / scopeSize + 1;
      Decimal interim = [
        SELECT Records_Scanned__c
        FROM OI_Scan_Task__c
        WHERE Id = :task.Id
      ]
      .Records_Scanned__c;
      if (scopesRun == 4) {
        System.assert(
          interim == null || interim == 0,
          'No interim write before the 5th scope, got ' + interim
        );
      } else if (scopesRun == 5) {
        System.assertEquals(
          50,
          interim,
          'The 5th scope must write the running count of observed nodes.'
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
      55,
      completedTask.Records_Scanned__c,
      'The final write must reflect every scope, not just the count at the last interim report.'
    );
    System.assertEquals(
      'Completed',
      [SELECT Status__c FROM OI_Scan_Run__c WHERE Id = :run.Id].Status__c
    );
  }
}
