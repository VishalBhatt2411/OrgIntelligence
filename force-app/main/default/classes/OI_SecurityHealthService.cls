/**
 * Purpose: Org Health's Security Health section (ADR-0026 Phase 4, Tier 2 — live, bounded,
 *          unpersisted) — ProductSpecs.md's evidence-based checks: broad Object grants,
 *          sensitive metadata with broad grants, Permission Set coverage, elevated
 *          permissions. Facts-only — Is_Scored__c = false (§0.3): the spec says "No fake
 *          score" for this section, so no composite score is computed or invented; each row's
 *          own severity is still a real multi-signal judgment (OI_HealthScoringEngine, ADR-0027
 *          correction), not a bare threshold jump.
 * Responsibilities: Read a bounded set of Permission Sets (including profile shadow rows,
 *                    §0.6) via OI_PermissionSetSelector, evaluate each one's elevated system
 *                    permissions and broad object grants against real, admin-configurable
 *                    thresholds, score each rule's evidence through the shared
 *                    OI_HealthScoringEngine, and shape the result for the breakdown table +
 *                    heatmap primitives. Also the unified-finding-model (ADR-0027) source for
 *                    this section — getFindingCandidates() projects the exact same evidence
 *                    into one candidate per rule breach per Permission Set.
 * Dependencies: OI_PermissionSetSelector, OI_HealthScoringEngine, OI_Org_Health_Section_Config__mdt,
 *               OI_Org_Health_Metric_Config__mdt.
 * Limitations: "Elevated permissions" is scoped to a fixed, curated set of seven
 *              well-recognized administrative system permissions (Modify All Data, View All
 *              Data, Author Apex, Manage Users, Customize Application, Manage Sharing, Reset
 *              Passwords) — a deliberate v1 simplification (mirrors the Data Health canonical-
 *              variant precedent), not every PermissionsXxx boolean PermissionSet exposes.
 *              "Sensitive metadata" is scoped to a fixed set of PII/financial CRM objects
 *              (Contact, Account) rather than identity/setup objects (User, Group, Profile):
 *              ObjectPermissions.SobjectType's own restricted picklist does not accept
 *              identity/setup object names at all (confirmed against a real org — User, Group,
 *              Profile, PermissionSet, and ApexClass are all invalid values there; those are
 *              governed by SetupEntityAccess and system permission booleans instead, already
 *              covered by the elevated-permissions check above), so "broad access to a
 *              sensitive object" is scoped to the CRM/PII data ObjectPermissions can actually
 *              describe — extendable later, e.g. via CMDT, if that need arises. Broader
 *              Security areas named in ADR-0026's own vision (network access, session settings,
 *              native Health Check score, connected/external client apps, authentication policy)
 *              are a named future enhancement, not a silent omission — ProductSpecs.md's own
 *              Security Health scope lists exactly the four evidence-based checks this class
 *              already covers ("broad Object grants," "sensitive metadata with broad grants,"
 *              "Permission Set coverage," "elevated permissions"), and none of those broader
 *              areas have an existing selector/service in this codebase yet.
 *              Field-level grants are out of scope (OI_PermissionSetSelector's own
 *              documented limitation). Bounded by a ceiling (Live_Row_Ceiling__c, falling back
 *              to a built-in default).
 */
