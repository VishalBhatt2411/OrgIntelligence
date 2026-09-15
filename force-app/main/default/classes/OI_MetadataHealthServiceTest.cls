/**
 * Purpose: Verifies OI_MetadataHealthService computes real, evidence-based, multi-signal
 *          findings from OI_Graph_Node__c/OI_Graph_Edge__c fixtures — never a placeholder score —
 *          and degrades honestly when there is nothing to scan. Object-level classification is
 *          backed by real EntityDefinition rows (ADR-0027 correction), so fixtures needing a
 *          specific classification use real API names already deployed by this package
 *          ('Account'/'Contact' for Standard, this package's own objects for Unmanaged Custom)
 *          rather than fabricated names, which would classify Unknown against a real org.
 */
@isTest
private class OI_MetadataHealthServiceTest {
  private static final String REAL_CUSTOM_OBJECT_A = 'OI_Org_Health_Finding__c';
  private static final String REAL_CUSTOM_OBJECT_B = 'OI_Org_Health_Snapshot__c';
  private static final String REAL_CUSTOM_OBJECT_C = 'OI_Hierarchy_Definition__c';

  @isTest
  static void testGetMetadataHealthDetailComputesScoreAndFindingsFromRealGraphData() {
    insertObject('mh_clean', REAL_CUSTOM_OBJECT_A, 3, 1);
    insertObject('mh_orphan', REAL_CUSTOM_OBJECT_B, 2, 0);
    insertObject('mh_hub', REAL_CUSTOM_OBJECT_C, 4, 3);

    OI_MetadataHealthDTO detail = new OI_MetadataHealthService()
      .getMetadataHealthDetail();

    System.assertNotEquals(
      null,
      detail.score,
      'With real objects in scope, a real score must be computed.'
    );
    System.assertNotEquals(
      null,
      detail.severityKey,
      'A real score must resolve to a real severity band.'
    );
    System.assertEquals(
      3,
      detail.formulaComponents.size(),
      'The formula disclosure must expose all 3 weighted components (never a hidden formula).'
    );
    System.assert(
      detail.coverageNote.contains('3'),
      'Coverage note must reflect the real scanned count.'
    );
    System.assertEquals(
      true,
      detail.isCoverageComplete,
      'Scanning fewer objects than the ceiling must report complete coverage.'
    );

    Boolean foundOrphanRow = false;
    for (OI_HealthHeatmapRowDTO row : detail.heatmapRows) {
      if (row.rowLabel == REAL_CUSTOM_OBJECT_B) {
        foundOrphanRow = true;
        OI_HealthMetricValueDTO orphanCell = row.cells[2];
        System.assertEquals(
          'Y',
          orphanCell.value,
          'The orphan fixture has 0 incoming relationship edges and must be flagged as having no detected incoming references.'
        );
        System.assertEquals(
          'Warning',
          orphanCell.severityKey,
          'A missing-incoming-reference signal must never reach Critical on its own — it is a candidate for review, not proof of an unused object.'
        );
      }
    }
    System.assert(
      foundOrphanRow,
      'The no-incoming-references object must appear in the heatmap (only 3 objects exist, well within the row limit).'
    );

    Boolean foundOrphanInBreakdown = false;
    for (OI_HealthBreakdownRowDTO row : detail.breakdownRows) {
      if (row.key == 'mh_orphan') {
        foundOrphanInBreakdown = true;
        System.assertEquals(
          'Warning',
          row.severityKey,
          'An object with 0 detected incoming references must rank as Warning, never Critical, from that single signal alone.'
        );
        System.assert(
          row.explanation.contains('No incoming references'),
          'The row must explain, in plain language, WHY it has this severity — not just show a severity badge.'
        );
      }
    }
    System.assert(
      foundOrphanInBreakdown,
      'The no-incoming-references object must appear in the breakdown table.'
    );
  }

  @isTest
  static void testGetMetadataHealthDetailWithNoObjectsReturnsNullScoreAndHonestCoverage() {
    OI_MetadataHealthDTO detail = new OI_MetadataHealthService()
      .getMetadataHealthDetail();

    System.assertEquals(
      null,
      detail.score,
      'With nothing to scan, the score must be null, never a fabricated value.'
    );
    System.assertEquals(
      null,
      detail.severityKey,
      'A null score must resolve to a null severity, never a guessed one.'
    );
    System.assertEquals(0, detail.breakdownRows.size());
    System.assertEquals(0, detail.heatmapRows.size());
  }

