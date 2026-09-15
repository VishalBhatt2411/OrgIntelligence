/**
 * Purpose: Verifies OI_GraphRepository's atomicity (commitVersion), optimistic
 *          concurrency translation, and delegation contract (GraphRepository.md §6, §15,
 *          §23) — tested against a fake OI_IGraphStorageProvider for atomicity/delegation,
 *          and against the real OI_CustomObjectStorageProvider for the genuine
 *          DUPLICATE_VALUE conflict path, which cannot be manufactured on a fake
 *          (its StatusCode can't be constructed manually).
 */
@isTest
private class OI_GraphRepositoryTest {
  @isTest
  static void testGetCurrentVersionsDelegatesToProvider() {
    OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
    fake.writeVersion(
      OI_TestDataFactory.newNodeVersionRecord('n1', 1, 'c1'),
      true
    );
    OI_GraphRepository repo = new OI_GraphRepository(fake, fake);
    System.assertEquals(
      1,
      repo.getCurrentVersions(new Set<String>{ 'n1' }, false).size()
    );
  }

  @isTest
  static void testCommitVersionInsertsBrandNewKeyNoFlip() {
    OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
    OI_GraphRepository repo = new OI_GraphRepository(fake, fake);
    repo.commitVersion(
      OI_TestDataFactory.newNodeVersionRecord('n2', 1, 'c1'),
      null
    );
    System.assertEquals(1, fake.versionsByKey.size());
  }

  @isTest
  static void testCommitVersionSupersedesPriorVersion() {
    OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
    OI_GraphRepository repo = new OI_GraphRepository(fake, fake);
    OI_VersionRecord v1 = OI_TestDataFactory.newNodeVersionRecord(
      'n3',
      1,
      'c1'
    );
    repo.commitVersion(v1, null);
    OI_VersionRecord v2 = OI_TestDataFactory.newNodeVersionRecord(
      'n3',
      2,
      'c2'
    );
    repo.commitVersion(v2, v1.versionKey);
    System.assertEquals(
      false,
      fake.versionsByVersionKey.get(v1.versionKey).isCurrent
    );
    System.assertEquals(
      true,
      fake.versionsByVersionKey.get(v2.versionKey).isCurrent
    );
  }

  /**
   * A manually-constructed DmlException cannot safely simulate this path — calling
   * getNumDml() on one that never came from a real failed DML statement raises an
   * uncatchable platform-level UnexpectedException (confirmed empirically; there is no
   * public API to detect this in advance). So this exercises a genuine, real
   * REQUIRED_FIELD_MISSING DmlException instead (Node_Type__c is required on
   * OI_Graph_Node__c) — verifying isDuplicateValueConflict correctly says "no" to a
   * real non-conflict DmlException and the original exception propagates unwrapped.
   */
  @isTest
  static void testCommitVersionPropagatesNonConflictDmlExceptionUnchanged() {
    OI_GraphRepository repo = new OI_GraphRepository();
    OI_VersionRecord invalidRecord = new OI_VersionRecord(
      'n4',
      'n4::v1',
      1,
      null,
      null,
      null,
      null,
      new Map<String, Object>(),
      'c1',
      'Active',
      null,
      null,
      null,
      true,
      null,
      null
    );
    try {
      repo.commitVersion(invalidRecord, null);
      System.assert(
        false,
        'Expected a DmlException from the missing required Node_Type__c field.'
      );
    } catch (OI_ConcurrencyException e) {
      System.assert(
        false,
        'A required-field violation must not be misclassified as a concurrency conflict.'
      );
    } catch (DmlException e) {
      System.assert(
        true,
        'Non-conflict DmlExceptions must propagate unchanged.'
      );
    }
  }

  @isTest
  static void testRealDuplicateValueConflictTranslatesToConcurrencyException() {
    OI_GraphRepository repo = new OI_GraphRepository();
    OI_VersionRecord record = OI_TestDataFactory.newNodeVersionRecord(
      'n5',
      1,
      'c1'
    );
    repo.commitVersion(record, null);
    try {
      repo.commitVersion(record, null);
      System.assert(
        false,
        'Expected OI_ConcurrencyException from a real External ID collision.'
      );
    } catch (OI_ConcurrencyException e) {
      System.assert(true);
    }
  }

  @isTest
  static void testTouchLivenessDelegatesToProvider() {
    OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
    OI_GraphRepository repo = new OI_GraphRepository(fake, fake);
    repo.commitVersion(
      OI_TestDataFactory.newNodeVersionRecord('n6', 1, 'c1'),
      null
    );
    repo.touchLiveness(new Set<String>{ 'n6' }, UserInfo.getUserId(), false);
    System.assertNotEquals(null, fake.versionsByKey.get('n6').lastSeenRunId);
  }

