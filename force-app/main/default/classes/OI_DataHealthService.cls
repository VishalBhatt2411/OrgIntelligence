/**
 * Purpose: Org Health's Data Health section (ADR-0026 Phase 5, Tier 3 — async, persisted) —
 *          ProductSpecs.md's deterministic data-quality indicators: stale records,
 *          completeness (null density on the object's own required fields), and duplicates
 *          (exact-match on Email/Phone). Is_Scored__c = true — "any score must expose formula."
 *          Never runs unbounded full-org data profiling synchronously (ProductSpecs.md's
 *          explicit rule): this Service never queries object data itself — that is
 *          OI_DataHealthComputeBatchable's job, bounded per object by
 *          OI_Data_Health_Object_Scope__mdt.Max_Records_To_Sample__c. This Service owns two
 *          things only: shaping raw per-object signals into the scored DTO the Batchable
 *          persists, and reading that persisted result (plus the live AsyncApexJob status)
 *          back out for the UI. Each object's own row severity is a real multi-signal judgment
 *          (OI_HealthScoringEngine, ADR-0027 correction), not a bare threshold jump; this
 *          Service is also the unified-finding-model (ADR-0027) source for this section —
 *          getFindingCandidates() projects the exact same per-object evidence into one
 *          candidate per rule breach, called by the Batchable's finish() once per run (Data
 *          Health has no separate live "sync findings" action — computing and syncing findings
 *          both happen inside the one bounded, async, admin-triggered recompute).
 * Responsibilities: buildSnapshotFromSignals — the weighted-penalty score formula and
 *                    breakdown/heatmap shaping, pure and DML-free so it is directly testable
 *                    with hand-built signals; getFindingCandidates — the same per-object
 *                    signals projected into OI_OrgHealthFindingCandidate, equally pure and
 *                    DML-free; persistSnapshot — serializes and writes through
 *                    OI_OrgHealthSnapshotRepository; getDataHealthDetail — the read path the
 *                    Controller calls, resolving real run status from AsyncApexJob and, once a
 *                    result exists, deserializing the latest snapshot's Result_Json__c.
 * Dependencies: OI_OrgHealthSnapshotRepository, OI_HealthSeverityService,
 *               OI_HealthScoringEngine, OI_Org_Health_Metric_Config__mdt.
 * Limitations: Completeness is scoped to fields the object's own schema marks required
 *              (isNillable() = false) and user-editable — a generic, per-org-safe definition
 *              that needs no per-object configuration, but will report 100% complete for an
 *              object with no such fields (an honest "nothing to check," not a fabricated
 *              pass). Duplicate detection only fires for objects that have an Email or Phone
 *              field, and is scoped to exact-match on that one field — not native Duplicate
 *              Rule/Matching Rule/DuplicateRecordSet evidence. This is a deliberate v1
 *              simplification, not a silent omission: ProductSpecs.md's own Data Health scope
 *              ("Potential indicators: Record Count, stale records, null density, data
 *              completeness, high-volume Objects") does not name duplicates as a required
 *              indicator at all, so native Duplicate Management integration is a named future
 *              enhancement rather than in-scope for this pass. AsyncApexJob rows age out of the
 *              org after 7 days, so "last run status" naturally falls back to the persisted
 *              Snapshot once the job history itself has expired — see getRunStatus.
 */