  @isTest
  static void testGetMetadataHealthDetailBulkHandlesManyObjectsWithoutError() {
    List<OI_Graph_Node__c> nodes = new List<OI_Graph_Node__c>();
    List<OI_Graph_Edge__c> edges = new List<OI_Graph_Edge__c>();
    for (Integer i = 0; i < 40; i++) {
      String objectKey = 'bulk_obj_' + i;
      String apiName = 'Bulk_Fake_Object_' + i + '__x';
      nodes.add(
        new OI_Graph_Node__c(
          Node_Key__c = objectKey,
          Node_Version_Key__c = objectKey + '::v1',
          Version_Number__c = 1,
          Node_Type__c = 'SalesforceMetadata.CustomObject',
          Label__c = apiName,
          Secondary_Key__c = apiName,
          State__c = 'Active',
          Is_Current__c = true
        )
      );
      String fieldKey = objectKey + '_f0';
      nodes.add(
        new OI_Graph_Node__c(
          Node_Key__c = fieldKey,
          Node_Version_Key__c = fieldKey + '::v1',
          Version_Number__c = 1,
          Node_Type__c = 'SalesforceMetadata.CustomField',
          Label__c = 'Field 0',
          Secondary_Key__c = apiName + '.Field_0__c',
          Parent_Key__c = objectKey,
          State__c = 'Active',
          Is_Current__c = true
        )
      );
      edges.add(
        new OI_Graph_Edge__c(
          Edge_Key__c = objectKey + '::HAS_FIELD::f0',
          Edge_Version_Key__c = objectKey + '::HAS_FIELD::f0::v1',
          Version_Number__c = 1,
          Edge_Type__c = 'SalesforceMetadata.HAS_FIELD',
          Source_Node_Key__c = objectKey,
          Target_Node_Key__c = fieldKey,
          State__c = 'Active',
          Is_Current__c = true
        )
      );
    }
    insert nodes;
    insert edges;

    Test.startTest();
    OI_MetadataHealthDTO detail = new OI_MetadataHealthService()
      .getMetadataHealthDetail();
    Test.stopTest();

    System.assert(
      detail.coverageNote.contains('40'),
      'All 40 fixture objects must be reflected in the coverage note.'
    );
    System.assert(
      detail.breakdownRows.size() <= 8,
      'The breakdown table must stay capped at its top-N limit regardless of scan size.'
    );
    System.assert(
      detail.heatmapRows.size() <= 5,
      'The heatmap must stay capped at its top-N limit regardless of scan size.'
    );
  }

  @isTest
  static void testIsCustomFieldApiNameRecognizesTheHardCcSuffixInvariant() {
    System.assertEquals(
      true,
      OI_MetadataHealthService.isCustomFieldApiName('Account.My_Field__c')
    );
    System.assertEquals(
      true,
      OI_MetadataHealthService.isCustomFieldApiName(
        'npsp__Household__c.npsp__Field__c'
      )
    );
    System.assertEquals(
      false,
      OI_MetadataHealthService.isCustomFieldApiName('Account.Name')
    );
    System.assertEquals(
      false,
      OI_MetadataHealthService.isCustomFieldApiName('Account.OwnerId')
    );
    System.assertEquals(
      false,
      OI_MetadataHealthService.isCustomFieldApiName(null)
    );
    System.assertEquals(
      false,
      OI_MetadataHealthService.isCustomFieldApiName('')
    );
  }

