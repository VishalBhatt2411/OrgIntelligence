/**
 * Purpose: Verifies OI_SecurityHealthService's severity formula in isolation (deterministic,
 *          no DML) and its end-to-end shape/evidence against real PermissionSet data — facts-
 *          only (§0.3), no composite score. PermissionSet, unlike OI_Graph_Node__c, is visible
 *          to tests without SeeAllData=true (it is org setup metadata), so the org's own
 *          pre-existing Permission Sets and Profile shadow rows are always mixed into these
 *          results — the same constraint OI_CodeHealthServiceTest documents for ApexClass.
 */
@IsTest
private class OI_SecurityHealthServiceTest {
  /**
   * Deliberately constructs the PermissionSet in memory and never inserts it: several of the
   * curated elevated-permission fields (Modify All Data especially) carry large
   * FIELD_INTEGRITY_EXCEPTION dependency chains on real DML in an org with sample data
   * (Sales/Service Cloud features enabled), so exercising the counting logic itself must stay
   * DML-free to remain deterministic.
   */
  @IsTest
  static void testCountElevatedPermissionsCountsOnlyTheCuratedSevenFlags() {
    System.assertEquals(
      0,
      OI_SecurityHealthService.countElevatedPermissions(new PermissionSet())
    );
    System.assertEquals(
      1,
      OI_SecurityHealthService.countElevatedPermissions(
        new PermissionSet(PermissionsManageUsers = true)
      )
    );
    System.assertEquals(
      7,
      OI_SecurityHealthService.countElevatedPermissions(
        new PermissionSet(
          PermissionsModifyAllData = true,
          PermissionsViewAllData = true,
          PermissionsAuthorApex = true,
          PermissionsManageUsers = true,
          PermissionsCustomizeApplication = true,
          PermissionsManageSharing = true,
          PermissionsResetPasswords = true
        )
      ),
      'All seven curated flags must each count once.'
    );
  }

  @IsTest
  static void testGetSecurityHealthDetailReturnsWellFormedResultAgainstRealPermissionSets() {
    OI_SecurityHealthDTO result = new OI_SecurityHealthService()
      .getSecurityHealthDetail();

    System.assertEquals(5, result.kpiTiles.size());
    System.assert(String.isNotBlank(result.coverageNote));
    System.assertNotEquals(null, result.computedAt);
    System.assert(
      result.breakdownRows.size() <= 8,
      'The breakdown table must stay capped at its top-N limit.'
    );
    System.assert(
      result.heatmapRows.size() <= 5,
      'The heatmap must stay capped at its top-N limit.'
    );

    Set<String> validSeverities = new Set<String>{
      'Good',
      'Warning',
      'Critical'
    };
    for (OI_HealthBreakdownRowDTO row : result.breakdownRows) {
      System.assertEquals(
        2,
        row.metricValues.size(),
        'Every breakdown row must carry exactly the two configured metric columns.'
      );
      System.assert(
        validSeverities.contains(row.severityKey),
        'Every row severity must be a recognized band.'
      );
    }
    for (OI_HealthHeatmapRowDTO row : result.heatmapRows) {
      System.assertEquals(
        3,
        row.cells.size(),
        'Every heatmap row must carry exactly the three configured columns.'
      );
      for (OI_HealthMetricValueDTO cell : row.cells) {
        System.assert(
          validSeverities.contains(cell.severityKey),
          'Every heatmap cell severity must be a recognized band.'
        );
      }
    }
  }