public with sharing class OI_DataHealthService {
  private static final String SECTION_KEY = 'DataHealth';
  private static final String METRIC_STALE = 'StaleRecords';
  private static final String METRIC_COMPLETENESS = 'Completeness';
  private static final String METRIC_DUPLICATES = 'Duplicates';
  private static final String BATCHABLE_CLASS_NAME = 'OI_DataHealthComputeBatchable';
  private static final Integer BREAKDOWN_ROW_LIMIT = 8;
  private static final Integer HEATMAP_ROW_LIMIT = 5;
  /**
   * Mirrors every other domain's identical PRIMARY_SIGNAL_WEIGHT convention, but paired with
   * a deliberately lower confidence (0.7, vs. 0.8 for deterministic graph-count signals
   * elsewhere) since a sampled percentage rate is inherently a noisier estimate of the true
   * org-wide rate than a full-population graph count — this combination preserves this
   * domain's own established, more lenient "roughly double the threshold reaches Critical"
   * convention for rate-based metrics (vs. the ~1.3x convention count-based domains use).
   */
  private static final Decimal PRIMARY_SIGNAL_WEIGHT = 90;
  private static final Decimal RATE_SIGNAL_CONFIDENCE = 0.7;

  private final OI_OrgHealthSnapshotRepository snapshotRepository;
  private final OI_HealthSeverityService severityService;
  private final OI_HealthScoringEngine scoringEngine;

  public OI_DataHealthService() {
    this(
      new OI_OrgHealthSnapshotRepository(),
      new OI_HealthSeverityService(),
      new OI_HealthScoringEngine()
    );
  }

  public OI_DataHealthService(
    OI_OrgHealthSnapshotRepository snapshotRepository,
    OI_HealthSeverityService severityService,
    OI_HealthScoringEngine scoringEngine
  ) {
    this.snapshotRepository = snapshotRepository;
    this.severityService = severityService;
    this.scoringEngine = scoringEngine;
  }

  /** The Controller's read path — real async status first, the latest persisted result (if any) layered underneath it. */
  public OI_DataHealthDTO getDataHealthDetail() {
    String runStatus = resolveRunStatus();
    OI_Org_Health_Snapshot__c latest = snapshotRepository.getLatest(
      SECTION_KEY
    );

    OI_DataHealthDTO dto;
    if (latest != null && String.isNotBlank(latest.Result_Json__c)) {
      dto = (OI_DataHealthDTO) JSON.deserialize(
        latest.Result_Json__c,
        OI_DataHealthDTO.class
      );
    } else {
      dto = new OI_DataHealthDTO();
      dto.coverageNote = 'Data Health has not been computed yet. Run a scan to see results.';
      dto.isCoverageComplete = false;
    }
    dto.runStatus = runStatus;
    return dto;
  }

  /** The most recent AsyncApexJob for this Batchable, if any — real platform status, never a hand-rolled state machine. */
  @TestVisible
  private String resolveRunStatus() {
    List<AsyncApexJob> jobs = [
      SELECT Status
      FROM AsyncApexJob
      WHERE ApexClass.Name = :BATCHABLE_CLASS_NAME
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (jobs.isEmpty()) {
      return 'NotYetRun';
    }
    String status = jobs[0].Status;
    if (status == 'Queued' || status == 'Holding' || status == 'Preparing') {
      return 'Queued';
    }
    if (status == 'Processing') {
      return 'Processing';
    }
    if (status == 'Completed') {
      return 'Completed';
    }
    if (status == 'Failed') {
      return 'Failed';
    }
    if (status == 'Aborted') {
      return 'Aborted';
    }
    return 'NotYetRun';
  }

  /** Pure and DML-free — the weighted-penalty score formula (mirrors Metadata/Code Health exactly) plus KPI/breakdown/heatmap shaping, built entirely from already-collected per-object signals. */
  public OI_DataHealthDTO buildSnapshotFromSignals(
    List<ObjectSignal> signals,
    List<String> skippedObjects,
    Boolean anyObjectTruncated
  ) {
    Thresholds thresholds = loadThresholds();

    Integer totalSampled = 0;
    Integer totalStale = 0;
    Integer totalIncomplete = 0;
    Integer totalDuplicates = 0;
    for (ObjectSignal signal : signals) {
      totalSampled += signal.sampledCount;
      totalStale += signal.staleCount;
      totalIncomplete += signal.incompleteCount;
      totalDuplicates += signal.duplicateCount;
      signal.applySeverity(thresholds, scoringEngine);
    }

    OI_DataHealthDTO dto = new OI_DataHealthDTO();
    dto.computedAt = Datetime.now();
    populateScoreAndFormula(
      dto,
      totalSampled,
      totalStale,
      totalIncomplete,
      totalDuplicates,
      thresholds
    );
    populateCoverage(dto, signals, skippedObjects, anyObjectTruncated);
    populateKpiTiles(
      dto,
      signals,
      totalSampled,
      totalStale,
      totalIncomplete,
      totalDuplicates
    );
    populateBreakdownAndHeatmap(dto, signals);
    return dto;
  }

  /**
   * The unified-finding-model view of this run's signals (ADR-0027) — one candidate per rule
   * breach per object, reusing the exact same signals buildSnapshotFromSignals already scored.
   * Pure and DML-free like buildSnapshotFromSignals; the Batchable's finish() calls both on
   * the same signal list, then syncs the resulting candidates in the same run.
   */
  public List<OI_OrgHealthFindingCandidate> getFindingCandidates(
    List<ObjectSignal> signals
  ) {
    Thresholds thresholds = loadThresholds();
    List<OI_OrgHealthFindingCandidate> candidates = new List<OI_OrgHealthFindingCandidate>();
    for (ObjectSignal signal : signals) {
      if (signal.staleScore == null) {
        signal.applySeverity(thresholds, scoringEngine);
      }
      if (signal.staleScore.severityKey != 'Good') {
        candidates.add(buildStaleCandidate(signal, thresholds));
      }
      if (signal.incompleteScore.severityKey != 'Good') {
        candidates.add(buildCompletenessCandidate(signal, thresholds));
      }
      if (signal.duplicateScore.severityKey != 'Good') {
        candidates.add(buildDuplicatesCandidate(signal, thresholds));
      }
    }
    return candidates;
  }

  private OI_OrgHealthFindingCandidate buildStaleCandidate(
    ObjectSignal signal,
    Thresholds thresholds
  ) {
    OI_OrgHealthFindingCandidate candidate = new OI_OrgHealthFindingCandidate();
    candidate.sectionKey = SECTION_KEY;
    candidate.ruleId = 'DataHealth.StaleRecords';
    candidate.ruleVersion = 1;
    candidate.title =
      signal.objectApiName + ' has an unusually high rate of stale records';
    candidate.severityKey = signal.staleScore.severityKey;
    candidate.score = signal.staleScore.score;
    candidate.scoreExplanation = signal.staleScore.explanation;
    candidate.scoreContributorsJson = JSON.serialize(
      signal.staleScore.contributors
    );
    candidate.confidence = 'Medium';
    candidate.componentKey = signal.objectApiName;
    candidate.componentType = 'Object';
    candidate.componentLabel = signal.objectApiName;
    candidate.isManaged = false;
    candidate.evidence =
      signal.staleCount +
      ' of ' +
      signal.sampledCount +
      ' sampled records (' +
      signal.staleRatePercent() +
      '%) were not modified in the last 180 days (configured threshold: ' +
      thresholds.staleThresholdPercent.intValue() +
      '%). ' +
      signal.staleScore.explanation;
    candidate.measuredValue = signal.staleRatePercent() + '% stale';
    candidate.expectedValue =
      '< ' +
      thresholds.staleThresholdPercent.intValue() +
      '% stale';
    candidate.explanation = 'A high rate of records untouched for 180+ days often signals dead or low-value data — abandoned leads, closed-out records nobody archived, or an integration that stopped syncing.';
    candidate.orgRisk =
      'Reports, dashboards, and automation running against ' +
      signal.objectApiName +
      ' are working against a growing share of stale data.';
    candidate.potentialImpact = 'Misleading reporting, wasted storage, and harder-to-trust automation decisions built on this object.';
    candidate.remediation =
      'Review whether ' +
      signal.objectApiName +
      ' needs an archival/cleanup process, or whether the staleness is expected and this object should be excluded from scope.';
    candidate.validationSteps =
      'Re-run the Data Health scan after cleanup and confirm the stale rate for ' +
      signal.objectApiName +
      ' has dropped below ' +
      thresholds.staleThresholdPercent.intValue() +
      '%, or that this finding no longer appears.';
    return candidate;
  }

  private OI_OrgHealthFindingCandidate buildCompletenessCandidate(
    ObjectSignal signal,
    Thresholds thresholds
  ) {
    OI_OrgHealthFindingCandidate candidate = new OI_OrgHealthFindingCandidate();
    candidate.sectionKey = SECTION_KEY;
    candidate.ruleId = 'DataHealth.Completeness';
    candidate.ruleVersion = 1;
    candidate.title =
      signal.objectApiName +
      ' has an unusually high rate of incomplete records';
    candidate.severityKey = signal.incompleteScore.severityKey;
    candidate.score = signal.incompleteScore.score;
    candidate.scoreExplanation = signal.incompleteScore.explanation;
    candidate.scoreContributorsJson = JSON.serialize(
      signal.incompleteScore.contributors
    );
    candidate.confidence = 'Medium';
    candidate.componentKey = signal.objectApiName;
    candidate.componentType = 'Object';
    candidate.componentLabel = signal.objectApiName;
    candidate.isManaged = false;
    candidate.evidence =
      signal.incompleteCount +
      ' of ' +
      signal.sampledCount +
      ' sampled records (' +
      signal.incompleteRatePercent() +
      '%) are missing a value the object\'s own schema marks required (configured threshold: ' +
      thresholds.completenessThresholdPercent.intValue() +
      '%). ' +
      signal.incompleteScore.explanation;
    candidate.measuredValue = signal.incompleteRatePercent() + '% incomplete';
    candidate.expectedValue =
      '< ' +
      thresholds.completenessThresholdPercent.intValue() +
      '% incomplete';
    candidate.explanation = 'A required field left null on a record it should always be populated on usually means the data was created outside normal validation — a bulk import, a data migration, or an integration that skipped a mapping.';
    candidate.orgRisk =
      'Downstream automation, reports, and integrations reading ' +
      signal.objectApiName +
      ' may assume this required field is always populated and behave unexpectedly when it is not.';
    candidate.potentialImpact = 'Broken automation logic, misleading reports, and a growing backlog of records that need manual correction.';
    candidate.remediation = 'Identify the source of the incomplete records (import, migration, integration) and either backfill the missing values or fix the source process.';
    candidate.validationSteps =
      'Re-run the Data Health scan after backfilling and confirm the incomplete rate for ' +
      signal.objectApiName +
      ' has dropped below ' +
      thresholds.completenessThresholdPercent.intValue() +
      '%, or that this finding no longer appears.';
    return candidate;
  }

  private OI_OrgHealthFindingCandidate buildDuplicatesCandidate(
    ObjectSignal signal,
    Thresholds thresholds
  ) {
    OI_OrgHealthFindingCandidate candidate = new OI_OrgHealthFindingCandidate();
    candidate.sectionKey = SECTION_KEY;
    candidate.ruleId = 'DataHealth.Duplicates';
    candidate.ruleVersion = 1;
    candidate.title =
      signal.objectApiName +
      ' has an unusually high rate of exact-match duplicate records';
    candidate.severityKey = signal.duplicateScore.severityKey;
    candidate.score = signal.duplicateScore.score;
    candidate.scoreExplanation = signal.duplicateScore.explanation;
    candidate.scoreContributorsJson = JSON.serialize(
      signal.duplicateScore.contributors
    );
    candidate.confidence = 'Low';
    candidate.componentKey = signal.objectApiName;
    candidate.componentType = 'Object';
    candidate.componentLabel = signal.objectApiName;
    candidate.isManaged = false;
    candidate.evidence =
      signal.duplicateCount +
      ' of ' +
      signal.sampledCount +
      ' sampled records (' +
      signal.duplicateRatePercent() +
      '%) share an exact-match Email or Phone value with at least one other sampled record (configured threshold: ' +
      thresholds.duplicatesThresholdPercent.intValue() +
      '%). ' +
      signal.duplicateScore.explanation;
    candidate.measuredValue =
      signal.duplicateRatePercent() + '% exact-match duplicates';
    candidate.expectedValue =
      '< ' +
      thresholds.duplicatesThresholdPercent.intValue() +
      '% exact-match duplicates';
    candidate.explanation = 'This is a simple exact-match check on Email or Phone within the sampled window, not native Duplicate Rule/Matching Rule evidence — it is a low-confidence, review-first signal, not a confirmed duplicate-record verdict.';
    candidate.orgRisk =
      'Duplicate records on ' +
      signal.objectApiName +
      ' fragment activity history, skew counts/reports, and create confusion about which record is authoritative.';
    candidate.potentialImpact = 'Split communication history, inflated record counts in reporting, and wasted effort maintaining more than one copy of the same real-world record.';
    candidate.remediation = 'Review the matched records using Salesforce\'s native Duplicate/Matching Rules and merge tooling for a confirmed, auditable merge rather than acting on this heuristic alone.';
    candidate.validationSteps =
      'Re-run the Data Health scan after merging and confirm the duplicate rate for ' +
      signal.objectApiName +
      ' has dropped below ' +
      thresholds.duplicatesThresholdPercent.intValue() +
      '%, or that this finding no longer appears.';
    return candidate;
  }

  public void persistSnapshot(
    OI_DataHealthDTO dto,
    String computeRunId,
    Integer rowCountExamined,
    Boolean isTruncated,
    Id triggeredById
  ) {
    snapshotRepository.put(
      SECTION_KEY,
      computeRunId,
      dto.score,
      JSON.serialize(dto),
      dto.coverageNote,
      dto.computedAt,
      rowCountExamined,
      isTruncated,
      triggeredById
    );
  }

  private void populateScoreAndFormula(
    OI_DataHealthDTO dto,
    Integer totalSampled,
    Integer totalStale,
    Integer totalIncomplete,
    Integer totalDuplicates,
    Thresholds thresholds
  ) {
    Decimal score;
    if (totalSampled == 0) {
      score = null;
    } else {
      Decimal penalty =
        (Decimal.valueOf(totalStale) / totalSampled) * thresholds.staleWeight +
        (Decimal.valueOf(totalIncomplete) / totalSampled) *
        thresholds.completenessWeight +
        (Decimal.valueOf(totalDuplicates) / totalSampled) *
        thresholds.duplicatesWeight;
      score = (100 - penalty).setScale(0, System.RoundingMode.HALF_UP);
      score = score < 0 ? 0 : (score > 100 ? 100 : score);
    }
    dto.score = score;
    dto.severityKey = severityService.resolveSeverityKey(score);

    dto.formulaSummary = 'Score = 100 − weighted penalty per metric, proportional to its org-wide bad-record rate. Thresholds and weights are admin-configurable in Org Health Settings.';
    dto.formulaComponents.add(
      new OI_HealthKeyValueDTO(
        'Stale records — not modified in 180+ days',
        '(weight ' + thresholds.staleWeight.intValue() + '%)'
      )
    );
    dto.formulaComponents.add(
      new OI_HealthKeyValueDTO(
        'Completeness — required fields left null',
        '(weight ' + thresholds.completenessWeight.intValue() + '%)'
      )
    );
    dto.formulaComponents.add(
      new OI_HealthKeyValueDTO(
        'Duplicates — exact-match Email/Phone',
        '(weight ' + thresholds.duplicatesWeight.intValue() + '%)'
      )
    );
  }

  private void populateCoverage(
    OI_DataHealthDTO dto,
    List<ObjectSignal> signals,
    List<String> skippedObjects,
    Boolean anyObjectTruncated
  ) {
    dto.isCoverageComplete =
      anyObjectTruncated != true &&
      (skippedObjects == null || skippedObjects.isEmpty());
    String note =
      signals.size() +
      ' object' +
      (signals.size() == 1 ? '' : 's') +
      ' scanned';
    if (anyObjectTruncated == true) {
      note += ' (one or more hit their sample ceiling — results may be incomplete)';
    }
    if (skippedObjects != null && !skippedObjects.isEmpty()) {
      note += '. Skipped: ' + String.join(skippedObjects, ', ');
    }
    dto.coverageNote = note;
  }

  private void populateKpiTiles(
    OI_DataHealthDTO dto,
    List<ObjectSignal> signals,
    Integer totalSampled,
    Integer totalStale,
    Integer totalIncomplete,
    Integer totalDuplicates
  ) {
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'Objects scanned',
        String.valueOf(signals.size())
      )
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO('Records sampled', String.valueOf(totalSampled))
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO('Stale records', String.valueOf(totalStale))
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'Incomplete records',
        String.valueOf(totalIncomplete)
      )
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'Duplicate records',
        String.valueOf(totalDuplicates)
      )
    );
  }

  private void populateBreakdownAndHeatmap(
    OI_DataHealthDTO dto,
    List<ObjectSignal> signals
  ) {
    List<ObjectSignal> ranked = signals.clone();
    ranked.sort(new ByAttentionRank());

    dto.breakdownTitle = 'Objects needing attention';
    dto.metricColumnLabels = new List<String>{
      'Stale %',
      'Incomplete %',
      'Duplicate %'
    };
    Integer breakdownCount = Math.min(BREAKDOWN_ROW_LIMIT, ranked.size());
    dto.breakdownCoverageCaption =
      'Top ' +
      breakdownCount +
      ' of ' +
      signals.size();
    for (Integer i = 0; i < breakdownCount; i++) {
      ObjectSignal signal = ranked[i];
      OI_HealthBreakdownRowDTO row = new OI_HealthBreakdownRowDTO();
      row.key = signal.objectApiName;
      row.primaryLabel =
        signal.objectApiName +
        ' (' +
        signal.totalRecordCount +
        ' total)';
      row.metricValues.add(
        new OI_HealthMetricValueDTO(
          'stale',
          String.valueOf(signal.staleRatePercent())
        )
      );
      row.metricValues.add(
        new OI_HealthMetricValueDTO(
          'incomplete',
          String.valueOf(signal.incompleteRatePercent())
        )
      );
      row.metricValues.add(
        new OI_HealthMetricValueDTO(
          'duplicate',
          String.valueOf(signal.duplicateRatePercent())
        )
      );
      row.severityKey = signal.severityKey;
      row.severityLabel = signal.severityKey;
      dto.breakdownRows.add(row);
    }

    dto.heatmapColumnLabels = new List<String>{
      'Stale %',
      'Incomplete %',
      'Duplicate %'
    };
    Integer heatmapCount = Math.min(HEATMAP_ROW_LIMIT, ranked.size());
    for (Integer i = 0; i < heatmapCount; i++) {
      ObjectSignal signal = ranked[i];
      OI_HealthHeatmapRowDTO row = new OI_HealthHeatmapRowDTO();
      row.rowLabel = signal.objectApiName;
      row.cells.add(
        new OI_HealthMetricValueDTO(
          'stale',
          String.valueOf(signal.staleRatePercent()),
          signal.staleScore.severityKey
        )
      );
      row.cells.add(
        new OI_HealthMetricValueDTO(
          'incomplete',
          String.valueOf(signal.incompleteRatePercent()),
          signal.incompleteScore.severityKey
        )
      );
      row.cells.add(
        new OI_HealthMetricValueDTO(
          'duplicate',
          String.valueOf(signal.duplicateRatePercent()),
          signal.duplicateScore.severityKey
        )
      );
      dto.heatmapRows.add(row);
    }
  }

  @TestVisible
  private Thresholds loadThresholds() {
    Map<String, Decimal> thresholdByMetric = new Map<String, Decimal>();
    Map<String, Decimal> weightByMetric = new Map<String, Decimal>();
    for (
      OI_Org_Health_Metric_Config__mdt row : OI_Org_Health_Metric_Config__mdt.getAll()
        .values()
    ) {
      if (row.Section_Key__c != SECTION_KEY || row.Is_Active__c != true) {
        continue;
      }
      thresholdByMetric.put(row.Metric_Key__c, row.Threshold_Value__c);
      weightByMetric.put(row.Metric_Key__c, row.Weight__c);
    }
    return new Thresholds(
      decimalOrDefault(thresholdByMetric.get(METRIC_STALE), 15),
      decimalOrDefault(weightByMetric.get(METRIC_STALE), 35),
      decimalOrDefault(thresholdByMetric.get(METRIC_COMPLETENESS), 10),
      decimalOrDefault(weightByMetric.get(METRIC_COMPLETENESS), 35),
      decimalOrDefault(thresholdByMetric.get(METRIC_DUPLICATES), 5),
      decimalOrDefault(weightByMetric.get(METRIC_DUPLICATES), 30)
    );
  }

  private Decimal decimalOrDefault(Decimal value, Decimal fallback) {
    return value == null ? fallback : value;
  }

  /** Sorts worst-first: Critical before Warning before Good, then by combined bad-rate within a tier. */
  private class ByAttentionRank implements Comparator<ObjectSignal> {
    public Integer compare(ObjectSignal a, ObjectSignal b) {
      Integer rankA = severityRank(a.severityKey);
      Integer rankB = severityRank(b.severityKey);
      if (rankA != rankB) {
        return rankA - rankB;
      }
      Decimal combinedA =
        a.staleRatePercent() +
        a.incompleteRatePercent() +
        a.duplicateRatePercent();
      Decimal combinedB =
        b.staleRatePercent() +
        b.incompleteRatePercent() +
        b.duplicateRatePercent();
      return combinedB > combinedA ? 1 : (combinedB < combinedA ? -1 : 0);
    }

    private Integer severityRank(String severityKey) {
      if (severityKey == 'Critical') {
        return 0;
      }
      if (severityKey == 'Warning') {
        return 1;
      }
      return 2;
    }
  }

  /** One scoped object's collected sample signal — built by OI_DataHealthComputeBatchable, shaped by this Service. Public: the Batchable constructs and populates instances of it directly. */
  public class ObjectSignal {
    public String objectApiName;
    public Integer totalRecordCount;
    public Integer sampledCount;
    public Integer staleCount;
    public Integer incompleteCount;
    public Integer duplicateCount;
    public Boolean isTruncated;
    public OI_HealthScoreResult staleScore;
    public OI_HealthScoreResult incompleteScore;
    public OI_HealthScoreResult duplicateScore;
    public String severityKey;

    public ObjectSignal(
      String objectApiName,
      Integer totalRecordCount,
      Integer sampledCount,
      Integer staleCount,
      Integer incompleteCount,
      Integer duplicateCount,
      Boolean isTruncated
    ) {
      this.objectApiName = objectApiName;
      this.totalRecordCount = totalRecordCount;
      this.sampledCount = sampledCount;
      this.staleCount = staleCount;
      this.incompleteCount = incompleteCount;
      this.duplicateCount = duplicateCount;
      this.isTruncated = isTruncated;
    }

    public Decimal staleRatePercent() {
      return ratePercent(staleCount);
    }

    public Decimal incompleteRatePercent() {
      return ratePercent(incompleteCount);
    }

    public Decimal duplicateRatePercent() {
      return ratePercent(duplicateCount);
    }

    private Decimal ratePercent(Integer badCount) {
      if (sampledCount == null || sampledCount == 0) {
        return 0;
      }
      return (Decimal.valueOf(badCount) /
        sampledCount *
        100)
        .setScale(1, System.RoundingMode.HALF_UP);
    }

    /** Called once thresholds are known — computes this object's per-metric and overall row severity via the shared scoring engine. */
    public void applySeverity(
      Thresholds thresholds,
      OI_HealthScoringEngine scoringEngine
    ) {
      this.staleScore = scoringEngine.score(
        new List<OI_HealthSignal>{
          rateSignal(
            'StaleRecords',
            'Stale record rate',
            staleRatePercent(),
            thresholds.staleThresholdPercent
          )
        }
      );
      this.incompleteScore = scoringEngine.score(
        new List<OI_HealthSignal>{
          rateSignal(
            'Completeness',
            'Incomplete record rate',
            incompleteRatePercent(),
            thresholds.completenessThresholdPercent
          )
        }
      );
      this.duplicateScore = scoringEngine.score(
        new List<OI_HealthSignal>{
          rateSignal(
            'Duplicates',
            'Duplicate record rate',
            duplicateRatePercent(),
            thresholds.duplicatesThresholdPercent
          )
        }
      );
      this.severityKey = worstOf(
        staleScore.severityKey,
        incompleteScore.severityKey,
        duplicateScore.severityKey
      );
    }

    private OI_HealthSignal rateSignal(
      String key,
      String label,
      Decimal ratePercent,
      Decimal thresholdPercent
    ) {
      OI_HealthSignal signal = new OI_HealthSignal(
        key,
        label,
        PRIMARY_SIGNAL_WEIGHT,
        thresholdPercent != null &&
          thresholdPercent > 0
          ? ratePercent / thresholdPercent
          : 0,
        ratePercent +
          '% vs. threshold ' +
          (thresholdPercent == null ? 0 : thresholdPercent.intValue()) +
          '% (of ' +
          sampledCount +
          ' sampled record(s))'
      );
      signal.confidence = RATE_SIGNAL_CONFIDENCE;
      return signal;
    }

    private String worstOf(String a, String b, String c) {
      if (a == 'Critical' || b == 'Critical' || c == 'Critical') {
        return 'Critical';
      }
      if (a == 'Warning' || b == 'Warning' || c == 'Warning') {
        return 'Warning';
      }
      return 'Good';
    }
  }

  public class Thresholds {
    public Decimal staleThresholdPercent;
    public Decimal staleWeight;
    public Decimal completenessThresholdPercent;
    public Decimal completenessWeight;
    public Decimal duplicatesThresholdPercent;
    public Decimal duplicatesWeight;

    public Thresholds(
      Decimal staleThresholdPercent,
      Decimal staleWeight,
      Decimal completenessThresholdPercent,
      Decimal completenessWeight,
      Decimal duplicatesThresholdPercent,
      Decimal duplicatesWeight
    ) {
      this.staleThresholdPercent = staleThresholdPercent;
      this.staleWeight = staleWeight;
      this.completenessThresholdPercent = completenessThresholdPercent;
      this.completenessWeight = completenessWeight;
      this.duplicatesThresholdPercent = duplicatesThresholdPercent;
      this.duplicatesWeight = duplicatesWeight;
    }
  }
}
