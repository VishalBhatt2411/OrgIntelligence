/**
 * Purpose: Verifies OI_AutomationHealthService computes real, evidence-based findings from
 *          OI_Graph_Node__c/OI_Graph_Edge__c fixtures — no composite score (facts-only,
 *          §0.3) — and degrades honestly when there is nothing to scan.
 */
@isTest
private class OI_AutomationHealthServiceTest {
  @isTest
  static void testGetAutomationHealthDetailComputesFactsFromRealGraphData() {
    insertNode('objA', 'SalesforceMetadata.CustomObject', 'Account');
    insertNode('objB', 'SalesforceMetadata.CustomObject', 'Contact');
    insertNode('trg1', 'SalesforceMetadata.ApexTrigger', 'AccountTrigger');
    insertNode('trg2', 'SalesforceMetadata.ApexTrigger', 'ContactTrigger');
    insertNode('flow1', 'SalesforceMetadata.Flow', 'LeadFlow');

    insert new List<OI_Graph_Edge__c>{
      edge('trg1', 'SalesforceMetadata.EXECUTES_ON', 'objA'),
      edge('flow1', 'SalesforceMetadata.EXECUTES_ON', 'objA'),
      edge('trg2', 'SalesforceMetadata.EXECUTES_ON', 'objB'),
      edge('trg1', 'SalesforceMetadata.REFERENCES', 'trg2'),
      edge('trg2', 'SalesforceMetadata.REFERENCES', 'trg1')
    };

    OI_AutomationHealthDTO detail = new OI_AutomationHealthService()
      .getAutomationHealthDetail();

    System.assert(
      detail.coverageNote.contains('3'),
      'Coverage note must reflect the 2 triggers + 1 flow scanned.'
    );
    System.assertEquals(true, detail.isCoverageComplete);

    Map<String, String> kpiByLabel = new Map<String, String>();
    for (OI_HealthKeyValueDTO tile : detail.kpiTiles) {
      kpiByLabel.put(tile.label, tile.value);
    }
    System.assertEquals('2', kpiByLabel.get('Triggers scanned'));
    System.assertEquals('1', kpiByLabel.get('Flows scanned'));
    System.assertEquals(
      '2',
      kpiByLabel.get('Components in dependency cycles'),
      'trg1 and trg2 reference each other and must both be flagged as cyclic.'
    );
    System.assert(
      kpiByLabel.get('Most automated object').startsWith('Account'),
      'Account has 2 automation components (trg1 + flow1), the most of any object.'
    );

    Boolean foundCyclicRow = false;
    for (OI_HealthBreakdownRowDTO row : detail.breakdownRows) {
      if (row.key == 'trg1' || row.key == 'trg2') {
        foundCyclicRow = true;
        System.assertEquals(
          'Warning',
          row.severityKey,
          'A component participating in a dependency cycle must rank Warning, never Critical, from cycle membership alone — this scanner cannot yet corroborate the cycle with runtime/impact evidence.'
        );
      }
    }
    System.assert(
      foundCyclicRow,
      'The cyclic components must appear in the breakdown table.'
    );
  }

  @isTest
  static void testGetAutomationHealthDetailWithNoComponentsReturnsHonestZeroState() {
    OI_AutomationHealthDTO detail = new OI_AutomationHealthService()
      .getAutomationHealthDetail();

    System.assert(
      detail.coverageNote.contains('0'),
      'With nothing to scan, the coverage note must honestly report zero.'
    );
    System.assertEquals(0, detail.breakdownRows.size());
    System.assertEquals(0, detail.heatmapRows.size());
    Boolean foundMostAutomated = false;
    for (OI_HealthKeyValueDTO tile : detail.kpiTiles) {
      if (tile.label == 'Most automated object') {
        foundMostAutomated = true;
        System.assertEquals('None detected', tile.value);
      }
    }
    System.assert(foundMostAutomated);
  }

