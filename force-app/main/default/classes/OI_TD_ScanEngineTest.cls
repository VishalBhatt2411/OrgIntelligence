/**
 * Purpose: Drives OI_TD_ScanEngine through a whole scan against in-memory Tooling / Metadata
 *          fakes (OI_TD_TestSupport.installEngineFakes) and checks the stored results, plus the
 *          section-failure and helper paths.
 */
@isTest
private class OI_TD_ScanEngineTest {
  private static OI_TD_Scan__c runningScan() {
    return OI_TD_TestSupport.insertScan(
      OI_TD_ScanEngine.STATUS_RUNNING,
      System.now(),
      null
    );
  }

  /** Repeats executes like the batch chain would, until the scan finishes. */
  private static void runToCompletion(OI_TD_ScanState st) {
    Integer guard = 0;
    while (!OI_TD_ScanEngine.runExecute(st) && guard < 60) {
      guard++;
    }
    System.assert(
      st.stage >= OI_TD_ScanEngine.S_DONE,
      'scan did not finish, stopped at stage ' + st.stage
    );
  }

  @isTest
  static void fullScanStoresFindingsScoresAndInventory() {
    OI_TD_TestSupport.installEngineFakes();
    OI_TD_Scan__c scan = runningScan();
    OI_TD_ScanState st = new OI_TD_ScanState(scan.Id);

    Test.startTest();
    runToCompletion(st);
    Test.stopTest();

    OI_TD_Scan__c done = [
      SELECT
        Status__c,
        Overall_Score__c,
        Category_Scores__c,
        Summary__c,
        Section_Results__c,
        Finished_At__c
      FROM OI_TD_Scan__c
      WHERE Id = :scan.Id
    ];
    System.assertEquals(
      OI_TD_ScanEngine.STATUS_COMPLETED,
      done.Status__c,
      done.Section_Results__c
    );
    System.assertNotEquals(null, done.Overall_Score__c);
    System.assertNotEquals(null, done.Finished_At__c);
    Map<String, Object> summary = (Map<String, Object>) JSON.deserializeUntyped(
      done.Summary__c
    );
    Map<String, Object> counts = (Map<String, Object>) summary.get('counts');
    System.assertEquals(2, counts.get('objects'));
    System.assertEquals(1, counts.get('lwc'));
    System.assertEquals(1, counts.get('workflowRules'));
    System.assertEquals(2, counts.get('packages'));
    System.assertEquals(true, summary.get('hasDependencyData'));

    Set<String> kinds = new Set<String>();
    for (OI_TD_Scan_Data__c d : [
      SELECT Kind__c
      FROM OI_TD_Scan_Data__c
      WHERE Scan__c = :scan.Id
    ]) {
      kinds.add(d.Kind__c);
      System.assert(
        !d.Kind__c.startsWith('hay:'),
        'haystack data should be removed: ' + d.Kind__c
      );
    }
    System.assert(kinds.contains('objects'), String.valueOf(kinds));
    System.assert(kinds.contains('fields:0'), String.valueOf(kinds));
    System.assert(kinds.contains('refs'), String.valueOf(kinds));

    List<Object> wf = OI_TD_DataStore.readList(scan.Id, 'wf');
    Map<String, Object> rule = (Map<String, Object>) wf[0];
    System.assertEquals('Notify', rule.get('n'));
    System.assertEquals(true, rule.get('ac'));
  }

  @isTest
  static void scanWithoutDependencyDataFallsBackToTextSearch() {
    OI_TD_TestSupport.FakeTooling tooling = OI_TD_TestSupport.installEngineFakes();
    tooling.failOn = 'MetadataComponentDependency';
    OI_TD_Scan__c scan = runningScan();
    OI_TD_ScanState st = new OI_TD_ScanState(scan.Id);

    Test.startTest();
    runToCompletion(st);
    Test.stopTest();

    OI_TD_Scan__c done = [
      SELECT Status__c, Summary__c, Section_Results__c
      FROM OI_TD_Scan__c
      WHERE Id = :scan.Id
    ];
    System.assertEquals(OI_TD_ScanEngine.STATUS_COMPLETED, done.Status__c);
    System.assertEquals(
      false,
      ((Map<String, Object>) JSON.deserializeUntyped(done.Summary__c))
        .get('hasDependencyData')
    );
    System.assert(
      done.Section_Results__c.contains('Tooling unavailable'),
      done.Section_Results__c
    );
  }

  @isTest
  static void toolingFailuresAreBestEffort() {
    OI_TD_TestSupport.FakeTooling tooling = OI_TD_TestSupport.installEngineFakes();
    tooling.failOn = 'FROM';
    OI_TD_Scan__c scan = runningScan();
    OI_TD_ScanState st = new OI_TD_ScanState(scan.Id);

    Test.startTest();
    runToCompletion(st);
    Test.stopTest();

    OI_TD_Scan__c done = [
      SELECT Status__c, Section_Results__c
      FROM OI_TD_Scan__c
      WHERE Id = :scan.Id
    ];
    System.assertEquals(OI_TD_ScanEngine.STATUS_COMPLETED, done.Status__c);
    System.assert(
      done.Section_Results__c.contains('Tooling unavailable'),
      done.Section_Results__c
    );
  }