  @IsTest
  static void testGetSecurityHealthDetailDetectsSensitiveBroadGrantFromInsertedFixture() {
    PermissionSet sensitiveGrant = new PermissionSet(
      Name = 'OI_Test_Sensitive_Grant',
      Label = 'OI Test Sensitive Grant'
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

    OI_SecurityHealthDTO result = new OI_SecurityHealthService()
      .getSecurityHealthDetail();

    Map<String, String> kpiByLabel = new Map<String, String>();
    for (OI_HealthKeyValueDTO tile : result.kpiTiles) {
      kpiByLabel.put(tile.label, tile.value);
    }
    System.assert(
      Integer.valueOf(kpiByLabel.get('Permission sets with broad grants')) >= 1,
      'The inserted fixture grants Modify All Records on Contact, so this floor must hold.'
    );
    System.assert(
      Integer.valueOf(kpiByLabel.get('Sensitive object grants')) >= 1,
      'Contact is a configured sensitive object, so this floor must hold.'
    );
  }

  @IsTest
  static void testGetSecurityHealthDetailCountsAnUnassignedCustomPermissionSetButNotAProfileShadowRow() {
    PermissionSet unassigned = new PermissionSet(
      Name = 'OI_Test_Unassigned',
      Label = 'OI Test Unassigned'
    );
    insert unassigned;

    OI_SecurityHealthDTO result = new OI_SecurityHealthService()
      .getSecurityHealthDetail();

    Map<String, String> kpiByLabel = new Map<String, String>();
    for (OI_HealthKeyValueDTO tile : result.kpiTiles) {
      kpiByLabel.put(tile.label, tile.value);
    }
    System.assert(
      Integer.valueOf(kpiByLabel.get('Unassigned custom permission sets')) >= 1,
      'The freshly inserted, unassigned custom Permission Set must count toward this floor.'
    );
  }

  /**
   * Replaces the old computeSeverityKey static-helper tests now that severity comes from
   * OI_HealthScoringEngine (ADR-0027 correction) — verifies the SAME product guarantee
   * (ProductSpecs.md's "never mark Critical based only on the number of grants") end to end
   * through the real service and the unified finding model, not a bare static call.
   */
  @IsTest
  static void testSensitiveGrantWithNoAssigneesIsWarningNotCriticalEndToEnd() {
    PermissionSet sensitiveGrant = new PermissionSet(
      Name = 'OI_Test_Sensitive_Unassigned',
      Label = 'OI Test Sensitive Unassigned'
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

    List<OI_OrgHealthFindingCandidate> candidates = new OI_SecurityHealthService()
      .getFindingCandidates();

    OI_OrgHealthFindingCandidate sensitiveCandidate;
    for (OI_OrgHealthFindingCandidate candidate : candidates) {
      if (
        candidate.componentKey == sensitiveGrant.Id &&
        candidate.ruleId == 'SecurityHealth.SensitiveObjectGrant'
      ) {
        sensitiveCandidate = candidate;
      }
    }
    System.assertNotEquals(
      null,
      sensitiveCandidate,
      'A sensitive-object broad grant must always produce a SensitiveObjectGrant candidate, even with zero assignees.'
    );
    System.assertEquals(
      'Warning',
      sensitiveCandidate.severityKey,
      'A sensitive-object grant with zero active assignees is a configuration-hygiene finding, not a proven active risk — it must never reach Critical from the grant alone.'
    );
  }

  @IsTest
  static void testSensitiveGrantWithActiveAssigneeIsCriticalEndToEnd() {
    PermissionSet sensitiveGrant = new PermissionSet(
      Name = 'OI_Test_Sensitive_Assigned',
      Label = 'OI Test Sensitive Assigned'
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

    List<OI_OrgHealthFindingCandidate> candidates = new OI_SecurityHealthService()
      .getFindingCandidates();

    OI_OrgHealthFindingCandidate sensitiveCandidate;
    for (OI_OrgHealthFindingCandidate candidate : candidates) {
      if (
        candidate.componentKey == sensitiveGrant.Id &&
        candidate.ruleId == 'SecurityHealth.SensitiveObjectGrant'
      ) {
        sensitiveCandidate = candidate;
      }
    }
    System.assertNotEquals(
      null,
      sensitiveCandidate,
      'A sensitive-object broad grant must produce a SensitiveObjectGrant candidate.'
    );
    System.assertEquals(
      'Critical',
      sensitiveCandidate.severityKey,
      'A sensitive-object grant actually held by an active user is a real, corroborated exposure and must rank Critical.'
    );
    System.assertEquals('High', sensitiveCandidate.confidence);
    System.assert(
      String.isNotBlank(sensitiveCandidate.scoreContributorsJson),
      'The candidate must carry its full contributor breakdown for the drawer.'
    );
  }

  @IsTest
  static void testGetFindingCandidatesReturnsWellFormedCandidatesForEveryBreachedRule() {
    List<OI_OrgHealthFindingCandidate> candidates = new OI_SecurityHealthService()
      .getFindingCandidates();

    Set<String> validSeverities = new Set<String>{ 'Warning', 'Critical' };
    Set<String> validRuleIds = new Set<String>{
      'SecurityHealth.ElevatedPermissions',
      'SecurityHealth.BroadObjectGrant',
      'SecurityHealth.SensitiveObjectGrant'
    };
    for (OI_OrgHealthFindingCandidate candidate : candidates) {
      System.assertEquals('SecurityHealth', candidate.sectionKey);
      System.assert(
        validRuleIds.contains(candidate.ruleId),
        'Every candidate must carry one of the three recognized Security Health rule ids.'
      );
      System.assert(
        validSeverities.contains(candidate.severityKey),
        'A candidate is only ever produced for a breached (non-Good) rule.'
      );
      System.assert(
        String.isNotBlank(candidate.componentKey),
        'Every candidate must resolve to a real Permission Set/Profile Id.'
      );
      System.assert(
        String.isNotBlank(candidate.evidence),
        'Every candidate must carry real evidence, never a blank justification.'
      );
      System.assert(
        String.isNotBlank(candidate.scoreContributorsJson),
        'Every candidate must carry its full contributor breakdown for the drawer.'
      );
    }
  }
}