public with sharing class OI_SecurityHealthService {
  private static final String SECTION_KEY = 'SecurityHealth';
  private static final String METRIC_ELEVATED_PERMISSIONS = 'ElevatedPermissionCount';
  private static final String METRIC_BROAD_GRANTS = 'BroadGrantCount';
  private static final Integer DEFAULT_CEILING = 500;
  private static final Integer BREAKDOWN_ROW_LIMIT = 8;
  private static final Integer HEATMAP_ROW_LIMIT = 5;
  /** Mirrors OI_MetadataHealthService's/OI_AutomationHealthService's/OI_CodeHealthService's identical constant — a single fully-saturated, full-confidence signal alone can reach Critical. */
  private static final Decimal PRIMARY_SIGNAL_WEIGHT = 90;
  @TestVisible
  private static final Set<String> SENSITIVE_OBJECT_API_NAMES = new Set<String>{
    'Contact',
    'Account'
  };

  private final OI_PermissionSetSelector permissionSetSelector;
  private final OI_HealthScoringEngine scoringEngine;

  public OI_SecurityHealthService() {
    this(new OI_PermissionSetSelector(), new OI_HealthScoringEngine());
  }

  public OI_SecurityHealthService(
    OI_PermissionSetSelector permissionSetSelector,
    OI_HealthScoringEngine scoringEngine
  ) {
    this.permissionSetSelector = permissionSetSelector;
    this.scoringEngine = scoringEngine;
  }

  public OI_SecurityHealthDTO getSecurityHealthDetail() {
    Decimal elevatedThreshold = loadThreshold(METRIC_ELEVATED_PERMISSIONS, 1);
    Decimal broadGrantThreshold = loadThreshold(METRIC_BROAD_GRANTS, 1);
    Integer ceiling = loadCeiling();
    List<PermissionSetSignal> signals = buildAllSignals(
      elevatedThreshold,
      broadGrantThreshold,
      ceiling
    );

    OI_SecurityHealthDTO dto = new OI_SecurityHealthDTO();
    dto.computedAt = Datetime.now();
    populateCoverage(dto, signals.size(), ceiling);
    populateKpiTiles(dto, signals);
    populateBreakdownAndHeatmap(dto, signals);
    return dto;
  }

  /**
   * The unified-finding-model view of this section's live signals (ADR-0027) — one candidate
   * per rule breach per Permission Set, reusing the exact same query/threshold/signal logic
   * getSecurityHealthDetail already computes.
   */
  public List<OI_OrgHealthFindingCandidate> getFindingCandidates() {
    Decimal elevatedThreshold = loadThreshold(METRIC_ELEVATED_PERMISSIONS, 1);
    Decimal broadGrantThreshold = loadThreshold(METRIC_BROAD_GRANTS, 1);
    List<PermissionSetSignal> signals = buildAllSignals(
      elevatedThreshold,
      broadGrantThreshold,
      loadCeiling()
    );

    List<OI_OrgHealthFindingCandidate> candidates = new List<OI_OrgHealthFindingCandidate>();
    for (PermissionSetSignal signal : signals) {
      if (signal.elevatedScore.severityKey != 'Good') {
        candidates.add(
          buildElevatedPermissionsCandidate(signal, elevatedThreshold)
        );
      }
      if (signal.broadGrantScore.severityKey != 'Good') {
        candidates.add(buildBroadGrantCandidate(signal, broadGrantThreshold));
      }
      if (signal.hasSensitiveGrant) {
        candidates.add(buildSensitiveGrantCandidate(signal));
      }
    }
    return candidates;
  }

  private List<PermissionSetSignal> buildAllSignals(
    Decimal elevatedThreshold,
    Decimal broadGrantThreshold,
    Integer ceiling
  ) {
    List<PermissionSet> permissionSets = permissionSetSelector.selectPermissionSetsBounded(
      ceiling
    );
    Set<Id> permissionSetIds = new Set<Id>();
    for (PermissionSet permissionSet : permissionSets) {
      permissionSetIds.add(permissionSet.Id);
    }

    Map<Id, Integer> assigneeCountsByPsId = permissionSetSelector.countAssigneesByPermissionSetIds(
      permissionSetIds
    );
    Map<Id, Integer> broadGrantCountByPsId = new Map<Id, Integer>();
    Set<Id> sensitiveGrantPsIds = new Set<Id>();
    for (
      ObjectPermissions grant : permissionSetSelector.selectBroadObjectGrants(
        permissionSetIds
      )
    ) {
      Integer count = broadGrantCountByPsId.containsKey(grant.ParentId)
        ? broadGrantCountByPsId.get(grant.ParentId)
        : 0;
      broadGrantCountByPsId.put(grant.ParentId, count + 1);
      if (SENSITIVE_OBJECT_API_NAMES.contains(grant.SobjectType)) {
        sensitiveGrantPsIds.add(grant.ParentId);
      }
    }

    return buildSignals(
      permissionSets,
      assigneeCountsByPsId,
      broadGrantCountByPsId,
      sensitiveGrantPsIds,
      elevatedThreshold,
      broadGrantThreshold
    );
  }

  private OI_OrgHealthFindingCandidate buildElevatedPermissionsCandidate(
    PermissionSetSignal signal,
    Decimal threshold
  ) {
    OI_OrgHealthFindingCandidate candidate = new OI_OrgHealthFindingCandidate();
    candidate.sectionKey = SECTION_KEY;
    candidate.ruleId = 'SecurityHealth.ElevatedPermissions';
    candidate.ruleVersion = 1;
    candidate.title =
      signal.label +
      ' grants an unusually high number of elevated system permissions';
    candidate.severityKey = signal.elevatedScore.severityKey;
    candidate.score = signal.elevatedScore.score;
    candidate.scoreExplanation = signal.elevatedScore.explanation;
    candidate.scoreContributorsJson = JSON.serialize(
      signal.elevatedScore.contributors
    );
    candidate.confidence = 'Medium';
    candidate.componentKey = String.valueOf(signal.permissionSetId);
    candidate.componentType = signal.isOwnedByProfile == true
      ? 'Profile'
      : 'Permission Set';
    candidate.componentLabel = signal.label;
    candidate.isManaged = false;
    candidate.evidence =
      signal.elevatedPermissionCount +
      ' of 7 curated elevated system permission(s) granted (configured threshold: ' +
      threshold.intValue() +
      '). ' +
      signal.elevatedScore.explanation;
    candidate.measuredValue =
      signal.elevatedPermissionCount + ' elevated system permission(s)';
    candidate.expectedValue =
      '< ' +
      threshold.intValue() +
      ' elevated system permission(s)';
    candidate.explanation = 'Elevated system permissions (e.g. Modify All Data, Manage Users) let an assignee bypass normal record-level and setup restrictions — the more of them one Permission Set grants together, the larger the blast radius if that Permission Set is mis-assigned.';
    candidate.orgRisk =
      'Any user assigned ' +
      signal.label +
      ' inherits all ' +
      signal.elevatedPermissionCount +
      ' of these elevated capabilities at once.';
    candidate.potentialImpact = 'Broader-than-intended administrative access, harder least-privilege review, higher damage potential from a compromised or mis-assigned user.';
    candidate.remediation =
      'Review whether every elevated permission on ' +
      signal.label +
      ' is actually required for its intended audience; split narrowly-scoped permissions into a separate Permission Set where they are not.';
    candidate.validationSteps =
      'Re-run the Security Health scan after narrowing the grant and confirm the elevated permission count for ' +
      signal.label +
      ' has dropped below ' +
      threshold.intValue() +
      ', or that this finding no longer appears.';
    return candidate;
  }

  private OI_OrgHealthFindingCandidate buildBroadGrantCandidate(
    PermissionSetSignal signal,
    Decimal threshold
  ) {
    OI_OrgHealthFindingCandidate candidate = new OI_OrgHealthFindingCandidate();
    candidate.sectionKey = SECTION_KEY;
    candidate.ruleId = 'SecurityHealth.BroadObjectGrant';
    candidate.ruleVersion = 1;
    candidate.title =
      signal.label +
      ' grants an unusually high number of broad object-level permissions';
    candidate.severityKey = signal.broadGrantScore.severityKey;
    candidate.score = signal.broadGrantScore.score;
    candidate.scoreExplanation = signal.broadGrantScore.explanation;
    candidate.scoreContributorsJson = JSON.serialize(
      signal.broadGrantScore.contributors
    );
    candidate.confidence = 'Medium';
    candidate.componentKey = String.valueOf(signal.permissionSetId);
    candidate.componentType = signal.isOwnedByProfile == true
      ? 'Profile'
      : 'Permission Set';
    candidate.componentLabel = signal.label;
    candidate.isManaged = false;
    candidate.evidence =
      signal.broadGrantCount +
      ' broad object grant(s) detected — "View All"/"Modify All" on at least one object (configured threshold: ' +
      threshold.intValue() +
      '). ' +
      signal.broadGrantScore.explanation;
    candidate.measuredValue = signal.broadGrantCount + ' broad object grant(s)';
    candidate.expectedValue =
      '< ' +
      threshold.intValue() +
      ' broad object grant(s)';
    candidate.explanation = 'A "View All"/"Modify All Records" grant bypasses org-wide default and sharing-rule restrictions entirely for that object — it is a strictly stronger access level than any sharing rule can grant, so it deserves closer review the more objects it covers.';
    candidate.orgRisk =
      'Any user assigned ' +
      signal.label +
      ' can view or modify every record of ' +
      signal.broadGrantCount +
      ' object(s), regardless of ownership or sharing rules.';
    candidate.potentialImpact = 'Data exposure or unintended modification across records the assignee would not otherwise have access to under normal sharing.';
    candidate.remediation =
      'Confirm each broad grant on ' +
      signal.label +
      ' is intentional; prefer sharing rules or narrower object permissions where "View/Modify All" is not truly required.';
    candidate.validationSteps =
      'Re-run the Security Health scan after narrowing the grant and confirm the broad-grant count for ' +
      signal.label +
      ' has dropped below ' +
      threshold.intValue() +
      ', or that this finding no longer appears.';
    return candidate;
  }

  private OI_OrgHealthFindingCandidate buildSensitiveGrantCandidate(
    PermissionSetSignal signal
  ) {
    OI_OrgHealthFindingCandidate candidate = new OI_OrgHealthFindingCandidate();
    candidate.sectionKey = SECTION_KEY;
    candidate.ruleId = 'SecurityHealth.SensitiveObjectGrant';
    candidate.ruleVersion = 1;
    candidate.title =
      signal.label + ' grants broad access to a sensitive object';
    candidate.severityKey = signal.sensitiveGrantScore.severityKey;
    candidate.score = signal.sensitiveGrantScore.score;
    candidate.scoreExplanation = signal.sensitiveGrantScore.explanation;
    candidate.scoreContributorsJson = JSON.serialize(
      signal.sensitiveGrantScore.contributors
    );
    candidate.confidence = signal.assigneeCount != null &&
      signal.assigneeCount > 0
      ? 'High'
      : 'Medium';
    candidate.componentKey = String.valueOf(signal.permissionSetId);
    candidate.componentType = signal.isOwnedByProfile == true
      ? 'Profile'
      : 'Permission Set';
    candidate.componentLabel = signal.label;
    candidate.isManaged = false;
    candidate.evidence =
      signal.label +
      ' grants a broad object permission on a configured sensitive object (' +
      String.join(new List<String>(SENSITIVE_OBJECT_API_NAMES), ', ') +
      '), with ' +
      (signal.assigneeCount == null ? 0 : signal.assigneeCount) +
      ' active assignee(s). ' +
      signal.sensitiveGrantScore.explanation;
    candidate.measuredValue =
      (signal.assigneeCount == null ? 0 : signal.assigneeCount) +
      ' active assignee(s) holding a sensitive-object grant';
    candidate.expectedValue = '0 active assignees holding an unreviewed broad grant on a sensitive object';
    candidate.explanation = 'Contact and Account carry personal and business-relationship data — a broad "View All"/"Modify All" grant on either is real exposure only once it is actually held by an active user; with zero assignees it is a configuration-hygiene finding worth cleaning up before it is ever assigned.';
    candidate.orgRisk = signal.assigneeCount != null &&
      signal.assigneeCount > 0
      ? (signal.assigneeCount +
        ' active user(s) currently have broad access to every record of a sensitive object through ' +
        signal.label +
        '.')
      : signal.label +
        ' currently has no assignees, so this broad sensitive-object grant is not yet an active exposure — but will become one the moment it is assigned.';
    candidate.potentialImpact = 'Unreviewed broad access to PII/business-relationship data, and a larger surface for accidental or malicious data exposure the moment this Permission Set is assigned to anyone.';
    candidate.remediation =
      'Confirm this broad grant on a sensitive object is intentional and necessary for ' +
      signal.label +
      '\'s intended audience; narrow it or remove the grant if it is not.';
    candidate.validationSteps =
      'Re-run the Security Health scan after narrowing or removing the grant and confirm this finding no longer appears for ' +
      signal.label +
      '.';
    return candidate;
  }

  private List<PermissionSetSignal> buildSignals(
    List<PermissionSet> permissionSets,
    Map<Id, Integer> assigneeCountsByPsId,
    Map<Id, Integer> broadGrantCountByPsId,
    Set<Id> sensitiveGrantPsIds,
    Decimal elevatedThreshold,
    Decimal broadGrantThreshold
  ) {
    List<PermissionSetSignal> signals = new List<PermissionSetSignal>();
    for (PermissionSet permissionSet : permissionSets) {
      Integer assigneeCount = assigneeCountsByPsId.containsKey(permissionSet.Id)
        ? assigneeCountsByPsId.get(permissionSet.Id)
        : 0;
      Integer broadGrantCount = broadGrantCountByPsId.containsKey(
          permissionSet.Id
        )
        ? broadGrantCountByPsId.get(permissionSet.Id)
        : 0;
      Boolean hasSensitiveGrant = sensitiveGrantPsIds.contains(
        permissionSet.Id
      );
      signals.add(
        new PermissionSetSignal(
          permissionSet,
          broadGrantCount,
          hasSensitiveGrant,
          assigneeCount,
          elevatedThreshold,
          broadGrantThreshold,
          scoringEngine
        )
      );
    }
    return signals;
  }

  private void populateCoverage(
    OI_SecurityHealthDTO dto,
    Integer scannedCount,
    Integer ceiling
  ) {
    Boolean truncated = scannedCount >= ceiling;
    dto.isCoverageComplete = !truncated;
    dto.coverageNote = truncated
      ? scannedCount +
        ' permission sets & profiles scanned (ceiling reached — results may be incomplete)'
      : scannedCount +
        ' / ' +
        scannedCount +
        ' permission sets & profiles scanned';
  }

  private void populateKpiTiles(
    OI_SecurityHealthDTO dto,
    List<PermissionSetSignal> signals
  ) {
    Integer elevatedCount = 0;
    Integer broadGrantPsCount = 0;
    Integer sensitiveGrantCount = 0;
    Integer unassignedCustomCount = 0;
    for (PermissionSetSignal signal : signals) {
      if (signal.elevatedPermissionCount > 0) {
        elevatedCount++;
      }
      if (signal.broadGrantCount > 0) {
        broadGrantPsCount++;
      }
      if (signal.hasSensitiveGrant) {
        sensitiveGrantCount++;
      }
      if (signal.isOwnedByProfile != true && signal.assigneeCount == 0) {
        unassignedCustomCount++;
      }
    }

    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'Permission sets & profiles scanned',
        String.valueOf(signals.size())
      )
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'Elevated permission sets',
        String.valueOf(elevatedCount)
      )
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'Permission sets with broad grants',
        String.valueOf(broadGrantPsCount)
      )
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'Sensitive object grants',
        String.valueOf(sensitiveGrantCount)
      )
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'Unassigned custom permission sets',
        String.valueOf(unassignedCustomCount)
      )
    );
  }

  private void populateBreakdownAndHeatmap(
    OI_SecurityHealthDTO dto,
    List<PermissionSetSignal> signals
  ) {
    List<PermissionSetSignal> ranked = signals.clone();
    ranked.sort(new ByAttentionRank());

    dto.breakdownTitle = 'Permission sets needing attention';
    dto.metricColumnLabels = new List<String>{
      'Elevated perms',
      'Broad grants'
    };
    Integer breakdownCount = Math.min(BREAKDOWN_ROW_LIMIT, ranked.size());
    dto.breakdownCoverageCaption =
      'Top ' +
      breakdownCount +
      ' of ' +
      signals.size();
    for (Integer i = 0; i < breakdownCount; i++) {
      PermissionSetSignal signal = ranked[i];
      OI_HealthBreakdownRowDTO row = new OI_HealthBreakdownRowDTO();
      row.key = String.valueOf(signal.permissionSetId);
      row.primaryLabel = signal.label;
      row.metricValues.add(
        new OI_HealthMetricValueDTO(
          'elevated',
          String.valueOf(signal.elevatedPermissionCount)
        )
      );
      row.metricValues.add(
        new OI_HealthMetricValueDTO(
          'broadGrants',
          String.valueOf(signal.broadGrantCount)
        )
      );
      row.severityKey = signal.severityKey;
      row.severityLabel = signal.severityKey;
      dto.breakdownRows.add(row);
    }

    dto.heatmapColumnLabels = new List<String>{
      'Elevated',
      'Broad grants',
      'Sensitive'
    };
    Integer heatmapCount = Math.min(HEATMAP_ROW_LIMIT, ranked.size());
    for (Integer i = 0; i < heatmapCount; i++) {
      PermissionSetSignal signal = ranked[i];
      OI_HealthHeatmapRowDTO row = new OI_HealthHeatmapRowDTO();
      row.rowLabel = signal.label;
      row.cells.add(
        new OI_HealthMetricValueDTO(
          'elevated',
          String.valueOf(signal.elevatedPermissionCount),
          signal.elevatedScore.severityKey
        )
      );
      row.cells.add(
        new OI_HealthMetricValueDTO(
          'broadGrants',
          String.valueOf(signal.broadGrantCount),
          signal.broadGrantScore.severityKey
        )
      );
      row.cells.add(
        new OI_HealthMetricValueDTO(
          'sensitive',
          signal.hasSensitiveGrant ? 'Y' : 'N',
          signal.hasSensitiveGrant
            ? signal.sensitiveGrantScore.severityKey
            : 'Good'
        )
      );
      dto.heatmapRows.add(row);
    }
  }

  private Decimal loadThreshold(String metricKey, Decimal fallback) {
    for (
      OI_Org_Health_Metric_Config__mdt row : OI_Org_Health_Metric_Config__mdt.getAll()
        .values()
    ) {
      if (
        row.Section_Key__c == SECTION_KEY &&
        row.Metric_Key__c == metricKey &&
        row.Is_Active__c == true &&
        row.Threshold_Value__c != null
      ) {
        return row.Threshold_Value__c;
      }
    }
    return fallback;
  }

  private Integer loadCeiling() {
    OI_Org_Health_Section_Config__mdt config = OI_Org_Health_Section_Config__mdt.getInstance(
      SECTION_KEY
    );
    if (config != null && config.Live_Row_Ceiling__c != null) {
      return config.Live_Row_Ceiling__c.intValue();
    }
    return DEFAULT_CEILING;
  }

  /** Sorts worst-first: sensitive-object grants first, then Critical before Warning before Good, then by combined elevated/broad-grant count within a tier. */
  private class ByAttentionRank implements Comparator<PermissionSetSignal> {
    public Integer compare(PermissionSetSignal a, PermissionSetSignal b) {
      Integer sensitiveRankA = a.hasSensitiveGrant ? 0 : 1;
      Integer sensitiveRankB = b.hasSensitiveGrant ? 0 : 1;
      if (sensitiveRankA != sensitiveRankB) {
        return sensitiveRankA - sensitiveRankB;
      }
      Integer rankA = severityRank(a.severityKey);
      Integer rankB = severityRank(b.severityKey);
      if (rankA != rankB) {
        return rankA - rankB;
      }
      return (b.elevatedPermissionCount + b.broadGrantCount) -
        (a.elevatedPermissionCount + a.broadGrantCount);
    }
  }

  private static Integer severityRank(String severityKey) {
    if (severityKey == 'Critical') {
      return 0;
    }
    if (severityKey == 'Warning') {
      return 1;
    }
    return 2;
  }

  private static String worstOf(String a, String b, String c) {
    if (a == 'Critical' || b == 'Critical' || c == 'Critical') {
      return 'Critical';
    }
    if (a == 'Warning' || b == 'Warning' || c == 'Warning') {
      return 'Warning';
    }
    return 'Good';
  }

  /**
   * The curated, fixed set of seven administrative system permissions this v1 checks — see
   * class doc Limitations. Deliberately takes an in-memory PermissionSet rather than an Id:
   * several of these fields (Modify All Data especially) carry large FIELD_INTEGRITY_EXCEPTION
   * dependency chains when actually inserted/updated via DML, so this method — and its test —
   * only ever reads a constructed-but-never-persisted PermissionSet.
   */
  @TestVisible
  private static Integer countElevatedPermissions(PermissionSet permissionSet) {
    Integer count = 0;
    if (permissionSet.PermissionsModifyAllData == true) {
      count++;
    }
    if (permissionSet.PermissionsViewAllData == true) {
      count++;
    }
    if (permissionSet.PermissionsAuthorApex == true) {
      count++;
    }
    if (permissionSet.PermissionsManageUsers == true) {
      count++;
    }
    if (permissionSet.PermissionsCustomizeApplication == true) {
      count++;
    }
    if (permissionSet.PermissionsManageSharing == true) {
      count++;
    }
    if (permissionSet.PermissionsResetPasswords == true) {
      count++;
    }
    return count;
  }

  /** One Permission Set's (or profile shadow row's) computed evidence signal — an internal working shape, never returned directly. */
  private class PermissionSetSignal {
    Id permissionSetId;
    String label;
    Boolean isOwnedByProfile;
    Integer elevatedPermissionCount;
    Integer broadGrantCount;
    Boolean hasSensitiveGrant;
    Integer assigneeCount;
    OI_HealthScoreResult elevatedScore;
    OI_HealthScoreResult broadGrantScore;
    OI_HealthScoreResult sensitiveGrantScore;
    String severityKey;

    PermissionSetSignal(
      PermissionSet permissionSet,
      Integer broadGrantCount,
      Boolean hasSensitiveGrant,
      Integer assigneeCount,
      Decimal elevatedThreshold,
      Decimal broadGrantThreshold,
      OI_HealthScoringEngine scoringEngine
    ) {
      this.permissionSetId = permissionSet.Id;
      this.label = String.isBlank(permissionSet.Label)
        ? permissionSet.Name
        : permissionSet.Label;
      this.isOwnedByProfile = permissionSet.IsOwnedByProfile;
      this.elevatedPermissionCount = countElevatedPermissions(permissionSet);
      this.broadGrantCount = broadGrantCount;
      this.hasSensitiveGrant = hasSensitiveGrant;
      this.assigneeCount = assigneeCount;

      this.elevatedScore = scoringEngine.score(
        new List<OI_HealthSignal>{
          elevatedSignal(this.elevatedPermissionCount, elevatedThreshold)
        }
      );
      this.broadGrantScore = scoringEngine.score(
        new List<OI_HealthSignal>{
          broadGrantSignal(broadGrantCount, broadGrantThreshold)
        }
      );
      this.sensitiveGrantScore = scoringEngine.score(
        new List<OI_HealthSignal>{
          sensitiveGrantSignal(hasSensitiveGrant, assigneeCount)
        }
      );

      /**
       * Each of the three rules is scored independently (its own OI_HealthScoreResult, not
       * summed into one) — mirrors Automation/Code Health's identical pattern — so a
       * Permission Set breaching more than one rule at once correctly ranks at the worst of
       * the three, never double-counted into an inflated single score.
       */
      this.severityKey = worstOf(
        elevatedScore.severityKey,
        broadGrantScore.severityKey,
        hasSensitiveGrant ? sensitiveGrantScore.severityKey : 'Good'
      );
    }

    private OI_HealthSignal elevatedSignal(Integer count, Decimal threshold) {
      OI_HealthSignal signal = new OI_HealthSignal(
        'ElevatedPermissions',
        'Elevated system permissions',
        PRIMARY_SIGNAL_WEIGHT,
        threshold > 0 ? Decimal.valueOf(count) / threshold : 0,
        count +
          ' of 7 curated elevated system permission(s) vs. threshold ' +
          threshold.intValue()
      );
      signal.confidence = 0.8;
      return signal;
    }

    private OI_HealthSignal broadGrantSignal(Integer count, Decimal threshold) {
      OI_HealthSignal signal = new OI_HealthSignal(
        'BroadObjectGrant',
        'Broad object grants (view/modify all records)',
        PRIMARY_SIGNAL_WEIGHT,
        threshold > 0 ? Decimal.valueOf(count) / threshold : 0,
        count + ' broad object grant(s) vs. threshold ' + threshold.intValue()
      );
      signal.confidence = 0.8;
      return signal;
    }

    /**
     * A sensitive-object grant only reaches Critical when it is corroborated by real
     * exposure — at least one active assignee actually holding it. The grant's own existence
     * is a certain fact (confidence 1.0), but exposureMultiplier is halved with zero
     * assignees so the signal caps at Warning rather than fabricating Critical from
     * configuration alone (ProductSpecs.md's "severity requires context such as ... affected
     * users, active assignments," and "never mark Critical based only on the number of
     * grants").
     */
    private OI_HealthSignal sensitiveGrantSignal(
      Boolean hasSensitiveGrant,
      Integer assigneeCount
    ) {
      OI_HealthSignal signal = new OI_HealthSignal(
        'SensitiveObjectGrant',
        'Broad grant on a sensitive object',
        PRIMARY_SIGNAL_WEIGHT,
        hasSensitiveGrant == true ? 1.5 : 0,
        hasSensitiveGrant == true
          ? 'Broad grant detected on a sensitive object (' +
            String.join(new List<String>(SENSITIVE_OBJECT_API_NAMES), ', ') +
            ')'
          : 'No sensitive-object grant detected'
      );
      signal.confidence = 1.0;
      signal.exposureMultiplier = (assigneeCount != null &&
        assigneeCount > 0)
        ? 1.0
        : 0.5;
      return signal;
    }
  }
}