  @isTest
  static void skipSectionMovesPastTheWholeSection() {
    OI_TD_TestSupport.installEngineFakes();
    OI_TD_ScanState st = new OI_TD_ScanState(runningScan().Id);
    st.stage = OI_TD_ScanEngine.S_OBJ_IDS;
    OI_TD_ScanEngine.skipSection(st, 'boom');
    System.assertEquals(OI_TD_ScanEngine.S_CLASSES, st.stage);
    System.assertEquals('objects', st.sections[0].category);
    System.assertEquals('boom', st.sections[0].error);

    st.stage = OI_TD_ScanEngine.S_ANALYZE;
    OI_TD_ScanEngine.skipSection(st, 'fatal');
    System.assert(st.failed);
    System.assertEquals(OI_TD_ScanEngine.S_DONE, st.stage);
  }

  @isTest
  static void markScanFailedRemovesHaystackData() {
    OI_TD_Scan__c scan = runningScan();
    insert new List<OI_TD_Scan_Data__c>{
      OI_TD_DataStore.pack(scan.Id, 'hay:flows:0', 0, '[]'),
      OI_TD_DataStore.pack(scan.Id, 'objects', 0, '[]')
    };
    OI_TD_ScanEngine.markScanFailed(
      scan.Id,
      null,
      new List<OI_TD_ScanState.SectionResult>()
    );
    OI_TD_Scan__c failed = [
      SELECT Status__c, Error__c
      FROM OI_TD_Scan__c
      WHERE Id = :scan.Id
    ];
    System.assertEquals(OI_TD_ScanEngine.STATUS_FAILED, failed.Status__c);
    System.assertEquals('The scan failed.', failed.Error__c);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM OI_TD_Scan_Data__c WHERE Scan__c = :scan.Id]
    );
  }

  @isTest
  static void stageLabelsAndTypeNames() {
    System.assertEquals(
      'Connecting to Salesforce…',
      OI_TD_ScanEngine.stageLabel(OI_TD_ScanEngine.S_TARGETS)
    );
    System.assertEquals(
      'Reading objects & fields…',
      OI_TD_ScanEngine.stageLabel(OI_TD_ScanEngine.S_DESCRIBE)
    );
    System.assertEquals(
      'Scanning Apex classes…',
      OI_TD_ScanEngine.stageLabel(OI_TD_ScanEngine.S_CLASSES)
    );
    System.assertEquals(
      'Scanning triggers…',
      OI_TD_ScanEngine.stageLabel(OI_TD_ScanEngine.S_TRIGGERS)
    );
    System.assertEquals(
      'Scanning flows…',
      OI_TD_ScanEngine.stageLabel(OI_TD_ScanEngine.S_WF)
    );
    System.assertEquals(
      'Scanning Lightning components…',
      OI_TD_ScanEngine.stageLabel(OI_TD_ScanEngine.S_LWC)
    );
    System.assertEquals(
      'Checking profiles & permission sets…',
      OI_TD_ScanEngine.stageLabel(OI_TD_ScanEngine.S_EMAIL)
    );
    System.assertEquals(
      'Analyzing technical debt…',
      OI_TD_ScanEngine.stageLabel(OI_TD_ScanEngine.S_USAGE)
    );

    System.assertEquals(
      'int',
      OI_TD_ScanEngine.typeName(Schema.DisplayType.INTEGER)
    );
    System.assertEquals(
      'anyType',
      OI_TD_ScanEngine.typeName(Schema.DisplayType.ANYTYPE)
    );
    System.assertEquals(
      'currency',
      OI_TD_ScanEngine.typeName(Schema.DisplayType.CURRENCY)
    );
  }

  @isTest
  static void metadataRecordExtractionAndMatching() {
    List<Map<String, Object>> results = new List<Map<String, Object>>{
      new Map<String, Object>{
        'records' => new List<Object>{
          new Map<String, Object>{ 'fullName' => 'Account.Rule' },
          'junk'
        }
      },
      new Map<String, Object>{
        'records' => new Map<String, Object>{ 'fullName' => 'Case.Other' }
      },
      new Map<String, Object>{ 'records' => null },
      null
    };
    List<Map<String, Object>> records = OI_TD_ScanEngine.extractRecords(
      results
    );
    System.assertEquals(4, records.size());
    System.assertEquals(null, records[1]);

    Map<String, Map<String, Object>> matched = OI_TD_ScanEngine.matchRecords(
      new List<String>{ 'account.rule', 'Missing' },
      records
    );
    System.assertNotEquals(null, matched.get('account.rule'));
    System.assertEquals(null, matched.get('Missing'));

    // Without fullNames, records are matched by position.
    Map<String, Object> anonymous = new Map<String, Object>{ 'active' => true };
    Map<String, Map<String, Object>> positional = OI_TD_ScanEngine.matchRecords(
      new List<String>{ 'X' },
      new List<Map<String, Object>>{ anonymous }
    );
    System.assertEquals(anonymous, positional.get('X'));
  }
}