  @isTest
  static void testStandardObjectsOwnNativeFieldsAreExcludedFromTheFieldCountPenalty() {
    insertObjectWithFields('mh_std_native', 'Account', 60, true, 5);
    insertDegreeEdges('mh_std_native', 1);

    OI_MetadataHealthDTO detail = new OI_MetadataHealthService()
      .getMetadataHealthDetail();
    String severity;
    for (OI_HealthBreakdownRowDTO row : detail.breakdownRows) {
      if (row.key == 'mh_std_native') {
        severity = row.severityKey;
      }
    }
    System.assertEquals(
      'Good',
      severity,
      '60 Salesforce-provided (non-__c) fields must be entirely excluded from the count — only the 5 real custom fields, well under threshold, are measured.'
    );

    List<OI_OrgHealthFindingCandidate> candidates = new OI_MetadataHealthService()
      .getFindingCandidates();
    for (OI_OrgHealthFindingCandidate candidate : candidates) {
      if (candidate.componentKey == 'mh_std_native') {
        System.assertNotEquals(
          'MetadataHealth.HighFieldCount',
          candidate.ruleId,
          '60 native fields must never surface a HighFieldCount finding — only the 5 real custom fields exist for scoring purposes, well under threshold.'
        );
      }
    }
  }

  @isTest
  static void testStandardObjectWithManyAdminAddedCustomFieldsIsFlaggedLikeACustomObjectWould() {
    insertObjectWithFields('mh_std_custom_heavy', 'Account', 0, true, 200);

    List<OI_OrgHealthFindingCandidate> candidates = new OI_MetadataHealthService()
      .getFindingCandidates();

    OI_OrgHealthFindingCandidate fieldCountCandidate;
    for (OI_OrgHealthFindingCandidate candidate : candidates) {
      if (
        candidate.componentKey == 'mh_std_custom_heavy' &&
        candidate.ruleId == 'MetadataHealth.HighFieldCount'
      ) {
        fieldCountCandidate = candidate;
      }
    }
    System.assertNotEquals(
      null,
      fieldCountCandidate,
      'A Standard object with 200 admin-added custom fields must still be flagged — only Salesforce\'s own native fields are excluded, never fields this org added.'
    );
    System.assertEquals('Critical', fieldCountCandidate.severityKey);
  }

  @isTest
  static void testHighDegreeAppliesToStandardObjectsJustLikeCustomOnes() {
    insertObject('mh_std_hub', 'Account', 0, 200);
    insertObject('mh_custom_hub', REAL_CUSTOM_OBJECT_A, 0, 200);

    OI_MetadataHealthDTO detail = new OI_MetadataHealthService()
      .getMetadataHealthDetail();

    Map<String, String> severityByKey = new Map<String, String>();
    for (OI_HealthBreakdownRowDTO row : detail.breakdownRows) {
      severityByKey.put(row.key, row.severityKey);
    }
    System.assertEquals(
      'Critical',
      severityByKey.get('mh_std_hub'),
      'High incoming-relationship degree must be analyzed for Standard objects exactly like Custom ones — relationships this org built are this org\'s own concern regardless of who owns the target object\'s definition.'
    );
    System.assertEquals('Critical', severityByKey.get('mh_custom_hub'));
  }

  @isTest
  static void testUnknownClassificationObjectIsDampenedButStillGetsFlaggedAtHighMagnitude() {
    insertObjectWithFields(
      'mh_unknown',
      'Totally_Fake_Object__zzz',
      0,
      true,
      500
    );

    List<OI_OrgHealthFindingCandidate> candidates = new OI_MetadataHealthService()
      .getFindingCandidates();

    OI_OrgHealthFindingCandidate fieldCountCandidate;
    for (OI_OrgHealthFindingCandidate candidate : candidates) {
      if (
        candidate.componentKey == 'mh_unknown' &&
        candidate.ruleId == 'MetadataHealth.HighFieldCount'
      ) {
        fieldCountCandidate = candidate;
      }
    }
    System.assertNotEquals(
      null,
      fieldCountCandidate,
      'A large field count on an unclassifiable object must still surface as a finding — Unknown dampens confidence, it never suppresses detection.'
    );
    System.assertEquals(
      'Unknown/Insufficient Metadata',
      fieldCountCandidate.componentType
    );
    System.assertNotEquals(
      'Critical',
      fieldCountCandidate.severityKey,
      'Reduced confidence for an object this scan could not classify must keep a single magnitude signal below Critical.'
    );
  }