  @isTest
  static void testGetCurrentKeysByTypeDelegatesToProvider() {
    OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
    OI_GraphRepository repo = new OI_GraphRepository(fake, fake);
    repo.commitVersion(
      OI_TestDataFactory.newNodeVersionRecord('n7', 1, 'c1'),
      null
    );
    OI_KeysPage page = repo.getCurrentKeysByType(
      'Test.NodeType',
      null,
      10,
      false
    );
    System.assertEquals(1, page.items.size());
  }

  @isTest
  static void testArchiveSupersededVersionsNotImplementedThisSprint() {
    try {
      new OI_GraphRepository().archiveSupersededVersions(Datetime.now());
      System.assert(false);
    } catch (OI_ServiceException e) {
      System.assert(true);
    }
  }

  /**
   * commitVersion cannot be bulked across different keys the way a plain insert can
   * (GraphRepository.md §11, §24) — each key's insert-then-flip is its own
   * Savepoint-guarded transactional unit, and Database.setSavepoint() itself consumes
   * one DML statement per call. 120 sequential commits (not 200) is the honest
   * boundary this test can exercise within the platform's 150-DML-statement-per-
   * transaction ceiling — a real caller (OI_GraphBuilder, Roadmap Phase 2) is expected
   * to chunk beyond this, exactly as the cited sections already document.
   */
  @isTest
  static void testSequentialCommitVersionAcrossManyKeysRespectsPerTransactionDmlCeiling() {
    OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
    OI_GraphRepository repo = new OI_GraphRepository(fake, fake);
    for (Integer i = 0; i < 120; i++) {
      repo.commitVersion(
        OI_TestDataFactory.newNodeVersionRecord('bulkKey' + i, 1, 'c' + i),
        null
      );
    }
    System.assertEquals(120, fake.versionsByKey.size());
  }

  /**
   * These 8 current-state aggregate reads (ADR-0026, Org Health) moved from
   * OI_GraphEngine onto this Repository so the Engine stays a pure pass-through facade
   * and every node/edge storage read funnels through this one class
   * (GraphRepository.md §1). They read real OI_Graph_Node__c/OI_Graph_Edge__c rows
   * directly via the Selectors — the fake provider only intercepts the 5-op version
   * contract, not these — so each test inserts real rows exactly like
   * OI_NodeSelectorTest/OI_EdgeSelectorTest already do for the underlying Selector
   * methods; these tests verify the Repository exposes and delegates to them correctly,
   * not the Selector logic itself (already covered there).
   */
  @isTest
  static void testCountCurrentNodesByTypeDelegatesToNodeSelector() {
    insert new OI_Graph_Node__c(
      Node_Key__c = 'rn1',
      Node_Version_Key__c = 'rn1::v1',
      Version_Number__c = 1,
      Node_Type__c = 'Repo.TypeA',
      State__c = 'Active',
      Is_Current__c = true
    );
    Map<String, Integer> counts = new OI_GraphRepository()
      .countCurrentNodesByType(new Set<String>{ 'Repo.TypeA' });
    System.assertEquals(1, counts.get('Repo.TypeA'));
  }

  @isTest
  static void testCountCurrentEdgesTotalDelegatesToEdgeSelector() {
    insert new OI_Graph_Edge__c(
      Edge_Key__c = 're1',
      Edge_Version_Key__c = 're1::v1',
      Version_Number__c = 1,
      Edge_Type__c = 'Repo.EdgeType',
      Source_Node_Key__c = 's',
      Target_Node_Key__c = 't',
      State__c = 'Active',
      Is_Current__c = true
    );
    System.assertEquals(1, new OI_GraphRepository().countCurrentEdgesTotal());
  }

  @isTest
  static void testCountCurrentEdgesByTypeDelegatesToEdgeSelector() {
    insert new OI_Graph_Edge__c(
      Edge_Key__c = 're2',
      Edge_Version_Key__c = 're2::v1',
      Version_Number__c = 1,
      Edge_Type__c = 'Repo.EdgeTypeB',
      Source_Node_Key__c = 's',
      Target_Node_Key__c = 't',
      State__c = 'Active',
      Is_Current__c = true
    );
    System.assertEquals(
      1,
      new OI_GraphRepository()
        .countCurrentEdgesByType(new Set<String>{ 'Repo.EdgeTypeB' })
    );
    System.assertEquals(
      0,
      new OI_GraphRepository()
        .countCurrentEdgesByType(new Set<String>{ 'Repo.NoSuchType' })
    );
  }

