/**
 * Purpose: Verifies OI_OrgHealthSummaryService assembles the landing grid from the real
 *          OI_Org_Health_Section_Config__mdt registry, in Display_Order__c order, with all
 *          seven real sections (Org Overview, Storage, Metadata Health, Automation Health,
 *          Code Health, Security Health, Data Health) honestly marked implemented — scored
 *          sections carrying a real score/severity, facts-only sections never inventing one,
 *          and Data Health specifically staying score-null until its first async run
 *          completes, rather than any section being omitted or faked.
 */
@isTest
private class OI_OrgHealthSummaryServiceTest {
  @isTest
  static void testGetSummaryReturnsOneCardPerConfiguredSectionInDisplayOrder() {
    List<OI_Org_Health_Section_Config__mdt> configs = OI_Org_Health_Section_Config__mdt.getAll()
      .values();

    OI_OrgHealthSummaryDTO summary = new OI_OrgHealthSummaryService()
      .getSummary();

    System.assertEquals(
      configs.size(),
      summary.sections.size(),
      'Every configured section must produce exactly one card.'
    );

    Decimal previousOrder = -1;
    for (OI_OrgHealthSectionSummaryDTO card : summary.sections) {
      OI_Org_Health_Section_Config__mdt matching = OI_Org_Health_Section_Config__mdt.getInstance(
        card.sectionKey
      );
      System.assertNotEquals(
        null,
        matching,
        'Every returned card must trace back to a real CMDT section record.'
      );
      System.assert(
        matching.Display_Order__c >= previousOrder,
        'Cards must be emitted in ascending Display_Order__c order.'
      );
      previousOrder = matching.Display_Order__c;
    }
  }

  @isTest
  static void testGetSummaryMarksOrgOverviewAndStorageAsImplementedWithTopSignals() {
    OI_OrgHealthSummaryDTO summary = new OI_OrgHealthSummaryService()
      .getSummary();

    OI_OrgHealthSectionSummaryDTO overviewCard = findCard(
      summary,
      'OrgOverview'
    );
    System.assertEquals(true, overviewCard.isImplemented);
    System.assert(
      !overviewCard.topSignals.isEmpty(),
      'Org Overview is a real Phase 1 section and must carry real KPI signals.'
    );

    OI_OrgHealthSectionSummaryDTO storageCard = findCard(summary, 'Storage');
    System.assertEquals(true, storageCard.isImplemented);
    System.assertEquals('Live org limits.', storageCard.coverageNote);
  }

  @isTest
  static void testGetSummaryMarksMetadataHealthAsImplementedWithRealScoreAndTopSignals() {
    insertObjectNodeWithFieldsAndDegree('mh_acct', 'Account', 5, 2);

    OI_OrgHealthSummaryDTO summary = new OI_OrgHealthSummaryService()
      .getSummary();

    OI_OrgHealthSectionSummaryDTO metadataCard = findCard(
      summary,
      'MetadataHealth'
    );
    System.assertEquals(
      true,
      metadataCard.isImplemented,
      'Metadata Health is a real Phase 2 section and must be marked implemented.'
    );
    System.assertNotEquals(
      null,
      metadataCard.score,
      'An implemented, scored section must carry a real score.'
    );
    System.assert(
      !metadataCard.topSignals.isEmpty(),
      'Metadata Health must carry real top signals.'
    );
  }

  private static void insertObjectNodeWithFieldsAndDegree(
    String objectKey,
    String label,
    Integer fieldCount,
    Integer degree
  ) {
    insert new OI_Graph_Node__c(
      Node_Key__c = objectKey,
      Node_Version_Key__c = objectKey + '::v1',
      Version_Number__c = 1,
      Node_Type__c = 'SalesforceMetadata.CustomObject',
      Label__c = label,
      State__c = 'Active',
      Is_Current__c = true
    );
    List<OI_Graph_Edge__c> edges = new List<OI_Graph_Edge__c>();
    for (Integer i = 0; i < fieldCount; i++) {
      String fieldKey = objectKey + '_field' + i;
      edges.add(
        new OI_Graph_Edge__c(
          Edge_Key__c = objectKey + '::HAS_FIELD::' + fieldKey,
          Edge_Version_Key__c = objectKey + '::HAS_FIELD::' + fieldKey + '::v1',
          Version_Number__c = 1,
          Edge_Type__c = 'SalesforceMetadata.HAS_FIELD',
          Source_Node_Key__c = objectKey,
          Target_Node_Key__c = fieldKey,
          State__c = 'Active',
          Is_Current__c = true
        )
      );
    }
    for (Integer i = 0; i < degree; i++) {
      String referencingFieldKey = objectKey + '_ref' + i;
      edges.add(
        new OI_Graph_Edge__c(
          Edge_Key__c = objectKey + '::LOOKUP_TO::' + referencingFieldKey,
          Edge_Version_Key__c = objectKey +
            '::LOOKUP_TO::' +
            referencingFieldKey +
            '::v1',
          Version_Number__c = 1,
          Edge_Type__c = 'SalesforceMetadata.LOOKUP_TO',
          Source_Node_Key__c = referencingFieldKey,
          Target_Node_Key__c = objectKey,
          State__c = 'Active',
          Is_Current__c = true
        )
      );
    }
    insert edges;
  }

