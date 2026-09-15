/**
 * Purpose: Verifies OI_DataHealthService's weighted-penalty score formula, coverage/severity
 *          shaping, and read path in isolation — the formula/shaping logic is pure and
 *          DML-free (hand-built ObjectSignal fixtures), so it is tested deterministically
 *          without depending on OI_DataHealthComputeBatchable's real record sampling (that
 *          end-to-end path is covered separately by OI_DataHealthComputeBatchableTest).
 */
@isTest
private class OI_DataHealthServiceTest {
  @isTest
  static void testBuildSnapshotFromSignalsComputesWeightedPenaltyScoreAndRanksWorstFirst() {
    List<OI_DataHealthService.ObjectSignal> signals = new List<OI_DataHealthService.ObjectSignal>{
      new OI_DataHealthService.ObjectSignal(
        'Account',
        100,
        100,
        20,
        5,
        0,
        false
      ),
      new OI_DataHealthService.ObjectSignal('Contact', 50, 50, 0, 0, 10, false)
    };

    OI_DataHealthDTO dto = new OI_DataHealthService()
      .buildSnapshotFromSignals(signals, new List<String>(), false);

    System.assertEquals(
      92,
      dto.score,
      'Score = 100 - [(20/150*35) + (5/150*35) + (10/150*30)], rounded HALF_UP.'
    );
    System.assertEquals(5, dto.kpiTiles.size());
    System.assertEquals(
      3,
      dto.formulaComponents.size(),
      'Any score must expose its formula — all three weighted components.'
    );
    System.assertEquals(true, dto.isCoverageComplete);
    System.assertEquals(2, dto.breakdownRows.size());
    System.assertEquals(
      'Contact',
      dto.breakdownRows[0].key,
      'Contact is Critical (20% duplicate rate vs. a 5% threshold) and must rank before Account (Warning).'
    );
    System.assertEquals('Account', dto.breakdownRows[1].key);
    System.assertEquals(2, dto.heatmapRows.size());
    for (OI_HealthHeatmapRowDTO row : dto.heatmapRows) {
      System.assertEquals(
        3,
        row.cells.size(),
        'Stale, incomplete, and duplicate cells must always be present.'
      );
    }
  }

  @isTest
  static void testBuildSnapshotFromSignalsWithNoSampledRecordsReturnsNullScoreNotZero() {
    OI_DataHealthDTO dto = new OI_DataHealthService()
      .buildSnapshotFromSignals(
        new List<OI_DataHealthService.ObjectSignal>(),
        new List<String>(),
        false
      );

    System.assertEquals(
      null,
      dto.score,
      'Zero sampled records must never fabricate a zero (worst-possible) score.'
    );
    System.assertEquals(null, dto.severityKey);
    System.assert(
      dto.coverageNote.startsWith('0 objects'),
      'An honest zero-object coverage note, not a blank/misleading one.'
    );
    System.assertEquals(
      true,
      dto.isCoverageComplete,
      'No skipped objects and no truncation means coverage is complete, even with zero objects in scope.'
    );
  }

  @isTest
  static void testBuildSnapshotFromSignalsRecordsSkippedObjectsAndTruncationInCoverageNote() {
    List<OI_DataHealthService.ObjectSignal> signals = new List<OI_DataHealthService.ObjectSignal>{
      new OI_DataHealthService.ObjectSignal('Account', 500, 200, 0, 0, 0, true)
    };
    List<String> skipped = new List<String>{ 'Foo__c (not found in this org)' };

    OI_DataHealthDTO dto = new OI_DataHealthService()
      .buildSnapshotFromSignals(signals, skipped, true);

    System.assertEquals(
      false,
      dto.isCoverageComplete,
      'A truncated object or a skipped object both mean coverage is not complete.'
    );
    System.assert(
      dto.coverageNote.contains('sample ceiling'),
      'Truncation must be named in the coverage note, not hidden.'
    );
    System.assert(
      dto.coverageNote.contains('Skipped: Foo__c (not found in this org)'),
      'The skipped object and its reason must be named in the coverage note.'
    );
  }

  @isTest
  static void testApplySeverityRateSignalCalibrationMatchesEstablishedSeverityBoundaries() {
    OI_DataHealthService.ObjectSignal warningSignal = new OI_DataHealthService.ObjectSignal(
      'Account',
      100,
      100,
      20,
      5,
      0,
      false
    );
    OI_DataHealthService.ObjectSignal criticalSignal = new OI_DataHealthService.ObjectSignal(
      'Contact',
      50,
      50,
      0,
      0,
      10,
      false
    );
    OI_DataHealthService service = new OI_DataHealthService();

    service.buildSnapshotFromSignals(
      new List<OI_DataHealthService.ObjectSignal>{
        warningSignal,
        criticalSignal
      },
      new List<String>(),
      false
    );

    System.assertEquals(
      'Warning',
      warningSignal.severityKey,
      'A 20% stale rate against a 15% threshold (1.33x magnitude) must stay Warning under the RATE_SIGNAL_CONFIDENCE=0.7 calibration (badness ~56 -> healthEquivalent ~44).'
    );
    System.assertEquals(
      'Critical',
      criticalSignal.severityKey,
      'A 20% duplicate rate against a 5% threshold (4x magnitude, saturated at the engine\'s 1.5x cap) must reach Critical (badness ~63 -> healthEquivalent ~37).'
    );
  }

