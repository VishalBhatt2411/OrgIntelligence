/**
 * Purpose: Verifies OI_OrgHealthFindingService's orchestration (sync = upsert + auto-resolve as
 *          one unit), DTO mapping, and status-validation guardrail (ADR-0027) — plus the
 *          Remediation Management workspace's queue/summary/export/history methods (ADR-0027
 *          lifecycle extension).
 */
@isTest
private class OI_OrgHealthFindingServiceTest {
  @isTest
  static void testSyncUpsertsCandidatesAndResolvesWhatDisappearedInOneCall() {
    OI_OrgHealthFindingService service = new OI_OrgHealthFindingService();
    service.sync(
      'MetadataHealth',
      new List<OI_OrgHealthFindingCandidate>{ buildCandidate('objA') },
      'run-1'
    );

    // objA is no longer detected in run-2 — sync must both leave nothing new and resolve objA.
    service.sync(
      'MetadataHealth',
      new List<OI_OrgHealthFindingCandidate>(),
      'run-2'
    );

    List<OI_OrgHealthFindingDTO> findings = service.getFindingsForSection(
      'MetadataHealth'
    );
    System.assertEquals(1, findings.size());
    System.assertEquals(
      'Resolved',
      findings[0].status,
      'A finding no longer produced by the scan must be auto-resolved by sync.'
    );
  }

  @isTest
  static void testGetFindingsForSectionMapsEveryFieldOntoTheDTO() {
    new OI_OrgHealthFindingService()
      .sync(
        'MetadataHealth',
        new List<OI_OrgHealthFindingCandidate>{ buildCandidate('objA') },
        'run-1'
      );

    OI_OrgHealthFindingDTO dto = new OI_OrgHealthFindingService()
      .getFindingsForSection('MetadataHealth')[0];

    System.assertEquals('MetadataHealth', dto.sectionKey);
    System.assertEquals('MetadataHealth.HighFieldCount', dto.ruleId);
    System.assertEquals(1, dto.ruleVersion);
    System.assertEquals('Critical', dto.severityKey);
    System.assertEquals('objA', dto.componentKey);
    System.assertEquals('Open', dto.status);
    System.assertNotEquals(null, dto.firstDetected);
    System.assertNotEquals(null, dto.lastDetected);
    System.assert(String.isNotBlank(dto.evidence));
    System.assert(String.isNotBlank(dto.remediation));
  }

  @isTest
  static void testUpdateStatusRejectsAnUnrecognizedStatus() {
    new OI_OrgHealthFindingService()
      .sync(
        'MetadataHealth',
        new List<OI_OrgHealthFindingCandidate>{ buildCandidate('objA') },
        'run-1'
      );
    Id findingId = new OI_OrgHealthFindingService()
        .getFindingsForSection('MetadataHealth')[0]
      .id;

    try {
      new OI_OrgHealthFindingService()
        .updateStatus(
          findingId,
          'Ignored Forever',
          null,
          null,
          null,
          null,
          null,
          null
        );
      System.assert(
        false,
        'An unrecognized status must be rejected before it ever reaches the Repository.'
      );
    } catch (OI_ServiceException e) {
      System.assert(e.getMessage().contains('Ignored Forever'));
    }
  }

  @isTest
  static void testUpdateStatusRequiresAFindingId() {
    try {
      new OI_OrgHealthFindingService()
        .updateStatus(null, 'Open', null, null, null, null, null, null);
      System.assert(false, 'A null finding Id must be rejected.');
    } catch (OI_ServiceException e) {
      System.assert(true);
    }
  }

  @isTest
  static void testUpdateStatusAcceptsAValidStatusAndPersistsIt() {
    new OI_OrgHealthFindingService()
      .sync(
        'MetadataHealth',
        new List<OI_OrgHealthFindingCandidate>{ buildCandidate('objA') },
        'run-1'
      );
    Id findingId = new OI_OrgHealthFindingService()
        .getFindingsForSection('MetadataHealth')[0]
      .id;

    new OI_OrgHealthFindingService()
      .updateStatus(
        findingId,
        'Acknowledged',
        'Reviewed by admin.',
        null,
        UserInfo.getUserId(),
        null,
        null,
        null
      );

    OI_OrgHealthFindingDTO updated = new OI_OrgHealthFindingService()
      .getFindingsForSection('MetadataHealth')[0];
    System.assertEquals('Acknowledged', updated.status);
    System.assertEquals('Reviewed by admin.', updated.notes);
    System.assertEquals(UserInfo.getUserId(), updated.ownerId);
  }

