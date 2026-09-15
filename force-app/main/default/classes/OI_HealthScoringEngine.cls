/**
 * Purpose: The one place Org Health turns a rule's raw evidence into a defensible severity —
 *          replacing the "a single count crossed a threshold, therefore Critical" pattern every
 *          domain Health Service previously used. Shared by every section (Metadata Health is
 *          the first consumer; Automation/Code/Security Health adopt it as each is touched)
 *          rather than each section re-inventing its own weighting math.
 * Responsibilities: Combine a list of OI_HealthSignal into one OI_HealthScoreResult — a 0–100
 *                    badness score, the severity key that score resolves to via the exact same
 *                    band registry (OI_HealthSeverityService) every other Org Health score uses,
 *                    a human explanation, and the full contributor breakdown the finding drawer
 *                    renders. Signals sharing a correlationGroup are combined by their strongest
 *                    member, never summed, so two views of the same underlying evidence cannot
 *                    double-count.
 * Dependencies: OI_HealthSignal, OI_HealthScoreContributor, OI_HealthScoreResult,
 *               OI_HealthSeverityService.
 * Limitations: Deterministic and stateless — no randomness, no org-state reads beyond what the
 *              caller already resolved into signal magnitudes. A Low-confidence signal can still
 *              contribute if it is the only evidence available; it simply contributes less
 *              (confidence is a multiplier, not a hard gate) — reported honestly in the
 *              contributor breakdown rather than silently dropped, so an administrator can still
 *              see it and decide the finding needs corroboration.
 */