  @isTest
  static void testGetFindingCandidatesProducesOneCandidatePerRuleBreachWithRealEvidenceAndScoreContributors() {
    insertObject('mh_clean', REAL_CUSTOM_OBJECT_A, 3, 1);
    insertObjectWithFields('mh_flagged', REAL_CUSTOM_OBJECT_B, 0, true, 500);

    List<OI_OrgHealthFindingCandidate> candidates = new OI_MetadataHealthService()
      .getFindingCandidates();

    Map<String, OI_OrgHealthFindingCandidate> byRuleForFlagged = new Map<String, OI_OrgHealthFindingCandidate>();
    for (OI_OrgHealthFindingCandidate candidate : candidates) {
      System.assertEquals('MetadataHealth', candidate.sectionKey);
      System.assert(
        String.isNotBlank(candidate.evidence),
        'Every candidate must carry real evidence text.'
      );
      System.assert(
        String.isNotBlank(candidate.remediation),
        'Every candidate must carry real remediation guidance.'
      );
      System.assert(
        String.isNotBlank(candidate.explanation),
        'Every candidate must explain why the rule exists.'
      );
      System.assertNotEquals(
        null,
        candidate.score,
        'Every rewritten candidate must carry a real multi-signal score.'
      );
      System.assert(
        String.isNotBlank(candidate.scoreExplanation),
        'Every candidate must explain why its severity was selected.'
      );
      System.assert(
        String.isNotBlank(candidate.scoreContributorsJson),
        'Every candidate must persist its full contributor breakdown for the drawer.'
      );
      if (candidate.componentKey == 'mh_flagged') {
        byRuleForFlagged.put(candidate.ruleId, candidate);
      }
      System.assert(
        candidate.componentKey != 'mh_clean',
        'A clean object with no threshold breach must never produce a candidate.'
      );
    }

    System.assert(
      byRuleForFlagged.containsKey('MetadataHealth.HighFieldCount'),
      'A field count far above threshold must produce a HighFieldCount candidate.'
    );
    System.assert(
      byRuleForFlagged.containsKey('MetadataHealth.NoIncomingReferences'),
      'Zero incoming references must produce a NoIncomingReferences candidate.'
    );
    System.assertEquals(
      'Critical',
      byRuleForFlagged.get('MetadataHealth.HighFieldCount').severityKey
    );
    System.assertEquals(
      'Warning',
      byRuleForFlagged.get('MetadataHealth.NoIncomingReferences').severityKey
    );

    List<Object> contributors = (List<Object>) JSON.deserializeUntyped(
      byRuleForFlagged.get('MetadataHealth.HighFieldCount')
        .scoreContributorsJson
    );
    System.assert(
      !contributors.isEmpty(),
      'The persisted contributor JSON must actually contain at least one signal.'
    );
  }

  @isTest
  static void testGetKpiDrilldownForHighFieldCountReturnsEveryMatchNotJustTheBreakdownTablesTopEight() {
    for (Integer i = 0; i < 9; i++) {
      insertObjectWithFields(
        'mh_kpi_flagged_' + i,
        'Bulk_Kpi_Object_' + i + '__x',
        0,
        true,
        200
      );
    }
    insertObject('mh_kpi_clean', REAL_CUSTOM_OBJECT_A, 3, 1);

    OI_HealthKpiDrilldownDTO drilldown = new OI_MetadataHealthService()
      .getKpiDrilldown('HighFieldCount');

    System.assertEquals(
      9,
      drilldown.rows.size(),
      'A KPI drill-down must return every matching object, never truncated the way the breakdown table\'s top-8 is.'
    );
    for (OI_HealthBreakdownRowDTO row : drilldown.rows) {
      System.assertNotEquals(
        'mh_kpi_clean',
        row.key,
        'A clean object must never appear in the High field-count drill-down.'
      );
      System.assert(
        String.isNotBlank(row.explanation),
        'Every drill-down row must explain why it is here.'
      );
    }
  }

  @isTest
  static void testGetKpiDrilldownForOrphanRateOnlyReturnsObjectsWithNoIncomingReferences() {
    insertObject('mh_kpi_orphan', REAL_CUSTOM_OBJECT_A, 2, 0);
    insertObject('mh_kpi_referenced', REAL_CUSTOM_OBJECT_B, 2, 3);

    OI_HealthKpiDrilldownDTO drilldown = new OI_MetadataHealthService()
      .getKpiDrilldown('OrphanRate');

    Set<String> keys = new Set<String>();
    for (OI_HealthBreakdownRowDTO row : drilldown.rows) {
      keys.add(row.key);
    }
    System.assert(
      keys.contains('mh_kpi_orphan'),
      'The orphan object must appear in its own KPI drill-down.'
    );
    System.assert(
      !keys.contains('mh_kpi_referenced'),
      'A referenced object must never appear in the no-incoming-references drill-down.'
    );
  }

