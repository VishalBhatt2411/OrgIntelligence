/**
 * Purpose: Verifies OI_SharingRuleScanner's component/relationship shape across all four rule
 *          categories, its single-Map-vs-List<Object> normalization, its per-chunk degrade-not-
 *          abort behavior on a Metadata API failure, and its defensive callout-cap path — using
 *          DI-based fakes for OI_MetadataApiAdapter (CodingStandards.md) and OI_ScanContext's
 *          scopedApiNames seam to avoid a full org-wide Describe, mirroring
 *          OI_WorkflowRuleScannerTest/OI_EmailAlertScannerTest's established pattern.
 */
@isTest
private class OI_SharingRuleScannerTest {
  @isTest
  static void testEmitsOneComponentAndAnAppliesToEdgeForASingleRule() {
    OI_SharingRuleScanner scanner = new OI_SharingRuleScanner(
      new FakeMetadataApiAdapter(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'fullName' => 'Account',
            'sharingCriteriaRules' => new Map<String, Object>{
              'fullName' => 'Account.Share_To_Sales',
              'accessLevel' => 'Read',
              'label' => 'Share to Sales',
              'sharedTo' => new Map<String, Object>{ 'role' => 'Sales_Manager' }
            }
          }
        }
      )
    );

    OI_DiscoveryBatch batch = scanner.scan(
      new OI_ScanContext(null, 200, null, null, new Set<String>{ 'Account' })
    );

    System.assertEquals('SharingRule', batch.componentKind);
    System.assertEquals(1, batch.components.size());
    OI_DiscoveredComponent component = batch.components[0];
    System.assertEquals('Account.Share_To_Sales', component.fullyQualifiedName);
    System.assertEquals(null, component.namespace);
    System.assertEquals('Metadata', component.sourceApi);
    System.assertEquals(
      'SharingCriteriaRule',
      component.rawAttributes.get('ruleType')
    );
    System.assertEquals('Read', component.rawAttributes.get('accessLevel'));
    System.assertEquals(
      'Account',
      component.rawAttributes.get('objectApiName')
    );
    Map<String, Object> sharedTo = (Map<String, Object>) component.rawAttributes.get(
      'sharedTo'
    );
    System.assertEquals('Sales_Manager', sharedTo.get('role'));

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
      'Criteria filters and shared-to/shared-from targets are not resolved into edges — a permanent, by-design boundary (Partial), not a failure (Degraded).'
    );
    System.assertEquals(true, batch.isFullSnapshot);
  }

  @isTest
  static void testNormalizesARepeatedRuleListIntoMultipleComponents() {
    OI_SharingRuleScanner scanner = new OI_SharingRuleScanner(
      new FakeMetadataApiAdapter(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'fullName' => 'Case',
            'sharingCriteriaRules' => new List<Object>{
              new Map<String, Object>{
                'fullName' => 'Case.Share_To_Support',
                'accessLevel' => 'Edit'
              },
              new Map<String, Object>{
                'fullName' => 'Case.Share_To_Billing',
                'accessLevel' => 'Read'
              }
            }
          }
        }
      )
    );

    OI_DiscoveryBatch batch = scanner.scan(
      new OI_ScanContext(null, 200, null, null, new Set<String>{ 'Case' })
    );

    System.assertEquals(
      2,
      batch.components.size(),
      'A repeated rule list (List<Object>) must produce one component per entry.'
    );
    System.assertEquals(2, batch.relationships.size());
  }

  @isTest
  static void testEmitsComponentsAcrossAllFourRuleCategories() {
    OI_SharingRuleScanner scanner = new OI_SharingRuleScanner(
      new FakeMetadataApiAdapter(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'fullName' => 'Account',
            'sharingCriteriaRules' => new Map<String, Object>{
              'fullName' => 'Account.Criteria_Rule',
              'accessLevel' => 'Read'
            },
            'sharingGuestRules' => new Map<String, Object>{
              'fullName' => 'Account.Guest_Rule',
              'accessLevel' => 'Read'
            },
            'sharingOwnerRules' => new Map<String, Object>{
              'fullName' => 'Account.Owner_Rule',
              'accessLevel' => 'Edit',
              'sharedFrom' => new Map<String, Object>{ 'role' => 'CEO' }
            },
            'sharingTerritoryRules' => new Map<String, Object>{
              'fullName' => 'Account.Territory_Rule',
              'accessLevel' => 'Edit'
            }
          }
        }
      )
    );

    OI_DiscoveryBatch batch = scanner.scan(
      new OI_ScanContext(null, 200, null, null, new Set<String>{ 'Account' })
    );

    System.assertEquals(4, batch.components.size());
    Set<String> ruleTypes = new Set<String>();
    for (OI_DiscoveredComponent component : batch.components) {
      ruleTypes.add((String) component.rawAttributes.get('ruleType'));
    }
    System.assertEquals(
      new Set<String>{
        'SharingCriteriaRule',
        'SharingGuestRule',
        'SharingOwnerRule',
        'SharingTerritoryRule'
      },
      ruleTypes
    );
    System.assertEquals(4, batch.relationships.size());
  }

  @isTest
  static void testEmitsARuleComponentWithoutAnEdgeWhenTheObjectCannotBeResolved() {
    OI_SharingRuleScanner scanner = new OI_SharingRuleScanner(
      new FakeMetadataApiAdapter(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'fullName' => 'Not_A_Real_Object',
            'sharingCriteriaRules' => new Map<String, Object>{
              'fullName' => 'Not_A_Real_Object.Orphan_Rule',
              'accessLevel' => 'Edit'
            }
          }
        }
      )
    );

    OI_DiscoveryBatch batch = scanner.scan(
      new OI_ScanContext(null, 200, null, null, new Set<String>{ 'Account' })
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
      'Not_A_Real_Object',
      batch.components[0].rawAttributes.get('objectApiName')
    );
  }

  @isTest
  static void testExcludesOutOfScopeObjectsBeforeIssuingAnyCallout() {
    OI_SharingRuleScanner scanner = new OI_SharingRuleScanner(
      new ThrowingMetadataApiAdapter()
    );

    OI_DiscoveryBatch batch = scanner.scan(
      new OI_ScanContext(
        null,
        200,
        null,
        null,
        new Set<String>{ 'AccountHistory' }
      )
    );

    System.assertEquals(
      0,
      batch.components.size(),
      'AccountHistory is excluded by OI_ObjectScopeFilter, so no readMetadata call is ever issued for it — the throwing Adapter must never be invoked.'
    );
    System.assertEquals(
      OI_ScanCoverage.STATUS_PARTIAL,
      batch.coverage.status,
      'Zero in-scope objects is a real, complete-for-this-scope result, not a failure.'
    );
    System.assertEquals(true, batch.isFullSnapshot);
  }

  @isTest
  static void testReportsDegradedCoverageRatherThanAbortingWhenTheAdapterFails() {
    OI_SharingRuleScanner scanner = new OI_SharingRuleScanner(
      new ThrowingMetadataApiAdapter()
    );

    OI_DiscoveryBatch batch = scanner.scan(
      new OI_ScanContext(null, 200, null, null, new Set<String>{ 'Account' })
    );

    System.assertEquals(0, batch.components.size());
    System.assertEquals(0, batch.relationships.size());
    System.assertEquals(false, batch.isFullSnapshot);
    System.assertEquals(OI_ScanCoverage.STATUS_DEGRADED, batch.coverage.status);
    System.assertNotEquals(null, batch.coverage.reason);
  }

  @isTest
  static void testCapsChunkProcessingAndReportsPartialCoverageWithASkippedObjectCount() {
    OI_SharingRuleScanner.maxMetadataApiCallsOverride = 0;
    try {
      OI_SharingRuleScanner scanner = new OI_SharingRuleScanner(
        new FakeMetadataApiAdapter(new List<Map<String, Object>>())
      );

      OI_DiscoveryBatch batch = scanner.scan(
        new OI_ScanContext(null, 200, null, null, new Set<String>{ 'Account' })
      );

      System.assertEquals(
        0,
        batch.components.size(),
        'The one available chunk is skipped entirely once the cap is set to zero.'
      );
      System.assertEquals(false, batch.isFullSnapshot);
      System.assertEquals(
        OI_ScanCoverage.STATUS_PARTIAL,
        batch.coverage.status
      );
      System.assert(
        batch.coverage.reason.contains('skipped'),
        'The reason must explain that object batches were skipped due to the safety cap.'
      );
    } finally {
      OI_SharingRuleScanner.maxMetadataApiCallsOverride = null;
    }
  }

  private class FakeMetadataApiAdapter extends OI_MetadataApiAdapter {
    private final List<Map<String, Object>> results;

    private FakeMetadataApiAdapter(List<Map<String, Object>> results) {
      this.results = results;
    }

    public override List<Map<String, Object>> readMetadata(
      String metadataType,
      List<String> fullNames
    ) {
      return results;
    }
  }

  private class ThrowingMetadataApiAdapter extends OI_MetadataApiAdapter {
    public override List<Map<String, Object>> readMetadata(
      String metadataType,
      List<String> fullNames
    ) {
      throw new OI_ServiceException('Simulated Metadata API failure.');
    }
  }
}