  @isTest
  static void testGetAutomationHealthDetailBulkHandlesManyComponentsWithoutError() {
    List<OI_Graph_Node__c> nodes = new List<OI_Graph_Node__c>();
    for (Integer i = 0; i < 30; i++) {
      nodes.add(
        node(
          'trg_bulk_' + i,
          'SalesforceMetadata.ApexTrigger',
          'BulkTrigger' + i
        )
      );
    }
    insert nodes;

    Test.startTest();
    OI_AutomationHealthDTO detail = new OI_AutomationHealthService()
      .getAutomationHealthDetail();
    Test.stopTest();

    System.assert(
      detail.coverageNote.contains('30'),
      'All 30 fixture triggers must be reflected in the coverage note.'
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
  static void testHighDependencyAtFullSaturationReachesCriticalEvenWithoutACycle() {
    insertNode(
      'trgHigh',
      'SalesforceMetadata.ApexTrigger',
      'HighDependencyTrigger'
    );
    List<OI_Graph_Node__c> targets = new List<OI_Graph_Node__c>();
    List<OI_Graph_Edge__c> edges = new List<OI_Graph_Edge__c>();
    for (Integer i = 0; i < 20; i++) {
      String targetKey = 'refTarget' + i;
      targets.add(
        node(targetKey, 'SalesforceMetadata.ApexClass', 'RefTarget' + i)
      );
      edges.add(edge('trgHigh', 'SalesforceMetadata.REFERENCES', targetKey));
    }
    insert targets;
    insert edges;

    OI_AutomationHealthDTO detail = new OI_AutomationHealthService()
      .getAutomationHealthDetail();

    String severity;
    for (OI_HealthBreakdownRowDTO row : detail.breakdownRows) {
      if (row.key == 'trgHigh') {
        severity = row.severityKey;
      }
    }
    System.assertEquals(
      'Critical',
      severity,
      '20 combined fan-out edges against the default threshold of 10 must saturate the dependency signal to Critical.'
    );

    List<OI_OrgHealthFindingCandidate> candidates = new OI_AutomationHealthService()
      .getFindingCandidates();
    OI_OrgHealthFindingCandidate highDependency;
    for (OI_OrgHealthFindingCandidate candidate : candidates) {
      if (
        candidate.componentKey == 'trgHigh' &&
        candidate.ruleId == 'AutomationHealth.HighDependency'
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
    System.assertEquals('Apex Trigger', highDependency.componentType);
    System.assert(
      String.isNotBlank(highDependency.scoreContributorsJson),
      'The candidate must carry its full contributor breakdown for the drawer.'
    );
  }

  @isTest
  static void testCycleMembershipAloneWithLowDependencyNeverReachesCriticalButStillProducesACandidate() {
    insertNode('cycA', 'SalesforceMetadata.ApexTrigger', 'CycleA');
    insertNode('cycB', 'SalesforceMetadata.ApexTrigger', 'CycleB');
    insert new List<OI_Graph_Edge__c>{
      edge('cycA', 'SalesforceMetadata.REFERENCES', 'cycB'),
      edge('cycB', 'SalesforceMetadata.REFERENCES', 'cycA')
    };

    List<OI_OrgHealthFindingCandidate> candidates = new OI_AutomationHealthService()
      .getFindingCandidates();

    OI_OrgHealthFindingCandidate cycleCandidate;
    for (OI_OrgHealthFindingCandidate candidate : candidates) {
      if (
        candidate.componentKey == 'cycA' &&
        candidate.ruleId == 'AutomationHealth.DependencyCycle'
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

  private static void insertNode(String nodeKey, String typeKey, String label) {
    insert node(nodeKey, typeKey, label);
  }

  private static OI_Graph_Node__c node(
    String nodeKey,
    String typeKey,
    String label
  ) {
    return new OI_Graph_Node__c(
      Node_Key__c = nodeKey,
      Node_Version_Key__c = nodeKey + '::v1',
      Version_Number__c = 1,
      Node_Type__c = typeKey,
      Label__c = label,
      State__c = 'Active',
      Is_Current__c = true
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
