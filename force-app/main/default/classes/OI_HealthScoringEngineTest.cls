@IsTest
private class OI_HealthScoringEngineTest {
  @IsTest
  static void testNoSignalsResolvesToGoodWithZeroScore() {
    OI_HealthScoreResult result = new OI_HealthScoringEngine()
      .score(new List<OI_HealthSignal>());
    System.assertEquals(
      0,
      result.score,
      'No signals detected must never fabricate badness.'
    );
    System.assertEquals('Good', result.severityKey);
  }

  @IsTest
  static void testSingleLowMagnitudeSignalStaysGood() {
    OI_HealthSignal signal = new OI_HealthSignal(
      'Magnitude',
      'Field count',
      35,
      0.4,
      '40 of 60 fields'
    );
    OI_HealthScoreResult result = new OI_HealthScoringEngine()
      .score(new List<OI_HealthSignal>{ signal });
    System.assertEquals(
      'Good',
      result.severityKey,
      'A signal well under its threshold must not raise severity.'
    );
  }

  @IsTest
  static void testFullyConfirmedHighImpactHighExposureSignalReachesCritical() {
    OI_HealthSignal signal = new OI_HealthSignal(
      'Magnitude',
      'Sensitive object grant',
      90,
      1.5,
      'Fully saturated'
    );
    signal.confidence = 1.0;
    signal.impactMultiplier = 1.0;
    signal.exposureMultiplier = 1.0;
    OI_HealthScoreResult result = new OI_HealthScoringEngine()
      .score(new List<OI_HealthSignal>{ signal });
    System.assertEquals('Critical', result.severityKey);
    System.assertEquals(90, result.score);
  }

  @IsTest
  static void testLowConfidenceAloneCannotReachCriticalEvenAtFullMagnitude() {
    OI_HealthSignal signal = new OI_HealthSignal(
      'Magnitude',
      'No incoming references',
      90,
      1.5,
      'Zero incoming edges detected'
    );
    signal.confidence = 0.3;
    OI_HealthScoreResult result = new OI_HealthScoringEngine()
      .score(new List<OI_HealthSignal>{ signal });
    System.assertNotEquals(
      'Critical',
      result.severityKey,
      'Low confidence must dampen a single raw signal below Critical.'
    );
  }

  @IsTest
  static void testManagedPackageImpactDampenerReducesContributionVsUnmanagedCustom() {
    OI_HealthSignal unmanaged = new OI_HealthSignal(
      'Magnitude',
      'Field count',
      35,
      1.5,
      'Unmanaged'
    );
    unmanaged.impactMultiplier = 1.0;
    OI_HealthSignal managed = new OI_HealthSignal(
      'Magnitude',
      'Field count',
      35,
      1.5,
      'Managed'
    );
    managed.impactMultiplier = 0.4;

    OI_HealthScoreResult unmanagedResult = new OI_HealthScoringEngine()
      .score(new List<OI_HealthSignal>{ unmanaged });
    OI_HealthScoreResult managedResult = new OI_HealthScoringEngine()
      .score(new List<OI_HealthSignal>{ managed });

    System.assert(
      managedResult.score < unmanagedResult.score,
      'A managed-package finding must score lower badness than an identical unmanaged-custom one.'
    );
  }

  @IsTest
  static void testCompensatingControlHalvesContribution() {
    OI_HealthSignal withoutControl = new OI_HealthSignal(
      'Magnitude',
      'Broad grant',
      60,
      1.5,
      'No control'
    );
    OI_HealthSignal withControl = new OI_HealthSignal(
      'Magnitude',
      'Broad grant',
      60,
      1.5,
      'Reviewed quarterly'
    );
    withControl.hasCompensatingControl = true;

    OI_HealthScoreResult withoutResult = new OI_HealthScoringEngine()
      .score(new List<OI_HealthSignal>{ withoutControl });
    OI_HealthScoreResult withResult = new OI_HealthScoringEngine()
      .score(new List<OI_HealthSignal>{ withControl });

    System.assertEquals(
      (withoutResult.score / 2).setScale(1),
      withResult.score.setScale(1),
      'A compensating control must exactly halve that signal contribution.'
    );
    System.assertEquals(
      true,
      withResult.contributors[0].hasCompensatingControl
    );
  }

  @IsTest
  static void testCorrelatedSignalsCombineByMaxNotSum() {
    OI_HealthSignal signalA = new OI_HealthSignal(
      'FanOut',
      'Fan-out',
      55,
      1.5,
      'High fan-out'
    );
    signalA.correlationGroup = 'DependencyDegree';
    OI_HealthSignal signalB = new OI_HealthSignal(
      'FanIn',
      'Fan-in',
      55,
      1.5,
      'High fan-in'
    );
    signalB.correlationGroup = 'DependencyDegree';

    OI_HealthScoreResult result = new OI_HealthScoringEngine()
      .score(new List<OI_HealthSignal>{ signalA, signalB });

    System.assertEquals(
      55,
      result.score,
      'Two correlated signals of equal weight must combine by their max, never their sum.'
    );
    Integer correlatedOutCount = 0;
    for (OI_HealthScoreContributor contributor : result.contributors) {
      if (contributor.wasCorrelatedOut) {
        correlatedOutCount++;
      }
    }
    System.assertEquals(
      1,
      correlatedOutCount,
      'Exactly one of two equally-correlated signals must be marked correlated-out.'
    );
  }

  @IsTest
  static void testIndependentSignalsSumRatherThanCombineByMax() {
    OI_HealthSignal signalA = new OI_HealthSignal(
      'HighFieldCount',
      'Field count',
      40,
      1.5,
      'High field count'
    );
    OI_HealthSignal signalB = new OI_HealthSignal(
      'HighDegree',
      'Degree',
      40,
      1.5,
      'High degree'
    );
    OI_HealthScoreResult result = new OI_HealthScoringEngine()
      .score(new List<OI_HealthSignal>{ signalA, signalB });
    System.assertEquals(
      80,
      result.score,
      'Two independent (ungrouped) signals must sum, not combine by max.'
    );
  }

  @IsTest
  static void testScoreNeverExceedsOneHundredEvenWhenSignalsOversaturate() {
    OI_HealthSignal signalA = new OI_HealthSignal(
      'A',
      'A',
      90,
      2.0,
      'Over-saturated'
    );
    OI_HealthSignal signalB = new OI_HealthSignal(
      'B',
      'B',
      90,
      2.0,
      'Over-saturated'
    );
    OI_HealthScoreResult result = new OI_HealthScoringEngine()
      .score(new List<OI_HealthSignal>{ signalA, signalB });
    System.assertEquals(100, result.score);
    System.assertEquals('Critical', result.severityKey);
  }

  @IsTest
  static void testExplanationNamesTopContributor() {
    OI_HealthSignal dominant = new OI_HealthSignal(
      'Dominant',
      'Sensitive exposure',
      90,
      1.5,
      'Dominant signal'
    );
    OI_HealthSignal minor = new OI_HealthSignal(
      'Minor',
      'Minor factor',
      5,
      1.5,
      'Minor signal'
    );
    OI_HealthScoreResult result = new OI_HealthScoringEngine()
      .score(new List<OI_HealthSignal>{ dominant, minor });
    System.assert(
      result.explanation.contains('Sensitive exposure'),
      'Explanation must name the dominant contributor: ' + result.explanation
    );
  }
}
