/**
 * Purpose: Verifies OI_OrgHealthController's thin permission-check -> Service-call -> DTO
 *          contract, and that every method denies access with a sanitized
 *          AuraHandledException when OI_View_Org_Health is not assigned (API.md §2.1,
 *          mirroring OI_GraphControllerTest's own pattern).
 */
@isTest
private class OI_OrgHealthControllerTest {
  @isTest
  static void testGetOrgHealthSummaryReturnsOverviewAndSectionCards() {
    OI_OrgHealthSummaryDTO result = OI_OrgHealthController.getOrgHealthSummary();
    System.assertNotEquals(null, result.overview);
    System.assert(!result.sections.isEmpty());
  }

  @isTest
  static void testGetOrgOverviewDetailReturnsRealCounts() {
    insert new OI_Graph_Node__c(
      Node_Key__c = 'ctlOv1',
      Node_Version_Key__c = 'ctlOv1::v1',
      Version_Number__c = 1,
      Node_Type__c = 'SalesforceMetadata.CustomObject',
      State__c = 'Active',
      Is_Current__c = true
    );

    OI_OrgOverviewDTO result = OI_OrgHealthController.getOrgOverviewDetail();

    System.assertEquals(1, result.objectCount);
  }

  @isTest
  static void testGetStorageDetailReturnsLiveOrgLimits() {
    OI_StorageHealthDTO result = OI_OrgHealthController.getStorageDetail();
    System.assertNotEquals(null, result.dataLimitMb);
  }

  @isTest
  static void testGetMetadataHealthDetailReturnsRealComputedResult() {
    insert new OI_Graph_Node__c(
      Node_Key__c = 'ctlMd1',
      Node_Version_Key__c = 'ctlMd1::v1',
      Version_Number__c = 1,
      Node_Type__c = 'SalesforceMetadata.CustomObject',
      Label__c = 'Ctl_Object__c',
      State__c = 'Active',
      Is_Current__c = true
    );

    OI_MetadataHealthDTO result = OI_OrgHealthController.getMetadataHealthDetail();

    System.assertEquals(4, result.kpiTiles.size());
    System.assertEquals(3, result.formulaComponents.size());
    for (OI_HealthKeyValueDTO tile : result.kpiTiles) {
      System.assert(
        String.isNotBlank(tile.metricKey),
        'Every Metadata Health KPI tile must carry a metricKey so the LWC knows it is clickable.'
      );
    }
  }

  @isTest
  static void testGetMetadataHealthKpiDrilldownReturnsMatchingObjects() {
    insert new OI_Graph_Node__c(
      Node_Key__c = 'ctlMdKpi1',
      Node_Version_Key__c = 'ctlMdKpi1::v1',
      Version_Number__c = 1,
      Node_Type__c = 'SalesforceMetadata.CustomObject',
      Label__c = 'Ctl_Kpi_Object__c',
      State__c = 'Active',
      Is_Current__c = true
    );

    OI_HealthKpiDrilldownDTO result = OI_OrgHealthController.getMetadataHealthKpiDrilldown(
      'OrphanRate'
    );

    System.assertEquals(
      1,
      result.rows.size(),
      'The lone fixture object has 0 incoming references and must appear in its own drill-down.'
    );
    System.assertEquals('ctlMdKpi1', result.rows[0].key);
  }

  @isTest
  static void testGetMetadataHealthKpiDrilldownWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getMetadataHealthKpiDrilldown('HighFieldCount');
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testGetAutomationHealthDetailReturnsRealComputedResult() {
    insert new OI_Graph_Node__c(
      Node_Key__c = 'ctlAu1',
      Node_Version_Key__c = 'ctlAu1::v1',
      Version_Number__c = 1,
      Node_Type__c = 'SalesforceMetadata.ApexTrigger',
      Label__c = 'CtlTrigger',
      State__c = 'Active',
      Is_Current__c = true
    );

    OI_AutomationHealthDTO result = OI_OrgHealthController.getAutomationHealthDetail();

    System.assertEquals(5, result.kpiTiles.size());
    System.assert(result.coverageNote.contains('1'));
  }