  @isTest
  static void testGetFindingCandidatesReturnsCandidatesOnlyForBreachedRules() {
    List<OI_DataHealthService.ObjectSignal> signals = new List<OI_DataHealthService.ObjectSignal>{
      new OI_DataHealthService.ObjectSignal(
        'Account',
        100,
        100,
        20,
        5,
        0,
        false
      ),
      new OI_DataHealthService.ObjectSignal('Contact', 50, 50, 0, 0, 10, false)
    };

    List<OI_OrgHealthFindingCandidate> candidates = new OI_DataHealthService()
      .getFindingCandidates(signals);

    System.assertEquals(
      2,
      candidates.size(),
      'Only Account.StaleRecords (Warning) and Contact.Duplicates (Critical) breach a rule — every Good-scored metric must not produce a candidate.'
    );
    Map<String, OI_OrgHealthFindingCandidate> byComponentAndRule = new Map<String, OI_OrgHealthFindingCandidate>();
    for (OI_OrgHealthFindingCandidate candidate : candidates) {
      byComponentAndRule.put(
        candidate.componentKey + ':' + candidate.ruleId,
        candidate
      );
    }
    System.assert(
      byComponentAndRule.containsKey('Account:DataHealth.StaleRecords')
    );
    System.assert(
      byComponentAndRule.containsKey('Contact:DataHealth.Duplicates')
    );

    OI_OrgHealthFindingCandidate accountStale = byComponentAndRule.get(
      'Account:DataHealth.StaleRecords'
    );
    System.assertEquals('DataHealth', accountStale.sectionKey);
    System.assertEquals('Warning', accountStale.severityKey);
    System.assertEquals('Object', accountStale.componentType);
    System.assertEquals('Account', accountStale.componentLabel);
    System.assertEquals(false, accountStale.isManaged);
    System.assertNotEquals(null, accountStale.score);
    System.assert(String.isNotBlank(accountStale.scoreExplanation));
    System.assert(String.isNotBlank(accountStale.scoreContributorsJson));
    System.assert(String.isNotBlank(accountStale.evidence));
    System.assert(String.isNotBlank(accountStale.remediation));
    System.assert(String.isNotBlank(accountStale.validationSteps));

    OI_OrgHealthFindingCandidate contactDuplicates = byComponentAndRule.get(
      'Contact:DataHealth.Duplicates'
    );
    System.assertEquals('Critical', contactDuplicates.severityKey);
    System.assertEquals(
      'Low',
      contactDuplicates.confidence,
      'Exact-match Email/Phone duplicates are a review-first heuristic, not confirmed evidence — Low confidence.'
    );
    System.assert(
      contactDuplicates.explanation.contains('not native Duplicate Rule'),
      'Must honestly disclose this is not native Duplicate/Matching Rule evidence.'
    );
  }

  @isTest
  static void testGetFindingCandidatesWithAllGoodSignalsReturnsNoCandidates() {
    List<OI_DataHealthService.ObjectSignal> signals = new List<OI_DataHealthService.ObjectSignal>{
      new OI_DataHealthService.ObjectSignal(
        'Opportunity',
        100,
        100,
        0,
        0,
        0,
        false
      )
    };

    List<OI_OrgHealthFindingCandidate> candidates = new OI_DataHealthService()
      .getFindingCandidates(signals);

    System.assertEquals(
      0,
      candidates.size(),
      'A fully clean object must never produce a finding candidate.'
    );
  }

  @isTest
  static void testResolveRunStatusReturnsNotYetRunWhenNoAsyncJobExistsForThisBatchable() {
    String status = new OI_DataHealthService().resolveRunStatus();
    System.assertEquals(
      'NotYetRun',
      status,
      'No AsyncApexJob row for OI_DataHealthComputeBatchable exists in a fresh test context.'
    );
  }

  @isTest
  static void testGetDataHealthDetailReturnsHonestNotYetComputedStateWhenNoSnapshotExists() {
    OI_DataHealthDTO dto = new OI_DataHealthService().getDataHealthDetail();

    System.assertEquals('NotYetRun', dto.runStatus);
    System.assertEquals(null, dto.score);
    System.assertEquals(false, dto.isCoverageComplete);
    System.assertEquals(
      'Data Health has not been computed yet. Run a scan to see results.',
      dto.coverageNote
    );
  }

  @isTest
  static void testPersistSnapshotThenGetDataHealthDetailReturnsTheStoredResult() {
    List<OI_DataHealthService.ObjectSignal> signals = new List<OI_DataHealthService.ObjectSignal>{
      new OI_DataHealthService.ObjectSignal('Account', 10, 10, 1, 0, 0, false)
    };
    OI_DataHealthService service = new OI_DataHealthService();
    OI_DataHealthDTO built = service.buildSnapshotFromSignals(
      signals,
      new List<String>(),
      false
    );
    service.persistSnapshot(
      built,
      'test-run-id-0001',
      10,
      false,
      UserInfo.getUserId()
    );

    OI_DataHealthDTO dto = service.getDataHealthDetail();

    System.assertEquals(
      built.score,
      dto.score,
      'The read path must return the persisted snapshot, not recompute anything.'
    );
    System.assertEquals(built.coverageNote, dto.coverageNote);
    System.assertEquals(
      'NotYetRun',
      dto.runStatus,
      'A manually persisted snapshot does not create a real AsyncApexJob row — run status stays independently accurate.'
    );
  }
}