  @isTest
  static void testGetSummaryMarksAutomationHealthAsImplementedFactsOnlyWithNoScore() {
    insert new OI_Graph_Node__c(
      Node_Key__c = 'sum_trg1',
      Node_Version_Key__c = 'sum_trg1::v1',
      Version_Number__c = 1,
      Node_Type__c = 'SalesforceMetadata.ApexTrigger',
      Label__c = 'SummaryTrigger',
      State__c = 'Active',
      Is_Current__c = true
    );

    OI_OrgHealthSummaryDTO summary = new OI_OrgHealthSummaryService()
      .getSummary();

    OI_OrgHealthSectionSummaryDTO automationCard = findCard(
      summary,
      'AutomationHealth'
    );
    System.assertEquals(
      true,
      automationCard.isImplemented,
      'Automation Health is a real Phase 3 section and must be marked implemented.'
    );
    System.assertEquals(
      null,
      automationCard.score,
      'Automation Health is facts-only (§0.3) and must never carry an invented score.'
    );
    System.assert(
      !automationCard.topSignals.isEmpty(),
      'Automation Health must carry real top signals.'
    );
  }

  @isTest
  static void testGetSummaryMarksCodeHealthAsImplementedWithRealScoreAndTopSignals() {
    OI_OrgHealthSummaryDTO summary = new OI_OrgHealthSummaryService()
      .getSummary();

    OI_OrgHealthSectionSummaryDTO codeCard = findCard(summary, 'CodeHealth');
    System.assertEquals(
      true,
      codeCard.isImplemented,
      'Code Health is a real Phase 3 section and must be marked implemented.'
    );
    System.assertNotEquals(
      null,
      codeCard.score,
      'Code Health is scored (Is_Scored__c = true) and must carry a real score.'
    );
    System.assert(
      !codeCard.topSignals.isEmpty(),
      'Code Health must carry real top signals.'
    );
  }

  @isTest
  static void testGetSummaryMarksSecurityHealthAsImplementedFactsOnlyWithNoScore() {
    OI_OrgHealthSummaryDTO summary = new OI_OrgHealthSummaryService()
      .getSummary();

    OI_OrgHealthSectionSummaryDTO securityCard = findCard(
      summary,
      'SecurityHealth'
    );
    System.assertEquals(
      true,
      securityCard.isImplemented,
      'Security Health is a real Phase 4 section and must be marked implemented.'
    );
    System.assertEquals(
      null,
      securityCard.score,
      'Security Health is facts-only (§0.3) — the spec says "No fake score" — and must never carry an invented score.'
    );
    System.assert(
      !securityCard.topSignals.isEmpty(),
      'Security Health must carry real top signals.'
    );
  }

  @isTest
  static void testGetSummaryMarksDataHealthAsImplementedButHonestlyNotYetScoredBeforeAnyRun() {
    OI_OrgHealthSummaryDTO summary = new OI_OrgHealthSummaryService()
      .getSummary();

    OI_OrgHealthSectionSummaryDTO dataHealthCard = findCard(
      summary,
      'DataHealth'
    );
    System.assertEquals(
      true,
      dataHealthCard.isImplemented,
      'Data Health is a real Phase 5 section and must be marked implemented.'
    );
    System.assertEquals(
      null,
      dataHealthCard.score,
      'No compute has run yet in a fresh test context — the score must stay null, never a fabricated value.'
    );
    System.assertEquals(
      'Data Health has not been computed yet. Run a scan to see results.',
      dataHealthCard.coverageNote
    );
  }

  /**
   * Drives OI_DataHealthComputeBatchable's start()/execute()/finish() directly rather than
   * through Database.executeBatch — Salesforce allows at most one real executeBatch
   * invocation per RunLocalTests execution, and that budget is reserved for
   * OI_OrgHealthControllerTest's end-to-end async test. This still exercises the exact same
   * collection/scoring/persistence logic.
   */
  @isTest
  static void testGetSummaryMarksDataHealthWithARealScoreAfterAComputeRunHasCompleted() {
    insert new Account(Name = 'OI Summary Data Health Test');

    OI_DataHealthComputeBatchable batchable = new OI_DataHealthComputeBatchable(
      UserInfo.getUserId()
    );
    for (OI_Data_Health_Object_Scope__mdt scopeRow : batchable.start(null)) {
      batchable.execute(
        null,
        new List<OI_Data_Health_Object_Scope__mdt>{ scopeRow }
      );
    }
    batchable.finish(null);

    OI_OrgHealthSummaryDTO summary = new OI_OrgHealthSummaryService()
      .getSummary();

    OI_OrgHealthSectionSummaryDTO dataHealthCard = findCard(
      summary,
      'DataHealth'
    );
    System.assertEquals(true, dataHealthCard.isImplemented);
    System.assertNotEquals(
      null,
      dataHealthCard.score,
      'Once a compute run has completed, the landing card must reflect the real persisted score.'
    );
    System.assert(
      !dataHealthCard.topSignals.isEmpty(),
      'A completed run must carry real top signals.'
    );
  }

  private static OI_OrgHealthSectionSummaryDTO findCard(
    OI_OrgHealthSummaryDTO summary,
    String sectionKey
  ) {
    for (OI_OrgHealthSectionSummaryDTO card : summary.sections) {
      if (card.sectionKey == sectionKey) {
        return card;
      }
    }
    System.assert(false, 'Expected a card for section ' + sectionKey);
    return null;
  }
}