public with sharing class OI_HealthScoringEngine {
  /** Magnitude ratio (value / threshold) at which a signal saturates its full configured weight — mirrors every domain Service's existing "1.3x threshold = Critical" convention, generalized to 1.5x since this engine also folds in confidence/impact/exposure, not magnitude alone. */
  @TestVisible
  private static final Decimal MAGNITUDE_SATURATION_CAP = 1.5;
  /** A recorded compensating control halves a signal's contribution — mitigated, not erased; the underlying evidence still shows in the drawer. */
  @TestVisible
  private static final Decimal COMPENSATING_CONTROL_DAMPENER = 0.5;
  private static final Integer EXPLANATION_TOP_N = 2;

  private final OI_HealthSeverityService severityService;

  public OI_HealthScoringEngine() {
    this(new OI_HealthSeverityService());
  }

  public OI_HealthScoringEngine(OI_HealthSeverityService severityService) {
    this.severityService = severityService;
  }

  public OI_HealthScoreResult score(List<OI_HealthSignal> signals) {
    OI_HealthScoreResult result = new OI_HealthScoreResult();
    if (signals == null || signals.isEmpty()) {
      result.score = 0;
      result.severityKey = severityService.resolveSeverityKey(100);
      result.explanation = 'No signals evaluated — nothing detected.';
      return result;
    }

    List<OI_HealthScoreContributor> contributors = new List<OI_HealthScoreContributor>();
    Map<String, OI_HealthScoreContributor> bestByGroup = new Map<String, OI_HealthScoreContributor>();
    Integer ungroupedIndex = 0;
    for (OI_HealthSignal signal : signals) {
      OI_HealthScoreContributor contributor = toContributor(signal);
      /** Tentatively "correlated out" only for signals that actually declared a shared group — an ungrouped signal is always its own group's sole (and therefore winning) member, cleared below. */
      contributor.wasCorrelatedOut = String.isNotBlank(signal.correlationGroup);
      contributors.add(contributor);

      String groupKey = String.isNotBlank(signal.correlationGroup)
        ? signal.correlationGroup
        : '__ungrouped_' + ungroupedIndex++;
      OI_HealthScoreContributor currentBest = bestByGroup.get(groupKey);
      if (
        currentBest == null ||
        contributor.contribution > currentBest.contribution
      ) {
        bestByGroup.put(groupKey, contributor);
      }
    }

    Decimal totalBadness = 0;
    for (OI_HealthScoreContributor best : bestByGroup.values()) {
      best.wasCorrelatedOut = false;
      totalBadness += best.contribution;
    }

    Decimal badness = totalBadness > 100
      ? 100
      : (totalBadness < 0 ? 0 : totalBadness);
    Decimal healthEquivalent = 100 - badness;

    result.score = badness.setScale(1, System.RoundingMode.HALF_UP);
    result.severityKey = severityService.resolveSeverityKey(healthEquivalent);
    result.contributors = contributors;
    result.explanation = buildExplanation(contributors, result.severityKey);
    return result;
  }

  private OI_HealthScoreContributor toContributor(OI_HealthSignal signal) {
    Decimal confidence = clamp(
      signal.confidence == null ? 1.0 : signal.confidence,
      0,
      1
    );
    Decimal impact = signal.impactMultiplier == null
      ? 1.0
      : signal.impactMultiplier;
    Decimal exposure = signal.exposureMultiplier == null
      ? 1.0
      : signal.exposureMultiplier;
    Decimal magnitude = signal.magnitude == null ||
      signal.magnitude < 0
      ? 0
      : signal.magnitude;
    Decimal saturatedMagnitude = magnitude > MAGNITUDE_SATURATION_CAP
      ? MAGNITUDE_SATURATION_CAP
      : magnitude;
    Decimal magnitudeRatio = saturatedMagnitude / MAGNITUDE_SATURATION_CAP;
    Boolean hasCompensatingControl = signal.hasCompensatingControl == true;
    Decimal compensatingDampener = hasCompensatingControl
      ? COMPENSATING_CONTROL_DAMPENER
      : 1.0;

    Decimal contribution =
      (signal.weight == null ? 0 : signal.weight) *
      magnitudeRatio *
      confidence *
      impact *
      exposure *
      compensatingDampener;

    OI_HealthScoreContributor contributor = new OI_HealthScoreContributor();
    contributor.key = signal.key;
    contributor.label = signal.label;
    contributor.weight = signal.weight;
    contributor.magnitude = magnitude.setScale(2, System.RoundingMode.HALF_UP);
    contributor.confidence = confidence;
    contributor.impactMultiplier = impact;
    contributor.exposureMultiplier = exposure;
    contributor.hasCompensatingControl = hasCompensatingControl;
    contributor.wasCorrelatedOut = false;
    contributor.contribution = contribution.setScale(
      2,
      System.RoundingMode.HALF_UP
    );
    contributor.note = signal.note;
    return contributor;
  }

  private Decimal clamp(Decimal value, Decimal minValue, Decimal maxValue) {
    if (value < minValue) {
      return minValue;
    }
    if (value > maxValue) {
      return maxValue;
    }
    return value;
  }

  private String buildExplanation(
    List<OI_HealthScoreContributor> contributors,
    String severityKey
  ) {
    List<OI_HealthScoreContributor> ranked = contributors.clone();
    ranked.sort(new ByContributionDescending());
    List<String> parts = new List<String>();
    for (Integer i = 0; i < Math.min(EXPLANATION_TOP_N, ranked.size()); i++) {
      OI_HealthScoreContributor top = ranked[i];
      if (top.contribution <= 0) {
        continue;
      }
      String piece =
        top.label +
        ' contributed ' +
        top.contribution +
        ' point(s)';
      if (top.hasCompensatingControl) {
        piece += ' (halved by a recorded compensating control)';
      }
      parts.add(piece);
    }
    if (parts.isEmpty()) {
      return 'Severity ' +
        severityKey +
        ' — no individual signal contributed meaningfully; see contributor detail.';
    }
    return 'Severity ' +
      severityKey +
      ' because: ' +
      String.join(parts, '; ') +
      '.';
  }

  private class ByContributionDescending implements Comparator<OI_HealthScoreContributor> {
    public Integer compare(
      OI_HealthScoreContributor a,
      OI_HealthScoreContributor b
    ) {
      if (a.contribution == b.contribution) {
        return 0;
      }
      return a.contribution > b.contribution ? -1 : 1;
    }
  }
}
