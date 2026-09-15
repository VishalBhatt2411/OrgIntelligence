/**
 * Purpose: Verifies OI_CodeHealthService computes a well-formed, evidence-based result.
 * Limitations: ApexClass is platform-owned and cannot be seeded via DML in a test context
 *              (mirrors OI_ApexClassSelectorTest's own documented constraint), so these tests
 *              exercise the real deployed org's Apex classes and assert structural
 *              correctness — a well-formed score/formula/breakdown shape — rather than
 *              specific hardcoded numbers.
 */
@isTest
private class OI_CodeHealthServiceTest {
  @isTest
  static void testGetCodeHealthDetailReturnsWellFormedResultFromLiveOrgClasses() {
    Test.startTest();
    OI_CodeHealthDTO detail = new OI_CodeHealthService().getCodeHealthDetail();
    Test.stopTest();

    System.assert(
      detail.score == null || (detail.score >= 0 && detail.score <= 100),
      'A computed score must always be within 0-100.'
    );
    if (detail.score != null) {
      System.assertNotEquals(
        null,
        detail.severityKey,
        'A real score must resolve to a real severity band.'
      );
    }
    System.assert(
      String.isNotBlank(detail.coverageNote),
      'Coverage note must never be blank — an org always has at least the classes deployed here.'
    );
    System.assertEquals(
      4,
      detail.kpiTiles.size(),
      'Exactly 4 facts: classes scanned, high-dependency, stale API version, cycles.'
    );
    System.assert(
      detail.breakdownRows.size() <= 8,
      'The breakdown table must stay capped at its top-N limit.'
    );
    System.assert(
      detail.heatmapRows.size() <= 5,
      'The heatmap must stay capped at its top-N limit.'
    );

    for (OI_HealthBreakdownRowDTO row : detail.breakdownRows) {
      System.assert(
        String.isNotBlank(row.primaryLabel),
        'Every breakdown row must carry a real class name.'
      );
      System.assert(
        new Set<String>{ 'Good', 'Warning', 'Critical' }
          .contains(row.severityKey),
        'Every breakdown row must carry a recognized severity, never null or a guessed value.'
      );
      System.assertEquals(
        2,
        row.metricValues.size(),
        'Dependency and API version columns must always be present.'
      );
    }
  }

  @isTest
  static void testGetCodeHealthDetailAlwaysExposesTwoFormulaComponents() {
    OI_CodeHealthDTO detail = new OI_CodeHealthService().getCodeHealthDetail();

    System.assertEquals(
      2,
      detail.formulaComponents.size(),
      'Any score must expose its formula — both weighted components, never a hidden one.'
    );
    System.assertNotEquals(null, detail.formulaSummary);
    for (OI_HealthKeyValueDTO component : detail.formulaComponents) {
      System.assert(String.isNotBlank(component.label));
      System.assert(String.isNotBlank(component.value));
    }
  }

  @isTest
  static void testGetCodeHealthDetailHeatmapRowsCarryBothMetricCells() {
    OI_CodeHealthDTO detail = new OI_CodeHealthService().getCodeHealthDetail();

    for (OI_HealthHeatmapRowDTO row : detail.heatmapRows) {
      System.assertEquals(
        2,
        row.cells.size(),
        'Dependency and API version cells must always be present.'
      );
      for (OI_HealthMetricValueDTO cell : row.cells) {
        System.assert(
          new Set<String>{ 'Good', 'Warning', 'Critical' }
            .contains(cell.severityKey),
          'Every heatmap cell must carry a recognized severity.'
        );
      }
    }
  }