  @isTest
  static void testIsRiskAcceptanceExpiredIsTrueOnlyForAnExpiredAcceptedRisk() {
    new OI_OrgHealthFindingService()
      .sync(
        'MetadataHealth',
        new List<OI_OrgHealthFindingCandidate>{ buildCandidate('objA') },
        'run-1'
      );
    Id findingId = new OI_OrgHealthFindingService()
        .getFindingsForSection('MetadataHealth')[0]
      .id;

    new OI_OrgHealthFindingService()
      .updateStatus(
        findingId,
        'Risk Accepted',
        null,
        null,
        null,
        null,
        Date.today().addDays(-1),
        null
      );
    OI_OrgHealthFindingDTO expired = new OI_OrgHealthFindingService()
      .getFindingsForSection('MetadataHealth')[0];
    System.assertEquals(
      true,
      expired.isRiskAcceptanceExpired,
      'A Risk Accepted finding whose expiry date has passed must be flagged for re-review.'
    );

    new OI_OrgHealthFindingService()
      .updateStatus(findingId, 'Open', null, null, null, null, null, null);
    OI_OrgHealthFindingDTO reopened = new OI_OrgHealthFindingService()
      .getFindingsForSection('MetadataHealth')[0];
    System.assertEquals(
      false,
      reopened.isRiskAcceptanceExpired,
      'A finding no longer in Risk Accepted status must never report an expired acceptance, regardless of the stale expiry date still on file.'
    );
  }

  @isTest
  static void testGetRelatedFindingsReturnsOtherFindingsOnTheSameComponentOnly() {
    new OI_OrgHealthFindingService()
      .sync(
        'MetadataHealth',
        new List<OI_OrgHealthFindingCandidate>{
          buildCandidate('objA'),
          buildCandidateForRule('objA', 'MetadataHealth.HighDegree'),
          buildCandidate('objB')
        },
        'run-1'
      );
    OI_OrgHealthFindingDTO primary;
    for (
      OI_OrgHealthFindingDTO finding : new OI_OrgHealthFindingService()
        .getFindingsForSection('MetadataHealth')
    ) {
      if (
        finding.componentKey == 'objA' &&
        finding.ruleId == 'MetadataHealth.HighFieldCount'
      ) {
        primary = finding;
      }
    }

    List<OI_OrgHealthFindingDTO> related = new OI_OrgHealthFindingService()
      .getRelatedFindings('objA', primary.id);

    System.assertEquals(1, related.size());
    System.assertEquals('MetadataHealth.HighDegree', related[0].ruleId);
  }

  @isTest
  static void testGetRemediationQueueReturnsPagingMetadataAndAppliesTheFilter() {
    List<OI_OrgHealthFindingCandidate> candidates = new List<OI_OrgHealthFindingCandidate>();
    for (Integer i = 0; i < 3; i++) {
      candidates.add(buildCandidate('objQueue' + i));
    }
    new OI_OrgHealthFindingService()
      .sync('MetadataHealth', candidates, 'run-1');

    OI_RemediationFilterDTO filter = new OI_RemediationFilterDTO();
    filter.pageSize = 2;
    filter.pageNumber = 1;
    OI_RemediationQueryResultDTO result = new OI_OrgHealthFindingService()
      .getRemediationQueue(filter);

    System.assertEquals(3, result.totalCount);
    System.assertEquals(2, result.findings.size());
    System.assertEquals(1, result.pageNumber);
    System.assertEquals(2, result.pageSize);
    System.assertEquals(
      2,
      result.totalPages,
      '3 rows at 2 per page must report 2 total pages.'
    );
  }

  @isTest
  static void testGetRemediationSummaryAggregatesAcrossSectionsWithFriendlySectionLabels() {
    OI_OrgHealthFindingCandidate securityCandidate = buildCandidate(
      'objSecuritySvc'
    );
    securityCandidate.sectionKey = 'SecurityHealth';
    new OI_OrgHealthFindingService()
      .sync(
        'MetadataHealth',
        new List<OI_OrgHealthFindingCandidate>{ buildCandidate('objMetaSvc') },
        'run-1'
      );
    new OI_OrgHealthFindingService()
      .sync(
        'SecurityHealth',
        new List<OI_OrgHealthFindingCandidate>{ securityCandidate },
        'run-1'
      );

    OI_RemediationSummaryDTO summary = new OI_OrgHealthFindingService()
      .getRemediationSummary();

    System.assertEquals(2, summary.totalOpenFindings);
    Map<String, String> sectionCountByLabel = new Map<String, String>();
    for (OI_HealthKeyValueDTO row : summary.countBySection) {
      sectionCountByLabel.put(row.label, row.value);
    }
    System.assertEquals(
      true,
      sectionCountByLabel.containsKey('Metadata Health'),
      'countBySection must use the CMDT-configured display label, not the raw Section_Key__c.'
    );
    System.assertEquals(
      true,
      sectionCountByLabel.containsKey('Security Health')
    );
  }