  @isTest
  static void testSelectCurrentNodesByTypeBoundedDelegatesToNodeSelector() {
    insert new List<OI_Graph_Node__c>{
      new OI_Graph_Node__c(
        Node_Key__c = 'rb1',
        Node_Version_Key__c = 'rb1::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Repo.Bounded',
        Label__c = 'One',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'rb2',
        Node_Version_Key__c = 'rb2::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Repo.Bounded',
        Label__c = 'Two',
        State__c = 'Active',
        Is_Current__c = true
      )
    };
    System.assertEquals(
      1,
      new OI_GraphRepository()
        .selectCurrentNodesByTypeBounded('Repo.Bounded', 1)
        .size()
    );
  }

  @isTest
  static void testCountCurrentEdgesBySourceKeysGroupedByKeyDelegatesToEdgeSelector() {
    insert new OI_Graph_Edge__c(
      Edge_Key__c = 're3',
      Edge_Version_Key__c = 're3::v1',
      Version_Number__c = 1,
      Edge_Type__c = 'Repo.HasChild',
      Source_Node_Key__c = 'objA',
      Target_Node_Key__c = 'childA',
      State__c = 'Active',
      Is_Current__c = true
    );
    Map<String, Integer> counts = new OI_GraphRepository()
      .countCurrentEdgesBySourceKeysGroupedByKey(
        new Set<String>{ 'objA' },
        new Set<String>{ 'Repo.HasChild' }
      );
    System.assertEquals(1, counts.get('objA'));
  }

  @isTest
  static void testCountCurrentEdgesByTargetKeysGroupedByKeyDelegatesToEdgeSelector() {
    insert new OI_Graph_Edge__c(
      Edge_Key__c = 're4',
      Edge_Version_Key__c = 're4::v1',
      Version_Number__c = 1,
      Edge_Type__c = 'Repo.LookupTo',
      Source_Node_Key__c = 'fieldA',
      Target_Node_Key__c = 'objTarget',
      State__c = 'Active',
      Is_Current__c = true
    );
    Map<String, Integer> counts = new OI_GraphRepository()
      .countCurrentEdgesByTargetKeysGroupedByKey(
        new Set<String>{ 'objTarget' },
        new Set<String>{ 'Repo.LookupTo' }
      );
    System.assertEquals(1, counts.get('objTarget'));
  }

  @isTest
  static void testCountCurrentEdgesBySourceKeysGroupedByTargetKeyDelegatesToEdgeSelector() {
    insert new OI_Graph_Edge__c(
      Edge_Key__c = 're5',
      Edge_Version_Key__c = 're5::v1',
      Version_Number__c = 1,
      Edge_Type__c = 'Repo.ExecutesOn',
      Source_Node_Key__c = 'trg1',
      Target_Node_Key__c = 'objA',
      State__c = 'Active',
      Is_Current__c = true
    );
    Map<String, Integer> counts = new OI_GraphRepository()
      .countCurrentEdgesBySourceKeysGroupedByTargetKey(
        new Set<String>{ 'trg1' },
        new Set<String>{ 'Repo.ExecutesOn' }
      );
    System.assertEquals(1, counts.get('objA'));
  }

  @isTest
  static void testSelectCurrentEdgesBetweenKeysDelegatesToEdgeSelector() {
    insert new List<OI_Graph_Edge__c>{
      new OI_Graph_Edge__c(
        Edge_Key__c = 're6',
        Edge_Version_Key__c = 're6::v1',
        Version_Number__c = 1,
        Edge_Type__c = 'Repo.References',
        Source_Node_Key__c = 'clsA',
        Target_Node_Key__c = 'clsB',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Edge__c(
        Edge_Key__c = 're7',
        Edge_Version_Key__c = 're7::v1',
        Version_Number__c = 1,
        Edge_Type__c = 'Repo.References',
        Source_Node_Key__c = 'clsB',
        Target_Node_Key__c = 'clsOutside',
        State__c = 'Active',
        Is_Current__c = true
      )
    };
    List<OI_Graph_Edge__c> results = new OI_GraphRepository()
      .selectCurrentEdgesBetweenKeys(
        new Set<String>{ 'clsA', 'clsB' },
        new Set<String>{ 'Repo.References' }
      );
    System.assertEquals(1, results.size());
  }
}
