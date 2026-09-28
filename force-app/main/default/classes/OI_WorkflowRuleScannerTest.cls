/**
 * Purpose: Verifies OI_WorkflowRuleScanner's component/relationship shape and its "report
 *          degraded rather than throw" behavior on a Tooling API failure, using DI-based fakes
 *          for OI_ToolingApiAdapter (CodingStandards.md), mirroring
 *          OI_ValidationRuleScannerTest's established pattern.
 */
@isTest
private class OI_WorkflowRuleScannerTest {
  @isTest
  static void testEmitsOneComponentAndAnAppliesToEdgeToTheResolvedObject() {
    OI_WorkflowRuleScanner scanner = new OI_WorkflowRuleScanner(
      new FakeToolingApiAdapter(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'Name' => 'Escalate_High_Priority_Case',
            'NamespacePrefix' => null,
            'TableEnumOrId' => 'Case',
            'Metadata' => new Map<String, Object>{
              'active' => true,
              'description' => 'Escalates a Case when priority is High.',
              'triggerType' => 'onCreateOrTriggeringUpdate',
              'formula' => 'Priority = "High"'
            }
          }
        }
      )
    );

    OI_DiscoveryBatch batch = scanner.scan(
      new OI_ScanContext(null, 200, null, null, null)
    );

    System.assertEquals('WorkflowRule', batch.componentKind);
    System.assertEquals(1, batch.components.size());
    OI_DiscoveredComponent component = batch.components[0];
    System.assertEquals(
      'Escalate_High_Priority_Case',
      component.fullyQualifiedName
    );
    System.assertEquals(null, component.namespace);
    System.assertEquals('Tooling', component.sourceApi);
    System.assertEquals(true, component.rawAttributes.get('active'));
    System.assertEquals(
      'onCreateOrTriggeringUpdate',
      component.rawAttributes.get('triggerType')
    );
    System.assertEquals(
      'Priority = "High"',
      component.rawAttributes.get('formula')
    );
    System.assertEquals('Case', component.rawAttributes.get('objectApiName'));

    System.assertEquals(
      1,
      batch.relationships.size(),
      'Case is always an in-scope object, so the APPLIES_TO edge must be emitted.'
    );
    OI_DiscoveredRelationship relationship = batch.relationships[0];
    System.assertEquals('APPLIES_TO', relationship.relationshipKind);
    System.assertEquals(component.componentKey, relationship.fromComponentKey);
    System.assertEquals(
      OI_ComponentKeyUtil.build('CustomObject', null, 'Case'),
      relationship.toComponentKey
    );
    System.assertEquals(
      OI_ScanCoverage.STATUS_PARTIAL,
      batch.coverage.status,
      'Criteria formula and fired actions are not resolved into edges — a permanent, by-design boundary (Partial), not a failure (Degraded).'
    );
  }

  @isTest
  static void testNamespacedRuleBuildsAQualifiedFullyQualifiedName() {
    OI_WorkflowRuleScanner scanner = new OI_WorkflowRuleScanner(
      new FakeToolingApiAdapter(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'Name' => 'Notify_Owner',
            'NamespacePrefix' => 'acme',
            'TableEnumOrId' => 'Account',
            'Metadata' => new Map<String, Object>{ 'active' => false }
          }
        }
      )
    );

    OI_DiscoveryBatch batch = scanner.scan(
      new OI_ScanContext(null, 200, null, null, null)
    );

    System.assertEquals(1, batch.components.size());
    System.assertEquals('acme', batch.components[0].namespace);
    System.assertEquals(
      'acme.Notify_Owner',
      batch.components[0].fullyQualifiedName
    );
    System.assertEquals(false, batch.components[0].rawAttributes.get('active'));
  }

  @isTest
  static void testEmitsAComponentWithoutAnEdgeWhenTheParentObjectCannotBeResolved() {
    OI_WorkflowRuleScanner scanner = new OI_WorkflowRuleScanner(
      new FakeToolingApiAdapter(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'Name' => 'Orphaned_Rule',
            'NamespacePrefix' => null,
            /** An opaque custom-object durable Id, not a resolvable API name — OI_ScannerObjectResolver documents this exact case as resolving to null rather than a fabricated object. */
            'TableEnumOrId' => '01I000000000000AAA',
            'Metadata' => new Map<String, Object>{ 'active' => true }
          }
        }
      )
    );

    OI_DiscoveryBatch batch = scanner.scan(
      new OI_ScanContext(null, 200, null, null, null)
    );

    System.assertEquals(
      1,
      batch.components.size(),
      'A rule whose parent object could not be resolved is still a real, discovered component.'
    );
    System.assertEquals(
      0,
      batch.relationships.size(),
      'No edge can point at an unresolved object — absence of an edge, never a guess.'
    );
    System.assertEquals(
      null,
      batch.components[0].rawAttributes.get('objectApiName')
    );
  }

  @isTest
  static void testReportsDegradedCoverageRatherThanThrowingWhenTheAdapterFails() {
    OI_WorkflowRuleScanner scanner = new OI_WorkflowRuleScanner(
      new ThrowingToolingApiAdapter()
    );

    OI_DiscoveryBatch batch = scanner.scan(
      new OI_ScanContext(null, 200, null, null, null)
    );

    System.assertEquals(0, batch.components.size());
    System.assertEquals(0, batch.relationships.size());
    System.assertEquals(false, batch.isFullSnapshot);
    System.assertEquals(OI_ScanCoverage.STATUS_DEGRADED, batch.coverage.status);
    System.assertNotEquals(null, batch.coverage.reason);
  }

  private class FakeToolingApiAdapter extends OI_ToolingApiAdapter {
    private final List<Map<String, Object>> records;

    private FakeToolingApiAdapter(List<Map<String, Object>> records) {
      this.records = records;
    }

    public override List<Map<String, Object>> query(String soql) {
      return records;
    }
  }

  private class ThrowingToolingApiAdapter extends OI_ToolingApiAdapter {
    public override List<Map<String, Object>> query(String soql) {
      throw new OI_ServiceException('Simulated Tooling API failure.');
    }
  }
}
