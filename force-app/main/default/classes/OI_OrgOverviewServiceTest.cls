/**
 * Purpose: Verifies OI_OrgOverviewService's per-type node counts, dependency/relationship
 *          edge counts, and scan-freshness resolution.
 */
@isTest
private class OI_OrgOverviewServiceTest {
  @isTest
  static void testGetOrgOverviewCountsEachNodeTypeIndependently() {
    insert new List<OI_Graph_Node__c>{
      new OI_Graph_Node__c(
        Node_Key__c = 'o1',
        Node_Version_Key__c = 'o1::v1',
        Version_Number__c = 1,
        Node_Type__c = 'SalesforceMetadata.CustomObject',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'o2',
        Node_Version_Key__c = 'o2::v1',
        Version_Number__c = 1,
        Node_Type__c = 'SalesforceMetadata.CustomObject',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'f1',
        Node_Version_Key__c = 'f1::v1',
        Version_Number__c = 1,
        Node_Type__c = 'SalesforceMetadata.CustomField',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'a1',
        Node_Version_Key__c = 'a1::v1',
        Version_Number__c = 1,
        Node_Type__c = 'SalesforceMetadata.ApexClass',
        State__c = 'Active',
        Is_Current__c = true
      )
    };

    OI_OrgOverviewDTO dto = new OI_OrgOverviewService().getOrgOverview();

    System.assertEquals(2, dto.objectCount);
    System.assertEquals(1, dto.fieldCount);
    System.assertEquals(1, dto.apexClassCount);
    System.assertEquals(
      0,
      dto.triggerCount,
      'A node type with zero current rows must report 0, not null.'
    );
    System.assertEquals(0, dto.flowCount);
    System.assertEquals(
      [SELECT COUNT() FROM PermissionSet WHERE IsOwnedByProfile = FALSE],
      dto.permissionSetCount,
      'With no PermissionSet nodes in the graph, the KPI must fall back to the live standalone count, not report 0.'
    );
  }

  /** Once PermissionSet nodes are persisted, the graph count is authoritative and no live fallback applies. */
  @isTest
  static void testPermissionSetCountPrefersPersistedNodes() {
    insert new OI_Graph_Node__c(
      Node_Key__c = 'ps1',
      Node_Version_Key__c = 'ps1::v1',
      Version_Number__c = 1,
      Node_Type__c = 'SalesforceMetadata.PermissionSet',
      State__c = 'Active',
      Is_Current__c = true
    );

    System.assertEquals(
      1,
      new OI_OrgOverviewService().getOrgOverview().permissionSetCount
    );
  }

  /** ADR-0031: only relationship fields are persisted, so the Fields KPI sums each object's scanned fieldCount. */
  @isTest
  static void testFieldCountSumsScannedObjectAttributesInsteadOfFieldNodes() {
    insert new List<OI_Graph_Node__c>{
      objectNode('o1', '{"fieldCount":40,"customFieldCount":5}'),
      objectNode('o2', '{"fieldCount":12,"customFieldCount":12}'),
      new OI_Graph_Node__c(
        Node_Key__c = 'f1',
        Node_Version_Key__c = 'f1::v1',
        Version_Number__c = 1,
        Node_Type__c = 'SalesforceMetadata.CustomField',
        State__c = 'Active',
        Is_Current__c = true
      )
    };

    System.assertEquals(
      52,
      new OI_OrgOverviewService().getOrgOverview().fieldCount
    );
  }

  @isTest
  static void testFieldCountFallsBackToFieldNodesWhenAnyObjectPredatesTheAttribute() {
    insert new List<OI_Graph_Node__c>{
      objectNode('o1', '{"fieldCount":40}'),
      objectNode('o2', null),
      new OI_Graph_Node__c(
        Node_Key__c = 'f1',
        Node_Version_Key__c = 'f1::v1',
        Version_Number__c = 1,
        Node_Type__c = 'SalesforceMetadata.CustomField',
        State__c = 'Active',
        Is_Current__c = true
      )
    };

    System.assertEquals(
      1,
      new OI_OrgOverviewService().getOrgOverview().fieldCount,
      'A partial sum would undercount, so a mixed graph reports the persisted field-node count.'
    );
  }

  private static OI_Graph_Node__c objectNode(
    String key,
    String attributesJson
  ) {
    return new OI_Graph_Node__c(
      Node_Key__c = key,
      Node_Version_Key__c = key + '::v1',
      Version_Number__c = 1,
      Node_Type__c = 'SalesforceMetadata.CustomObject',
      Attributes_Json__c = attributesJson,
      State__c = 'Active',
      Is_Current__c = true
    );
  }

  @isTest
  static void testGetOrgOverviewSplitsDependencyAndRelationshipCountsCorrectly() {
    insert new List<OI_Graph_Edge__c>{
      new OI_Graph_Edge__c(
        Edge_Key__c = 'e1',
        Edge_Version_Key__c = 'e1::v1',
        Version_Number__c = 1,
        Edge_Type__c = 'SalesforceMetadata.REFERENCES',
        Source_Node_Key__c = 's',
        Target_Node_Key__c = 't',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Edge__c(
        Edge_Key__c = 'e2',
        Edge_Version_Key__c = 'e2::v1',
        Version_Number__c = 1,
        Edge_Type__c = 'SalesforceMetadata.HAS_FIELD',
        Source_Node_Key__c = 's',
        Target_Node_Key__c = 't',
        State__c = 'Active',
        Is_Current__c = true
      )
    };

    OI_OrgOverviewDTO dto = new OI_OrgOverviewService().getOrgOverview();

    System.assertEquals(
      1,
      dto.dependencyCount,
      'Only SalesforceMetadata.REFERENCES/EXECUTES_ON/GRANTS_ACCESS_TO count as dependencies (OI_DependencyEngineService.DEPENDENCY_EDGE_TYPE_KEYS).'
    );
    System.assertEquals(
      2,
      dto.relationshipCount,
      'Relationships is the unfiltered total current edge count.'
    );
  }

  @isTest
  static void testGetOrgOverviewReturnsNullLastScannedAtWhenNoScanHasCompleted() {
    OI_OrgOverviewDTO dto = new OI_OrgOverviewService().getOrgOverview();
    System.assertEquals(
      null,
      dto.lastScannedAt,
      'No completed OI_Scan_Run__c must resolve to null, not a fabricated freshness claim.'
    );
  }

  @isTest
  static void testGetOrgOverviewResolvesLastScannedAtFromMostRecentCompletedRun() {
    insert new OI_Scan_Run__c(Status__c = 'Completed', Scan_Type__c = 'Full');
    OI_OrgOverviewDTO dto = new OI_OrgOverviewService().getOrgOverview();
    System.assertNotEquals(null, dto.lastScannedAt);
  }
}
