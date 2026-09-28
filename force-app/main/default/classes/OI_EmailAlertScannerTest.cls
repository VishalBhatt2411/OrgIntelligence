/**
 * Purpose: Verifies OI_EmailAlertScanner's component/relationship shape and its "report degraded
 *          rather than throw" behavior on a Tooling API failure, using DI-based fakes for
 *          OI_ToolingApiAdapter (CodingStandards.md), mirroring OI_ValidationRuleScannerTest's
 *          established pattern.
 */
@isTest
private class OI_EmailAlertScannerTest {
  @isTest
  static void testEmitsOneComponentAndAnAppliesToEdgeToTheResolvedObject() {
    OI_EmailAlertScanner scanner = new OI_EmailAlertScanner(
      new FakeToolingApiAdapter(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'DeveloperName' => 'Notify_Account_Owner',
            'NamespacePrefix' => null,
            'Description' => 'Notifies the Account owner of a change.',
            'CcEmails' => 'ops@example.com',
            'SenderType' => 'OrgWideEmailAddress',
            'TemplateId' => '00X000000000001AAA',
            'EntityDefinition' => new Map<String, Object>{
              'QualifiedApiName' => 'Account'
            }
          }
        }
      )
    );

    OI_DiscoveryBatch batch = scanner.scan(
      new OI_ScanContext(null, 200, null, null, null)
    );

    System.assertEquals('EmailAlert', batch.componentKind);
    System.assertEquals(1, batch.components.size());
    OI_DiscoveredComponent component = batch.components[0];
    System.assertEquals('Notify_Account_Owner', component.fullyQualifiedName);
    System.assertEquals(null, component.namespace);
    System.assertEquals('Tooling', component.sourceApi);
    System.assertEquals(
      'ops@example.com',
      component.rawAttributes.get('ccEmails')
    );
    System.assertEquals(
      'OrgWideEmailAddress',
      component.rawAttributes.get('senderType')
    );
    System.assertEquals(
      'Account',
      component.rawAttributes.get('objectApiName')
    );

    System.assertEquals(
      1,
      batch.relationships.size(),
      'Account is always an in-scope object, so the APPLIES_TO edge must be emitted.'
    );
    OI_DiscoveredRelationship relationship = batch.relationships[0];
    System.assertEquals('APPLIES_TO', relationship.relationshipKind);
    System.assertEquals(component.componentKey, relationship.fromComponentKey);
    System.assertEquals(
      OI_ComponentKeyUtil.build('CustomObject', null, 'Account'),
      relationship.toComponentKey
    );
    System.assertEquals(
      OI_ScanCoverage.STATUS_PARTIAL,
      batch.coverage.status,
      'The recipient list is a permanent Tooling API boundary (Partial), not a failure (Degraded).'
    );
  }

  @isTest
  static void testNamespacedAlertBuildsAQualifiedFullyQualifiedName() {
    OI_EmailAlertScanner scanner = new OI_EmailAlertScanner(
      new FakeToolingApiAdapter(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'DeveloperName' => 'Escalation_Alert',
            'NamespacePrefix' => 'acme',
            'EntityDefinition' => new Map<String, Object>{
              'QualifiedApiName' => 'Case'
            }
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
      'acme.Escalation_Alert',
      batch.components[0].fullyQualifiedName
    );
  }

  @isTest
  static void testEmitsAComponentWithoutAnEdgeWhenTheParentObjectCannotBeResolved() {
    OI_EmailAlertScanner scanner = new OI_EmailAlertScanner(
      new FakeToolingApiAdapter(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'DeveloperName' => 'Orphaned_Alert',
            'NamespacePrefix' => null,
            'EntityDefinition' => null
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
      'An alert whose parent object could not be resolved is still a real, discovered component.'
    );
    System.assertEquals(
      0,
      batch.relationships.size(),
      'No edge can point at an unresolved object — absence of an edge, never a guess.'
    );
  }

  @isTest
  static void testReportsDegradedCoverageRatherThanThrowingWhenTheAdapterFails() {
    OI_EmailAlertScanner scanner = new OI_EmailAlertScanner(
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
