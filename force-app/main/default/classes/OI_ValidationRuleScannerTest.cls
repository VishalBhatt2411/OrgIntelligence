/**
 * Purpose: Verifies OI_ValidationRuleScanner's component/relationship shape and its "report
 *          degraded rather than throw" behavior on a Tooling API failure, using DI-based fakes
 *          for OI_ToolingApiAdapter (CodingStandards.md) rather than a real HTTP callout —
 *          mirroring OI_ObjectSharingSettingsServiceTest's own established pattern.
 */
@isTest
private class OI_ValidationRuleScannerTest {
  @isTest
  static void testEmitsOneComponentAndAValidatesEdgeToTheResolvedObject() {
    OI_ValidationRuleScanner scanner = new OI_ValidationRuleScanner(
      new FakeToolingApiAdapter(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'ValidationName' => 'Amount_Must_Be_Positive',
            'NamespacePrefix' => null,
            'EntityDefinition' => new Map<String, Object>{
              'QualifiedApiName' => 'Opportunity'
            },
            'Metadata' => new Map<String, Object>{
              'active' => true,
              'description' => 'Guards against a negative Amount.',
              'errorConditionFormula' => 'Amount < 0',
              'errorDisplayField' => 'Amount',
              'errorMessage' => 'Amount must be zero or greater.'
            }
          }
        }
      )
    );

    OI_DiscoveryBatch batch = scanner.scan(
      new OI_ScanContext(null, 200, null, null, null)
    );

    System.assertEquals('ValidationRule', batch.componentKind);
    System.assertEquals(1, batch.components.size());
    OI_DiscoveredComponent component = batch.components[0];
    System.assertEquals(
      'Amount_Must_Be_Positive',
      component.fullyQualifiedName
    );
    System.assertEquals(null, component.namespace);
    System.assertEquals('Tooling', component.sourceApi);
    System.assertEquals(true, component.rawAttributes.get('active'));
    System.assertEquals(
      'Amount < 0',
      component.rawAttributes.get('errorConditionFormula')
    );
    System.assertEquals(
      'Amount must be zero or greater.',
      component.rawAttributes.get('errorMessage')
    );
    System.assertEquals(
      'Opportunity',
      component.rawAttributes.get('objectApiName')
    );

    System.assertEquals(
      1,
      batch.relationships.size(),
      'Opportunity is always an in-scope object, so the VALIDATES edge must be emitted.'
    );
    OI_DiscoveredRelationship relationship = batch.relationships[0];
    System.assertEquals('VALIDATES', relationship.relationshipKind);
    System.assertEquals(component.componentKey, relationship.fromComponentKey);
    System.assertEquals(
      OI_ComponentKeyUtil.build('CustomObject', null, 'Opportunity'),
      relationship.toComponentKey
    );
    System.assertEquals(
      OI_ScanCoverage.STATUS_PARTIAL,
      batch.coverage.status,
      'Formula field references are not resolved into edges — that is a permanent, by-design boundary (Partial), not a failure (Degraded).'
    );
  }

  @isTest
  static void testNamespacedRuleBuildsAQualifiedFullyQualifiedName() {
    OI_ValidationRuleScanner scanner = new OI_ValidationRuleScanner(
      new FakeToolingApiAdapter(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'ValidationName' => 'Require_Region',
            'NamespacePrefix' => 'acme',
            'EntityDefinition' => new Map<String, Object>{
              'QualifiedApiName' => 'Account'
            },
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
      'acme.Require_Region',
      batch.components[0].fullyQualifiedName
    );
    System.assertEquals(false, batch.components[0].rawAttributes.get('active'));
  }

  @isTest
  static void testEmitsAComponentWithoutAnEdgeWhenTheParentObjectCannotBeResolved() {
    OI_ValidationRuleScanner scanner = new OI_ValidationRuleScanner(
      new FakeToolingApiAdapter(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'ValidationName' => 'Orphaned_Rule',
            'NamespacePrefix' => null,
            'EntityDefinition' => null,
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
  }

  @isTest
  static void testReportsDegradedCoverageRatherThanThrowingWhenTheAdapterFails() {
    OI_ValidationRuleScanner scanner = new OI_ValidationRuleScanner(
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