  @isTest
  static void testGetKpiDrilldownForDependencyDensityRanksEveryObjectByDegreeRatherThanFiltering() {
    insertObject('mh_kpi_low', REAL_CUSTOM_OBJECT_A, 1, 1);
    insertObject('mh_kpi_high', REAL_CUSTOM_OBJECT_B, 1, 9);

    OI_HealthKpiDrilldownDTO drilldown = new OI_MetadataHealthService()
      .getKpiDrilldown('DependencyDensity');

    System.assertEquals(
      2,
      drilldown.rows.size(),
      'Dependency density is an org-wide average, not a per-object flag, so its drill-down must show every object, not a filtered subset.'
    );
    System.assertEquals(
      'mh_kpi_high',
      drilldown.rows[0].key,
      'The drill-down must rank objects by degree, highest first.'
    );
    System.assertEquals('mh_kpi_low', drilldown.rows[1].key);
  }

  private static void insertObject(
    String objectKey,
    String apiName,
    Integer customFieldCount,
    Integer degree
  ) {
    insertObjectWithFields(objectKey, apiName, 0, true, customFieldCount);
    insertDegreeEdges(objectKey, degree);
  }

  /**
   * Inserts one Object node plus its field nodes — nativeFieldCount fields whose Secondary_Key__c
   * does NOT end "__c" (simulating Salesforce-provided fields, which must be excluded from the
   * count) and customFieldCount fields that DO (simulating admin/package-added fields, which
   * must count). isCustomSuffix controls which bucket customFieldCount actually falls into, so
   * callers that only care about one bucket can pass 0 for the other.
   */
  private static void insertObjectWithFields(
    String objectKey,
    String apiName,
    Integer nativeFieldCount,
    Boolean isCustomSuffix,
    Integer customFieldCount
  ) {
    insert new OI_Graph_Node__c(
      Node_Key__c = objectKey,
      Node_Version_Key__c = objectKey + '::v1',
      Version_Number__c = 1,
      Node_Type__c = 'SalesforceMetadata.CustomObject',
      Label__c = apiName,
      Secondary_Key__c = apiName,
      State__c = 'Active',
      Is_Current__c = true
    );

    List<OI_Graph_Node__c> fieldNodes = new List<OI_Graph_Node__c>();
    for (Integer i = 0; i < nativeFieldCount; i++) {
      String fieldKey = objectKey + '_native' + i;
      fieldNodes.add(
        new OI_Graph_Node__c(
          Node_Key__c = fieldKey,
          Node_Version_Key__c = fieldKey + '::v1',
          Version_Number__c = 1,
          Node_Type__c = 'SalesforceMetadata.CustomField',
          Label__c = 'Native Field ' + i,
          Secondary_Key__c = apiName + '.NativeField' + i,
          Parent_Key__c = objectKey,
          State__c = 'Active',
          Is_Current__c = true
        )
      );
    }
    for (Integer i = 0; i < customFieldCount; i++) {
      String fieldKey = objectKey + '_custom' + i;
      String suffix = isCustomSuffix ? '__c' : '';
      fieldNodes.add(
        new OI_Graph_Node__c(
          Node_Key__c = fieldKey,
          Node_Version_Key__c = fieldKey + '::v1',
          Version_Number__c = 1,
          Node_Type__c = 'SalesforceMetadata.CustomField',
          Label__c = 'Custom Field ' + i,
          Secondary_Key__c = apiName + '.Custom_Field_' + i + suffix,
          Parent_Key__c = objectKey,
          State__c = 'Active',
          Is_Current__c = true
        )
      );
    }
    if (!fieldNodes.isEmpty()) {
      insert fieldNodes;
    }
  }

  private static void insertDegreeEdges(String objectKey, Integer degree) {
    List<OI_Graph_Edge__c> edges = new List<OI_Graph_Edge__c>();
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
    if (!edges.isEmpty()) {
      insert edges;
    }
  }
}