  @isTest
  static void testGetCodeHealthDetailReturnsRealComputedResult() {
    OI_CodeHealthDTO result = OI_OrgHealthController.getCodeHealthDetail();

    System.assertEquals(2, result.formulaComponents.size());
    System.assertEquals(4, result.kpiTiles.size());
  }

  @isTest
  static void testGetSecurityHealthDetailReturnsRealComputedResult() {
    OI_SecurityHealthDTO result = OI_OrgHealthController.getSecurityHealthDetail();

    System.assertEquals(5, result.kpiTiles.size());
    System.assert(String.isNotBlank(result.coverageNote));
  }

  @isTest
  static void testGetDataHealthDetailReturnsHonestNotYetComputedStateBeforeAnyRun() {
    OI_DataHealthDTO result = OI_OrgHealthController.getDataHealthDetail();

    System.assertEquals('NotYetRun', result.runStatus);
    System.assertEquals(null, result.score);
  }

  /**
   * The one real Database.executeBatch invocation in the entire test suite for
   * OI_DataHealthComputeBatchable — every other test drives start()/execute()/finish()
   * directly instead (OI_DataHealthComputeBatchableTest, OI_OrgHealthSummaryServiceTest),
   * since Salesforce allows at most one such call per test method and an unwrapped call
   * (outside Test.startTest()/Test.stopTest()) is evaluated against the surrounding test
   * run's aggregate async context rather than this method's own, tripping the same
   * "No more than one executeBatch can be called from within a test method" error even
   * when it is the only real call — Test.startTest()/Test.stopTest() is what correctly
   * scopes it to just this method.
   */
  @isTest
  static void testRecomputeDataHealthEnqueuesTheBatchAndReturnsQueued() {
    Test.startTest();
    String result = OI_OrgHealthController.recomputeDataHealth();
    Test.stopTest();

    System.assertEquals('Queued', result);
    List<AsyncApexJob> jobs = [
      SELECT Id, Status
      FROM AsyncApexJob
      WHERE ApexClass.Name = 'OI_DataHealthComputeBatchable'
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    System.assertEquals(
      1,
      jobs.size(),
      'A real batch job must have been enqueued.'
    );
  }

  @isTest
  static void testGetSeverityRegistryReturnsSeedRecords() {
    List<OI_HealthSeverityDescriptorDTO> result = OI_OrgHealthController.getSeverityRegistry();
    System.assertEquals(3, result.size());
  }

  @isTest
  static void testSyncMetadataHealthFindingsComputesAndPersistsRealFindings() {
    insert new OI_Graph_Node__c(
      Node_Key__c = 'ctlFind1',
      Node_Version_Key__c = 'ctlFind1::v1',
      Version_Number__c = 1,
      Node_Type__c = 'SalesforceMetadata.CustomObject',
      Label__c = 'Ctl_Finding_Object__c',
      Secondary_Key__c = 'OI_Org_Health_Finding__c',
      State__c = 'Active',
      Is_Current__c = true
    );
    List<OI_Graph_Node__c> fieldNodes = new List<OI_Graph_Node__c>();
    for (Integer i = 0; i < 100; i++) {
      String fieldKey = 'ctlFind1_f' + i;
      fieldNodes.add(
        new OI_Graph_Node__c(
          Node_Key__c = fieldKey,
          Node_Version_Key__c = fieldKey + '::v1',
          Version_Number__c = 1,
          Node_Type__c = 'SalesforceMetadata.CustomField',
          Label__c = 'Field ' + i,
          Secondary_Key__c = 'OI_Org_Health_Finding__c.Field_' + i + '__c',
          Parent_Key__c = 'ctlFind1',
          State__c = 'Active',
          Is_Current__c = true
        )
      );
    }
    insert fieldNodes;

    String result = OI_OrgHealthController.syncMetadataHealthFindings();

    System.assertEquals('Synced', result);
    List<OI_OrgHealthFindingDTO> findings = OI_OrgHealthController.getMetadataHealthFindings();
    Boolean foundHighFieldCountFinding = false;
    for (OI_OrgHealthFindingDTO finding : findings) {
      if (
        finding.componentKey == 'ctlFind1' &&
        finding.ruleId == 'MetadataHealth.HighFieldCount'
      ) {
        foundHighFieldCountFinding = true;
        System.assertEquals('Open', finding.status);
        System.assert(String.isNotBlank(finding.evidence));
      }
    }
    System.assert(
      foundHighFieldCountFinding,
      'A real, evidence-based HighFieldCount finding must be persisted and readable back.'
    );
  }

  @isTest
  static void testUpdateFindingStatusAppliesTheAdministratorsTriageDecision() {
    insert new OI_Graph_Node__c(
      Node_Key__c = 'ctlFind2',
      Node_Version_Key__c = 'ctlFind2::v1',
      Version_Number__c = 1,
      Node_Type__c = 'SalesforceMetadata.CustomObject',
      Label__c = 'Ctl_Finding_Object_Two__c',
      State__c = 'Active',
      Is_Current__c = true
    );
    OI_OrgHealthController.syncMetadataHealthFindings();
    Id findingId = OI_OrgHealthController.getMetadataHealthFindings()[0].id;

    OI_OrgHealthController.updateFindingStatus(
      findingId,
      'Acknowledged',
      'Reviewed.',
      Date.today().addDays(14),
      UserInfo.getUserId(),
      null,
      null,
      null
    );

    OI_OrgHealthFindingDTO updated;
    for (
      OI_OrgHealthFindingDTO finding : OI_OrgHealthController.getMetadataHealthFindings()
    ) {
      if (finding.id == findingId) {
        updated = finding;
      }
    }
    System.assertEquals('Acknowledged', updated.status);
    System.assertEquals('Reviewed.', updated.notes);
    System.assertEquals(Date.today().addDays(14), updated.dueDate);
  }

  @isTest
  static void testSyncAutomationHealthFindingsComputesAndPersistsRealFindings() {
    insert new OI_Graph_Node__c(
      Node_Key__c = 'ctlAuFind1',
      Node_Version_Key__c = 'ctlAuFind1::v1',
      Version_Number__c = 1,
      Node_Type__c = 'SalesforceMetadata.ApexTrigger',
      Label__c = 'CtlAutomationTrigger',
      State__c = 'Active',
      Is_Current__c = true
    );
    insert new OI_Graph_Node__c(
      Node_Key__c = 'ctlAuFind2',
      Node_Version_Key__c = 'ctlAuFind2::v1',
      Version_Number__c = 1,
      Node_Type__c = 'SalesforceMetadata.ApexTrigger',
      Label__c = 'CtlAutomationTriggerTwo',
      State__c = 'Active',
      Is_Current__c = true
    );
    insert new OI_Graph_Edge__c(
      Edge_Key__c = 'ctlAuFind1::REFERENCES::ctlAuFind2',
      Edge_Version_Key__c = 'ctlAuFind1::REFERENCES::ctlAuFind2::v1',
      Version_Number__c = 1,
      Edge_Type__c = 'SalesforceMetadata.REFERENCES',
      Source_Node_Key__c = 'ctlAuFind1',
      Target_Node_Key__c = 'ctlAuFind2',
      State__c = 'Active',
      Is_Current__c = true
    );
    insert new OI_Graph_Edge__c(
      Edge_Key__c = 'ctlAuFind2::REFERENCES::ctlAuFind1',
      Edge_Version_Key__c = 'ctlAuFind2::REFERENCES::ctlAuFind1::v1',
      Version_Number__c = 1,
      Edge_Type__c = 'SalesforceMetadata.REFERENCES',
      Source_Node_Key__c = 'ctlAuFind2',
      Target_Node_Key__c = 'ctlAuFind1',
      State__c = 'Active',
      Is_Current__c = true
    );

    String result = OI_OrgHealthController.syncAutomationHealthFindings();

    System.assertEquals('Synced', result);
    List<OI_OrgHealthFindingDTO> findings = OI_OrgHealthController.getAutomationHealthFindings();
    Boolean foundCycleFinding = false;
    for (OI_OrgHealthFindingDTO finding : findings) {
      if (
        finding.componentKey == 'ctlAuFind1' &&
        finding.ruleId == 'AutomationHealth.DependencyCycle'
      ) {
        foundCycleFinding = true;
        System.assertEquals('Open', finding.status);
        System.assert(String.isNotBlank(finding.evidence));
      }
    }
    System.assert(
      foundCycleFinding,
      'A real, evidence-based DependencyCycle finding must be persisted and readable back.'
    );
  }

  @isTest
  static void testGetAutomationHealthFindingsWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getAutomationHealthFindings();
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testSyncAutomationHealthFindingsWithoutRunComputePermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.syncAutomationHealthFindings();
        System.assert(
          false,
          'Expected AuraHandledException when OI_Run_Org_Health_Compute is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  /**
   * ApexClass cannot be seeded via DML (mirrors OI_CodeHealthServiceTest's own documented
   * constraint), so this uses OI_CodeHealthService.deriveNodeKey (@TestVisible) to derive two
   * real, already-deployed classes' node keys and control their dependency-cycle evidence via
   * freely-insertable OI_Graph_Edge__c rows. Both endpoints must be real classes — cycle
   * detection only considers edges where BOTH endpoints are within the scanned class set.
   */
  @isTest
  static void testSyncCodeHealthFindingsComputesAndPersistsRealFindings() {
    String subjectKey = OI_CodeHealthService.deriveNodeKey(null, 'OI_HashUtil');
    String partnerKey = OI_CodeHealthService.deriveNodeKey(
      null,
      'OI_GraphEngine'
    );
    insert new List<OI_Graph_Edge__c>{
      new OI_Graph_Edge__c(
        Edge_Key__c = subjectKey + '::REFERENCES::' + partnerKey,
        Edge_Version_Key__c = subjectKey +
          '::REFERENCES::' +
          partnerKey +
          '::v1',
        Version_Number__c = 1,
        Edge_Type__c = 'SalesforceMetadata.REFERENCES',
        Source_Node_Key__c = subjectKey,
        Target_Node_Key__c = partnerKey,
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Edge__c(
        Edge_Key__c = partnerKey + '::REFERENCES::' + subjectKey,
        Edge_Version_Key__c = partnerKey +
          '::REFERENCES::' +
          subjectKey +
          '::v1',
        Version_Number__c = 1,
        Edge_Type__c = 'SalesforceMetadata.REFERENCES',
        Source_Node_Key__c = partnerKey,
        Target_Node_Key__c = subjectKey,
        State__c = 'Active',
        Is_Current__c = true
      )
    };

    String result = OI_OrgHealthController.syncCodeHealthFindings();

    System.assertEquals('Synced', result);
    List<OI_OrgHealthFindingDTO> findings = OI_OrgHealthController.getCodeHealthFindings();
    Boolean foundCycleFinding = false;
    for (OI_OrgHealthFindingDTO finding : findings) {
      if (
        finding.componentKey == subjectKey &&
        finding.ruleId == 'CodeHealth.DependencyCycle'
      ) {
        foundCycleFinding = true;
        System.assertEquals('Open', finding.status);
        System.assert(String.isNotBlank(finding.evidence));
      }
    }
    System.assert(
      foundCycleFinding,
      'A real, evidence-based DependencyCycle finding must be persisted and readable back.'
    );
  }

  @isTest
  static void testGetCodeHealthFindingsWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getCodeHealthFindings();
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testSyncCodeHealthFindingsWithoutRunComputePermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.syncCodeHealthFindings();
        System.assert(
          false,
          'Expected AuraHandledException when OI_Run_Org_Health_Compute is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @TestSetup
  static void setupSensitiveGrant() {
    PermissionSet sensitiveGrant = new PermissionSet(
      Name = 'OI_Ctl_Test_Sensitive',
      Label = 'OI Ctl Test Sensitive'
    );
    insert sensitiveGrant;
    insert new ObjectPermissions(
      ParentId = sensitiveGrant.Id,
      SobjectType = 'Contact',
      PermissionsRead = true,
      PermissionsCreate = true,
      PermissionsEdit = true,
      PermissionsDelete = true,
      PermissionsViewAllRecords = true,
      PermissionsModifyAllRecords = true
    );
    insert new PermissionSetAssignment(
      AssigneeId = UserInfo.getUserId(),
      PermissionSetId = sensitiveGrant.Id
    );
  }

  @isTest
  static void testSyncSecurityHealthFindingsComputesAndPersistsRealFindings() {
    PermissionSet sensitiveGrant = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'OI_Ctl_Test_Sensitive'
      LIMIT 1
    ];

    String result = OI_OrgHealthController.syncSecurityHealthFindings();

    System.assertEquals('Synced', result);
    List<OI_OrgHealthFindingDTO> findings = OI_OrgHealthController.getSecurityHealthFindings();
    Boolean foundSensitiveFinding = false;
    for (OI_OrgHealthFindingDTO finding : findings) {
      if (
        finding.componentKey == sensitiveGrant.Id &&
        finding.ruleId == 'SecurityHealth.SensitiveObjectGrant'
      ) {
        foundSensitiveFinding = true;
        System.assertEquals('Open', finding.status);
        System.assertEquals('Critical', finding.severityKey);
        System.assert(String.isNotBlank(finding.evidence));
      }
    }
    System.assert(
      foundSensitiveFinding,
      'A real, evidence-based SensitiveObjectGrant finding must be persisted and readable back.'
    );
  }

  @isTest
  static void testGetSecurityHealthFindingsWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getSecurityHealthFindings();
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testSyncSecurityHealthFindingsWithoutRunComputePermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.syncSecurityHealthFindings();
        System.assert(
          false,
          'Expected AuraHandledException when OI_Run_Org_Health_Compute is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testGetMetadataHealthFindingsWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getMetadataHealthFindings();
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testSyncMetadataHealthFindingsWithoutRunComputePermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.syncMetadataHealthFindings();
        System.assert(
          false,
          'Expected AuraHandledException when OI_Run_Org_Health_Compute is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testUpdateFindingStatusWithoutManageFindingWorkflowPermissionThrowsAuraHandledException() {
    insert new OI_Graph_Node__c(
      Node_Key__c = 'ctlFind3',
      Node_Version_Key__c = 'ctlFind3::v1',
      Version_Number__c = 1,
      Node_Type__c = 'SalesforceMetadata.CustomObject',
      Label__c = 'Ctl_Finding_Object_Three__c',
      State__c = 'Active',
      Is_Current__c = true
    );
    OI_OrgHealthController.syncMetadataHealthFindings();
    Id findingId = OI_OrgHealthController.getMetadataHealthFindings()[0].id;

    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.updateFindingStatus(
          findingId,
          'Acknowledged',
          null,
          null,
          null,
          null,
          null,
          null
        );
        System.assert(
          false,
          'Expected AuraHandledException when OI_Manage_Finding_Workflow is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testGetOrgHealthSummaryWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getOrgHealthSummary();
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testGetOrgOverviewDetailWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getOrgOverviewDetail();
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testGetStorageDetailWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getStorageDetail();
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testGetMetadataHealthDetailWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getMetadataHealthDetail();
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testGetAutomationHealthDetailWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getAutomationHealthDetail();
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testGetCodeHealthDetailWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getCodeHealthDetail();
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testGetSecurityHealthDetailWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getSecurityHealthDetail();
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testGetDataHealthDetailWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getDataHealthDetail();
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  /** recomputeDataHealth is gated by a different, narrower permission than every read method above — this must be tested separately, not lumped in with OI_View_Org_Health's coverage. */
  @isTest
  static void testRecomputeDataHealthWithoutRunComputePermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.recomputeDataHealth();
        System.assert(
          false,
          'Expected AuraHandledException when OI_Run_Org_Health_Compute is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  /** getDataHealthFindings is gated by OI_View_Org_Health like every other read method — Data Health has no separate syncDataHealthFindings write method to test, since finding sync happens inside OI_DataHealthComputeBatchable's own finish(). */
  @isTest
  static void testGetDataHealthFindingsWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getDataHealthFindings();
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testGetSeverityRegistryWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getSeverityRegistry();
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  /** The Remediation Management workspace's own read path (ADR-0027 lifecycle extension) — end-to-end through the Controller, proving the whole plumbing (Repository query -> Service DTO shaping -> Controller) works, not just the Service layer in isolation. */
  @isTest
  static void testGetRemediationQueueAndSummaryReturnRealCrossSectionData() {
    insert new OI_Graph_Node__c(
      Node_Key__c = 'ctlRem1',
      Node_Version_Key__c = 'ctlRem1::v1',
      Version_Number__c = 1,
      Node_Type__c = 'SalesforceMetadata.CustomObject',
      Label__c = 'Ctl_Remediation_Object__c',
      State__c = 'Active',
      Is_Current__c = true
    );
    OI_OrgHealthController.syncMetadataHealthFindings();

    OI_RemediationFilterDTO filter = new OI_RemediationFilterDTO();
    filter.sectionKeys = new List<String>{ 'MetadataHealth' };
    OI_RemediationQueryResultDTO queueResult = OI_OrgHealthController.getRemediationQueue(
      filter
    );
    System.assert(
      queueResult.totalCount > 0,
      'A real MetadataHealth finding must be visible through the cross-section queue when filtered to that section.'
    );
    System.assert(!queueResult.findings.isEmpty());

    OI_RemediationSummaryDTO summary = OI_OrgHealthController.getRemediationSummary();
    System.assert(summary.totalOpenFindings > 0);
    System.assert(!summary.countBySeverity.isEmpty());

    List<OI_OrgHealthFindingDTO> exported = OI_OrgHealthController.exportRemediationQueue(
      filter
    );
    System.assertEquals(
      queueResult.totalCount,
      exported.size(),
      'Export (no page cap) must return at least as many rows as one filtered page reported as the total.'
    );

    List<OI_FindingHistoryDTO> history = OI_OrgHealthController.getFindingHistory(
      queueResult.findings[0].id
    );
    System.assertEquals(
      0,
      history.size(),
      'A freshly-synced finding with no lifecycle edits yet has an honestly empty history.'
    );
  }

  @isTest
  static void testGetRemediationQueueWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getRemediationQueue(
          new OI_RemediationFilterDTO()
        );
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testGetRemediationSummaryWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getRemediationSummary();
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testExportRemediationQueueWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.exportRemediationQueue(
          new OI_RemediationFilterDTO()
        );
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  @isTest
  static void testGetFindingHistoryWithoutPermissionThrowsAuraHandledException() {
    System.runAs(createUnprivilegedTestUser()) {
      try {
        OI_OrgHealthController.getFindingHistory(null);
        System.assert(
          false,
          'Expected AuraHandledException when OI_View_Org_Health is not assigned.'
        );
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }

  private static User createUnprivilegedTestUser() {
    Profile standardProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    String uniqueSuffix = String.valueOf(Crypto.getRandomInteger()).right(8);
    User u = new User(
      FirstName = 'OI Test',
      LastName = 'Unprivileged' + uniqueSuffix,
      Email = 'oi.test.' + uniqueSuffix + '@example.invalid',
      Username = 'oi.test.' + uniqueSuffix + '@example.invalid',
      Alias = 'oitst' + uniqueSuffix.left(3),
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = standardProfile.Id
    );
    insert u;
    return u;
  }
}
