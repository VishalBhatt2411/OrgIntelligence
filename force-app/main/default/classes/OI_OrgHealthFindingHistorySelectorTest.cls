@IsTest
private class OI_OrgHealthFindingHistorySelectorTest {
  @IsTest
  static void testSelectByFindingIdWithNullIdReturnsEmptyListWithoutQuerying() {
    List<OI_FindingHistoryRowDTO> rows = new OI_OrgHealthFindingHistorySelector()
      .selectByFindingId(null);
    System.assertEquals(0, rows.size());
  }

  @IsTest
  static void testSelectByFindingIdForARealFindingExercisesTheRealQueryPath() {
    OI_OrgHealthFindingCandidate candidate = new OI_OrgHealthFindingCandidate();
    candidate.sectionKey = 'MetadataHealth';
    candidate.ruleId = 'MetadataHealth.HighFieldCount';
    candidate.ruleVersion = 1;
    candidate.title = 'Selector coverage finding';
    candidate.severityKey = 'Critical';
    candidate.confidence = 'Medium';
    candidate.componentKey = 'objSelectorCoverageTest';
    candidate.componentType = 'Custom';
    candidate.componentLabel = 'objSelectorCoverageTest';
    candidate.isManaged = false;
    candidate.evidence = 'Evidence.';
    candidate.measuredValue = '500 fields';
    candidate.expectedValue = '< 60 fields';
    candidate.explanation = 'Explanation.';
    candidate.orgRisk = 'Risk.';
    candidate.potentialImpact = 'Impact.';
    candidate.remediation = 'Remediation.';
    candidate.validationSteps = 'Validation.';

    new OI_OrgHealthFindingService()
      .sync(
        'MetadataHealth',
        new List<OI_OrgHealthFindingCandidate>{ candidate },
        'run-selector-coverage-1'
      );
    Id findingId = new OI_OrgHealthFindingService()
        .getFindingsForSection('MetadataHealth')[0]
      .id;

    /** Field History Tracking is not reliably queryable within the same transaction as the write that produced it (confirmed by live-org reproduction — see OI_OrgHealthFindingServiceTest), so this only exercises the selector's real query path/shape, not a specific row count. */
    List<OI_FindingHistoryRowDTO> rows = new OI_OrgHealthFindingHistorySelector()
      .selectByFindingId(findingId);
    System.assert(
      rows != null,
      'The real query path must return a (possibly empty) list, never null.'
    );
  }
}