  /**
   * ApexClass rows cannot be inserted via DML, but OI_CodeHealthService.deriveNodeKey
   * (@TestVisible) reproduces its exact deterministic hash formula for a real, already-deployed
   * class name — this lets fixtures control a real class's fan-in/fan-out via freely-insertable
   * OI_Graph_Edge__c rows without needing to fabricate the ApexClass row itself.
   */
  @isTest
  static void testHighDependencyAtFullSaturationReachesCriticalEvenWithoutACycle() {
    String subjectKey = OI_CodeHealthService.deriveNodeKey(null, 'OI_HashUtil');
    List<OI_Graph_Edge__c> edges = new List<OI_Graph_Edge__c>();
    for (Integer i = 0; i < 30; i++) {
      String targetKey = 'codeHealthTarget' + i;
      edges.add(edge(subjectKey, 'SalesforceMetadata.REFERENCES', targetKey));
    }
    insert edges;

    Test.startTest();
    OI_CodeHealthDTO detail = new OI_CodeHealthService().getCodeHealthDetail();
    List<OI_OrgHealthFindingCandidate> candidates = new OI_CodeHealthService()
      .getFindingCandidates();
    Test.stopTest();

    String severity;
    for (OI_HealthBreakdownRowDTO row : detail.breakdownRows) {
      if (row.key == subjectKey) {
        severity = row.severityKey;
      }
    }
    System.assertEquals(
      'Critical',
      severity,
      '30 combined fan-out edges against the configured threshold of 20 must saturate the dependency signal to Critical.'
    );

    OI_OrgHealthFindingCandidate highDependency;
    for (OI_OrgHealthFindingCandidate candidate : candidates) {
      if (
        candidate.componentKey == subjectKey &&
        candidate.ruleId == 'CodeHealth.HighDependency'
      ) {
        highDependency = candidate;
      }
    }
    System.assertNotEquals(
      null,
      highDependency,
      'A saturated combined fan-in/fan-out must produce a HighDependency candidate.'
    );
    System.assertEquals('Critical', highDependency.severityKey);
    System.assertEquals('Apex Class', highDependency.componentType);
    System.assert(
      String.isNotBlank(highDependency.scoreContributorsJson),
      'The candidate must carry its full contributor breakdown for the drawer.'
    );
  }

  /**
   * Cycle detection only considers edges where BOTH endpoints are within the scanned class
   * set (OI_GraphEngine.selectCurrentEdgesBetweenKeys — "between", not "from any of"), so the
   * partner half of the cycle must also be a real, already-deployed class, not an arbitrary key.
   */
  @isTest
  static void testCycleMembershipAloneWithLowDependencyNeverReachesCriticalButStillProducesACandidate() {
    String subjectKey = OI_CodeHealthService.deriveNodeKey(null, 'OI_HashUtil');
    String partnerKey = OI_CodeHealthService.deriveNodeKey(
      null,
      'OI_GraphEngine'
    );
    insert new List<OI_Graph_Edge__c>{
      edge(subjectKey, 'SalesforceMetadata.REFERENCES', partnerKey),
      edge(partnerKey, 'SalesforceMetadata.REFERENCES', subjectKey)
    };

    Test.startTest();
    List<OI_OrgHealthFindingCandidate> candidates = new OI_CodeHealthService()
      .getFindingCandidates();
    Test.stopTest();

    OI_OrgHealthFindingCandidate cycleCandidate;
    for (OI_OrgHealthFindingCandidate candidate : candidates) {
      if (
        candidate.componentKey == subjectKey &&
        candidate.ruleId == 'CodeHealth.DependencyCycle'
      ) {
        cycleCandidate = candidate;
      }
    }
    System.assertNotEquals(
      null,
      cycleCandidate,
      'Cycle membership must produce a DependencyCycle candidate even at low dependency counts.'
    );
    System.assertNotEquals(
      'Critical',
      cycleCandidate.severityKey,
      'Cycle membership alone (with negligible fan-in/out) must never reach Critical from this single low-confidence signal.'
    );
  }

  private static OI_Graph_Edge__c edge(
    String sourceKey,
    String edgeTypeKey,
    String targetKey
  ) {
    String edgeKey = sourceKey + '::' + edgeTypeKey + '::' + targetKey;
    return new OI_Graph_Edge__c(
      Edge_Key__c = edgeKey,
      Edge_Version_Key__c = edgeKey + '::v1',
      Version_Number__c = 1,
      Edge_Type__c = edgeTypeKey,
      Source_Node_Key__c = sourceKey,
      Target_Node_Key__c = targetKey,
      State__c = 'Active',
      Is_Current__c = true
    );
  }
}