  @isTest
  static void testExportRemediationQueueReturnsEveryMatchingRowNotJustOnePage() {
    List<OI_OrgHealthFindingCandidate> candidates = new List<OI_OrgHealthFindingCandidate>();
    for (Integer i = 0; i < 4; i++) {
      candidates.add(buildCandidate('objExportSvc' + i));
    }
    new OI_OrgHealthFindingService()
      .sync('MetadataHealth', candidates, 'run-1');

    OI_RemediationFilterDTO filter = new OI_RemediationFilterDTO();
    filter.pageSize = 1;
    List<OI_OrgHealthFindingDTO> exported = new OI_OrgHealthFindingService()
      .exportRemediationQueue(filter);

    System.assertEquals(
      4,
      exported.size(),
      'Export must ignore the filter\'s own interactive pageSize and return every matching row.'
    );
  }

  @isTest
  static void testGetFindingHistoryReturnsHumanReadableFieldLabelsForTrackedChanges() {
    new OI_OrgHealthFindingService()
      .sync(
        'MetadataHealth',
        new List<OI_OrgHealthFindingCandidate>{ buildCandidate('objHistory') },
        'run-1'
      );
    Id findingId = new OI_OrgHealthFindingService()
        .getFindingsForSection('MetadataHealth')[0]
      .id;

    new OI_OrgHealthFindingService()
      .updateStatus(
        findingId,
        'Acknowledged',
        null,
        null,
        null,
        null,
        null,
        null
      );

    List<OI_FindingHistoryDTO> history = new OI_OrgHealthFindingService()
      .getFindingHistory(findingId);

    System.assert(
      !history.isEmpty(),
      'Status__c has trackHistory=true — an explicit status change must produce at least one history row.'
    );
    Boolean foundStatusChange = false;
    for (OI_FindingHistoryDTO entry : history) {
      if (entry.fieldLabel == 'Status') {
        foundStatusChange = true;
        System.assertEquals('Acknowledged', entry.newValue);
      }
    }
    System.assert(
      foundStatusChange,
      'The Status field label must be resolved via Schema describe (human-readable "Status"), never the raw API name "Status__c".'
    );
  }

  @isTest
  static void testGetFindingHistoryForAFindingWithNoChangesReturnsAnEmptyListNotAnError() {
    new OI_OrgHealthFindingService()
      .sync(
        'MetadataHealth',
        new List<OI_OrgHealthFindingCandidate>{
          buildCandidate('objNoHistory')
        },
        'run-1'
      );
    Id findingId = new OI_OrgHealthFindingService()
        .getFindingsForSection('MetadataHealth')[0]
      .id;

    List<OI_FindingHistoryDTO> history = new OI_OrgHealthFindingService()
      .getFindingHistory(findingId);

    System.assertEquals(
      0,
      history.size(),
      'A freshly-inserted finding with no lifecycle edits yet must return an honest empty history, not an error.'
    );
  }

  private static OI_OrgHealthFindingCandidate buildCandidateForRule(
    String componentKey,
    String ruleId
  ) {
    OI_OrgHealthFindingCandidate candidate = buildCandidate(componentKey);
    candidate.ruleId = ruleId;
    return candidate;
  }

  private static OI_OrgHealthFindingCandidate buildCandidate(
    String componentKey
  ) {
    OI_OrgHealthFindingCandidate candidate = new OI_OrgHealthFindingCandidate();
    candidate.sectionKey = 'MetadataHealth';
    candidate.ruleId = 'MetadataHealth.HighFieldCount';
    candidate.ruleVersion = 1;
    candidate.title = 'Test finding for ' + componentKey;
    candidate.severityKey = 'Critical';
    candidate.confidence = 'Medium';
    candidate.componentKey = componentKey;
    candidate.componentType = 'Custom';
    candidate.componentLabel = componentKey;
    candidate.isManaged = false;
    candidate.evidence = 'Evidence for ' + componentKey;
    candidate.measuredValue = '500 fields';
    candidate.expectedValue = '< 60 fields';
    candidate.explanation = 'Explanation text.';
    candidate.orgRisk = 'Org risk text.';
    candidate.potentialImpact = 'Impact text.';
    candidate.remediation = 'Remediation text.';
    candidate.validationSteps = 'Validation text.';
    return candidate;
  }
}
