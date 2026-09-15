/**
 * Purpose: The only component that reads or writes OI_Org_Health_Finding__c (ADR-0027) — the
 *          unified finding's identity-stable persistence layer, matching the self-contained
 *          Repository-per-object pattern OI_OrgHealthSnapshotRepository/OI_ImpactCacheRepository
 *          already establish.
 * Responsibilities: Compute the stable Fingerprint__c for a (sectionKey, ruleId, componentKey)
 *                    triple; upsert a scan's candidate findings by that fingerprint without ever
 *                    overwriting a finding's lifecycle fields (Status__c, OwnerId, Due_Date__c,
 *                    Notes__c, Compensating_Control__c, Resolution_Evidence__c); auto-resolve
 *                    findings a re-scan no longer detects, preserving their history rather than
 *                    deleting them; apply an administrator's explicit status/ownership edits; and
 *                    (ADR-0027 lifecycle extension) serve the Remediation Management workspace's
 *                    cross-section filtered/sorted/paginated queue query plus its org-wide
 *                    summary aggregates (getFindingsByFilter, getFindingsCountByFilter,
 *                    getOpenCountsBySeverity/Status/Section, getExpiringRiskAcceptanceCount,
 *                    getOverdueCount, getTotalOpenCount).
 * Dependencies: OI_Org_Health_Finding__c, OI_HashUtil, OI_OrgHealthFindingCandidate,
 *               OI_RemediationFilterDTO.
 * Limitations: with sharing — findings are real, owner-assignable business records (not an
 *              internal computation cache like OI_Org_Health_Snapshot__c), so normal record
 *              sharing applies; CRUD/FLS on the object itself is enforced by the calling
 *              Controller's permission-set-driven object/field grants, not re-checked here
 *              (CodingStandards.md §1 Repository role — Repositories abstract data access,
 *              they are not the security boundary).
 */
public with sharing class OI_OrgHealthFindingRepository {
  /** Statuses that mean "this condition is confirmed to no longer be true" — recurrence of the same fingerprint invalidates that claim and must reopen the finding. Risk Accepted/False Positive are judgments about the condition itself, not claims that it disappeared, so recurrence never reopens those. */
  private static final Set<String> REOPENABLE_ON_RECURRENCE_STATUSES = new Set<String>{
    'Resolved'
  };
  private static final Set<String> TERMINAL_STATUSES = new Set<String>{
    'Resolved',
    'False Positive'
  };

  private static final String FIELDS_SOQL =
    'Id, Fingerprint__c, Section_Key__c, Rule_Id__c, Rule_Version__c, Title__c, Severity__c, Score__c, ' +
    'Score_Explanation__c, Severity_Contributors_Json__c, Confidence__c, ' +
    'Component_Key__c, Component_Type__c, Component_Label__c, Namespace__c, Is_Managed__c, Evidence__c, ' +
    'Measured_Value__c, Expected_Value__c, Explanation__c, Org_Risk__c, Potential_Impact__c, Remediation__c, ' +
    'Validation_Steps__c, First_Detected__c, Last_Detected__c, Status__c, OwnerId, Owner.Name, Due_Date__c, Notes__c, ' +
    'Compensating_Control__c, Resolution_Evidence__c, Resolved_Date__c, Risk_Acceptance_Expiry__c, ' +
    'False_Positive_Justification__c, Compute_Run_Id__c, Has_Automatic_Action__c, Required_Permission__c';

  /**
   * The Remediation Management workspace's allow-listed sort keys (ADR-0027 lifecycle
   * extension) — a friendly key from the client maps to a real field here; a client can never
   * inject an arbitrary ORDER BY expression, since only these exact field names are ever
   * concatenated into a query string. Severity_Rank__c (Critical=0, Warning=1, Good=2) is a
   * formula field purpose-built for this sort — Severity__c itself sorts alphabetically
   * (Critical, Good, Warning), which puts Good ahead of Warning and would misorder the queue.
   */
  @TestVisible
  private static final Map<String, String> SORTABLE_FIELDS = new Map<String, String>{
    'severity' => 'Severity_Rank__c',
    'status' => 'Status__c',
    'lastDetected' => 'Last_Detected__c',
    'firstDetected' => 'First_Detected__c',
    'dueDate' => 'Due_Date__c',
    'score' => 'Score__c',
    'title' => 'Title__c'
  };
  private static final String DEFAULT_SORT_FIELD = 'Severity_Rank__c';
  @TestVisible
  private static final Integer RISK_ACCEPTANCE_EXPIRY_LOOKAHEAD_DAYS = 30;
  private static final Integer MAX_PAGE_SIZE = 100;
  private static final Integer DEFAULT_PAGE_SIZE = 25;
  /** SOQL's own hard OFFSET ceiling — a page request beyond this is clamped rather than erroring, since a workspace user paging this deep should narrow their filter instead. */
  private static final Integer MAX_OFFSET = 2000;

  public String computeFingerprint(
    String sectionKey,
    String ruleId,
    String componentKey
  ) {
    return OI_HashUtil.hash(
      (sectionKey == null ? '' : sectionKey) +
        '::' +
        (ruleId == null ? '' : ruleId) +
        '::' +
        (componentKey == null ? '' : componentKey)
    );
  }

  /**
   * Upserts one scan's worth of candidates for a single section, keyed by fingerprint. A
   * fingerprint not seen before is inserted as a brand-new Open finding; one already on file
   * has its evidence/severity fields refreshed in place, its lifecycle fields left completely
   * untouched — except a Resolved finding whose condition recurs, which reopens (see class
   * doc). Returns the fingerprint set actually written, so the caller can pass it straight to
   * resolveMissingFindings.
   */
  public Set<String> upsertCandidates(
    List<OI_OrgHealthFindingCandidate> candidates,
    String computeRunId,
    Datetime runTimestamp
  ) {
    Set<String> fingerprints = new Set<String>();
    if (candidates == null || candidates.isEmpty()) {
      return fingerprints;
    }

    Map<String, OI_OrgHealthFindingCandidate> candidateByFingerprint = new Map<String, OI_OrgHealthFindingCandidate>();
    for (OI_OrgHealthFindingCandidate candidate : candidates) {
      String fingerprint = computeFingerprint(
        candidate.sectionKey,
        candidate.ruleId,
        candidate.componentKey
      );
      fingerprints.add(fingerprint);
      candidateByFingerprint.put(fingerprint, candidate);
    }

    Map<String, OI_Org_Health_Finding__c> existingByFingerprint = new Map<String, OI_Org_Health_Finding__c>();
    for (
      OI_Org_Health_Finding__c existing : Database.query(
        'SELECT ' +
          FIELDS_SOQL +
          ' FROM OI_Org_Health_Finding__c WHERE Fingerprint__c IN :fingerprints'
      )
    ) {
      existingByFingerprint.put(existing.Fingerprint__c, existing);
    }

    List<OI_Org_Health_Finding__c> toUpsert = new List<OI_Org_Health_Finding__c>();
    for (String fingerprint : candidateByFingerprint.keySet()) {
      OI_OrgHealthFindingCandidate candidate = candidateByFingerprint.get(
        fingerprint
      );
      OI_Org_Health_Finding__c existing = existingByFingerprint.get(
        fingerprint
      );
      toUpsert.add(
        mergeCandidateOntoRecord(
          fingerprint,
          candidate,
          existing,
          computeRunId,
          runTimestamp
        )
      );
    }
    upsert toUpsert OI_Org_Health_Finding__c.Fingerprint__c;
    return fingerprints;
  }

  private OI_Org_Health_Finding__c mergeCandidateOntoRecord(
    String fingerprint,
    OI_OrgHealthFindingCandidate candidate,
    OI_Org_Health_Finding__c existing,
    String computeRunId,
    Datetime runTimestamp
  ) {
    OI_Org_Health_Finding__c record = new OI_Org_Health_Finding__c(
      Fingerprint__c = fingerprint,
      Section_Key__c = candidate.sectionKey,
      Rule_Id__c = candidate.ruleId,
      Rule_Version__c = candidate.ruleVersion,
      Title__c = candidate.title,
      Severity__c = candidate.severityKey,
      Score__c = candidate.score,
      Score_Explanation__c = candidate.scoreExplanation,
      Severity_Contributors_Json__c = candidate.scoreContributorsJson,
      Confidence__c = candidate.confidence,
      Component_Key__c = candidate.componentKey,
      Component_Type__c = candidate.componentType,
      Component_Label__c = candidate.componentLabel,
      Namespace__c = candidate.namespace,
      Is_Managed__c = candidate.isManaged == true,
      Evidence__c = candidate.evidence,
      Measured_Value__c = candidate.measuredValue,
      Expected_Value__c = candidate.expectedValue,
      Explanation__c = candidate.explanation,
      Org_Risk__c = candidate.orgRisk,
      Potential_Impact__c = candidate.potentialImpact,
      Remediation__c = candidate.remediation,
      Validation_Steps__c = candidate.validationSteps,
      Last_Detected__c = runTimestamp,
      Compute_Run_Id__c = computeRunId
    );

    if (existing == null) {
      record.First_Detected__c = runTimestamp;
      record.Status__c = 'Open';
      return record;
    }

    record.Id = existing.Id;
    record.First_Detected__c = existing.First_Detected__c;
    if (REOPENABLE_ON_RECURRENCE_STATUSES.contains(existing.Status__c)) {
      record.Status__c = 'Open';
      record.Resolution_Evidence__c =
        'Automatically reopened — this condition was previously resolved but was detected again in run ' +
        computeRunId +
        ' at ' +
        runTimestamp.format() +
        '.';
      /** No longer true that this finding is resolved — clearing keeps Resolved_Date__c meaning exactly "the last time Status__c actually became Resolved and has stayed that way since," never a stale date from a resolution recurrence has since disproved. */
      record.Resolved_Date__c = null;
    }
    // Any other status (Open, Acknowledged, In Progress, Risk Accepted, False Positive) is
    // left exactly as the administrator set it — only the fields assigned above change.
    return record;
  }

  /**
   * Marks every non-terminal finding in this section whose fingerprint was NOT part of the
   * current scan as Resolved — the condition is gone, so its history is preserved rather than
   * deleted (ProductSpecs.md: "when a finding disappears, mark it resolved rather than
   * deleting its history"). Already-terminal findings (Resolved, False Positive) are left
   * alone; Risk Accepted findings ARE auto-resolved here, since a disappeared condition means
   * there is nothing left to accept risk on.
   */
  public Integer resolveMissingFindings(
    String sectionKey,
    Set<String> stillPresentFingerprints,
    String computeRunId,
    Datetime runTimestamp
  ) {
    if (String.isBlank(sectionKey)) {
      return 0;
    }
    Set<String> presentFingerprints = stillPresentFingerprints == null
      ? new Set<String>()
      : stillPresentFingerprints;
    List<OI_Org_Health_Finding__c> toResolve = new List<OI_Org_Health_Finding__c>();
    for (OI_Org_Health_Finding__c finding : [
      SELECT Id, Fingerprint__c, Status__c
      FROM OI_Org_Health_Finding__c
      WHERE Section_Key__c = :sectionKey AND Status__c NOT IN :TERMINAL_STATUSES
    ]) {
      if (!presentFingerprints.contains(finding.Fingerprint__c)) {
        toResolve.add(
          new OI_Org_Health_Finding__c(
            Id = finding.Id,
            Status__c = 'Resolved',
            Resolution_Evidence__c = 'Automatically resolved — condition no longer detected in scan run ' +
              computeRunId +
              ' at ' +
              runTimestamp.format() +
              '.',
            Resolved_Date__c = runTimestamp
          )
        );
      }
    }
    if (!toResolve.isEmpty()) {
      update toResolve;
    }
    return toResolve.size();
  }

  public List<OI_Org_Health_Finding__c> getBySectionKey(String sectionKey) {
    if (String.isBlank(sectionKey)) {
      return new List<OI_Org_Health_Finding__c>();
    }
    return Database.query(
      'SELECT ' +
        FIELDS_SOQL +
        ' FROM OI_Org_Health_Finding__c WHERE Section_Key__c = :sectionKey ORDER BY Severity__c ASC, Last_Detected__c DESC'
    );
  }

  /**
   * Applies an administrator's explicit edit to exactly the fields provided — an sObject with
   * only Id plus the assigned fields set touches only those columns on UPDATE, so omitted
   * parameters (passed as null) never clobber existing values. status is validated against
   * the picklist's own value set by the Service layer before this is called. Resolved_Date__c
   * is derived, never caller-supplied: stamped the moment status becomes Resolved, cleared the
   * moment it becomes anything else, so it always means exactly "currently Resolved since."
   */
  public void updateStatus(
    Id findingId,
    String status,
    String notes,
    Date dueDate,
    Id ownerId,
    String compensatingControl,
    Date riskAcceptanceExpiry,
    String falsePositiveJustification
  ) {
    OI_Org_Health_Finding__c record = new OI_Org_Health_Finding__c(
      Id = findingId
    );
    if (String.isNotBlank(status)) {
      record.Status__c = status;
      record.Resolved_Date__c = status == 'Resolved' ? Datetime.now() : null;
    }
    if (notes != null) {
      record.Notes__c = notes;
    }
    if (dueDate != null) {
      record.Due_Date__c = dueDate;
    }
    if (ownerId != null) {
      record.OwnerId = ownerId;
    }
    if (compensatingControl != null) {
      record.Compensating_Control__c = compensatingControl;
    }
    if (riskAcceptanceExpiry != null) {
      record.Risk_Acceptance_Expiry__c = riskAcceptanceExpiry;
    }
    if (falsePositiveJustification != null) {
      record.False_Positive_Justification__c = falsePositiveJustification;
    }
    update record;
  }

  /** Other findings sharing the same affected component, excluding the finding itself — computed on demand from existing indexed fields rather than a maintained many-to-many junction object, so it can never drift stale (ADR-0027 lifecycle extension). */
  public List<OI_Org_Health_Finding__c> getRelatedByComponentKey(
    String componentKey,
    Id excludeFindingId
  ) {
    if (String.isBlank(componentKey)) {
      return new List<OI_Org_Health_Finding__c>();
    }
    return Database.query(
      'SELECT ' +
        FIELDS_SOQL +
        ' FROM OI_Org_Health_Finding__c WHERE Component_Key__c = :componentKey AND Id != :excludeFindingId ORDER BY Severity__c ASC, Last_Detected__c DESC LIMIT 20'
    );
  }

  /**
   * The Remediation Management workspace's cross-section queue — one bounded, filtered,
   * sorted, paginated query across every section at once (ADR-0027 lifecycle extension:
   * "a shared remediation workspace, explicitly on this package's roadmap"). Every filter
   * value is passed as a bind variable via Database.queryWithBinds, never concatenated into
   * the query text, so no filter value (including free-text search) can alter the query's
   * shape — only which of the fixed, hardcoded WHERE clauses above are included does that.
   */
  public List<OI_Org_Health_Finding__c> getFindingsByFilter(
    OI_RemediationFilterDTO filter
  ) {
    Map<String, Object> binds = new Map<String, Object>();
    String whereClause = buildWhereClause(filter, binds);
    binds.put('pageLimit', resolvePageSize(filter));
    binds.put('pageOffset', resolveOffset(filter));
    String query =
      'SELECT ' +
      FIELDS_SOQL +
      ' FROM OI_Org_Health_Finding__c' +
      whereClause +
      buildOrderByClause(filter) +
      ' LIMIT :pageLimit OFFSET :pageOffset';
    return (List<OI_Org_Health_Finding__c>) Database.queryWithBinds(
      query,
      binds,
      AccessLevel.SYSTEM_MODE
    );
  }

  /**
   * The workspace's CSV export action — every row matching the filter (ignoring its own
   * pageSize/pageNumber, which govern only the interactive table's page), up to MAX_OFFSET
   * rows in one shot. A separate method rather than reusing getFindingsByFilter with a larger
   * pageSize: the interactive page size is deliberately capped at MAX_PAGE_SIZE for table UX,
   * which export must not be limited by.
   */
  public List<OI_Org_Health_Finding__c> getFindingsForExport(
    OI_RemediationFilterDTO filter
  ) {
    Map<String, Object> binds = new Map<String, Object>();
    String whereClause = buildWhereClause(filter, binds);
    binds.put('exportLimit', MAX_OFFSET);
    String query =
      'SELECT ' +
      FIELDS_SOQL +
      ' FROM OI_Org_Health_Finding__c' +
      whereClause +
      buildOrderByClause(filter) +
      ' LIMIT :exportLimit';
    return (List<OI_Org_Health_Finding__c>) Database.queryWithBinds(
      query,
      binds,
      AccessLevel.SYSTEM_MODE
    );
  }

  /** The total row count matching the same filter getFindingsByFilter uses — a second, LIMIT/OFFSET-free query, since Database.countQuery cannot itself be paginated. */
  public Integer getFindingsCountByFilter(OI_RemediationFilterDTO filter) {
    Map<String, Object> binds = new Map<String, Object>();
    String whereClause = buildWhereClause(filter, binds);
    String query = 'SELECT COUNT() FROM OI_Org_Health_Finding__c' + whereClause;
    return Database.countQueryWithBinds(query, binds, AccessLevel.SYSTEM_MODE);
  }

  /** Org-wide counts by severity, among non-terminal (still-open-work) findings — the summary strip's severity breakdown, independent of whatever page/filter the queue table is showing. */
  public List<AggregateResult> getOpenCountsBySeverity() {
    return [
      SELECT Severity__c sev, COUNT(Id) total
      FROM OI_Org_Health_Finding__c
      WHERE Status__c NOT IN :TERMINAL_STATUSES
      GROUP BY Severity__c
    ];
  }

  /** Org-wide counts by status, including terminal ones — the summary strip's status breakdown, the one view where Resolved/False Positive volume matters (proof remediation is happening). */
  public List<AggregateResult> getCountsByStatus() {
    return [
      SELECT Status__c stat, COUNT(Id) total
      FROM OI_Org_Health_Finding__c
      GROUP BY Status__c
    ];
  }

  /** Org-wide counts by section, among non-terminal findings — which section has the most open work right now. */
  public List<AggregateResult> getOpenCountsBySection() {
    return [
      SELECT Section_Key__c sec, COUNT(Id) total
      FROM OI_Org_Health_Finding__c
      WHERE Status__c NOT IN :TERMINAL_STATUSES
      GROUP BY Section_Key__c
    ];
  }

  /** Risk Accepted findings whose Risk_Acceptance_Expiry__c is within the lookahead window (including already past it) — a review prompt, per Risk_Acceptance_Expiry__c's own field doc. */
  public Integer getExpiringRiskAcceptanceCount() {
    Date lookaheadDate = Date.today()
      .addDays(RISK_ACCEPTANCE_EXPIRY_LOOKAHEAD_DAYS);
    return [
      SELECT COUNT()
      FROM OI_Org_Health_Finding__c
      WHERE
        Status__c = 'Risk Accepted'
        AND Risk_Acceptance_Expiry__c != NULL
        AND Risk_Acceptance_Expiry__c <= :lookaheadDate
    ];
  }

  /** Non-terminal findings whose Due_Date__c has passed — an administrator's own triage commitment that has slipped. */
  public Integer getOverdueCount() {
    Date todayDate = Date.today();
    return [
      SELECT COUNT()
      FROM OI_Org_Health_Finding__c
      WHERE
        Due_Date__c != NULL
        AND Due_Date__c < :todayDate
        AND Status__c NOT IN :TERMINAL_STATUSES
    ];
  }

  /** Every non-terminal finding, regardless of section/severity/status filter — the summary strip's headline number. */
  public Integer getTotalOpenCount() {
    return [
      SELECT COUNT()
      FROM OI_Org_Health_Finding__c
      WHERE Status__c NOT IN :TERMINAL_STATUSES
    ];
  }

  private String buildWhereClause(
    OI_RemediationFilterDTO filter,
    Map<String, Object> binds
  ) {
    if (filter == null) {
      return '';
    }
    List<String> clauses = new List<String>();
    if (filter.sectionKeys != null && !filter.sectionKeys.isEmpty()) {
      clauses.add('Section_Key__c IN :sectionKeys');
      binds.put('sectionKeys', filter.sectionKeys);
    }
    if (filter.severityKeys != null && !filter.severityKeys.isEmpty()) {
      clauses.add('Severity__c IN :severityKeys');
      binds.put('severityKeys', filter.severityKeys);
    }
    if (filter.statuses != null && !filter.statuses.isEmpty()) {
      clauses.add('Status__c IN :statuses');
      binds.put('statuses', filter.statuses);
    }
    if (filter.ownerId != null) {
      clauses.add('OwnerId = :ownerId');
      binds.put('ownerId', filter.ownerId);
    }
    if (String.isNotBlank(filter.searchText)) {
      /** Evidence__c/Explanation__c etc. are Long Text Area — Salesforce does not allow filtering (including LIKE) on that field type at all, so the search box is scoped to the two plain Text fields a finding row is actually labeled by. */
      clauses.add(
        '(Title__c LIKE :searchPattern OR Component_Label__c LIKE :searchPattern)'
      );
      binds.put(
        'searchPattern',
        '%' + escapeLikeWildcards(filter.searchText.trim()) + '%'
      );
    }
    if (filter.onlyExpiringRiskAcceptance == true) {
      clauses.add(
        'Status__c = \'Risk Accepted\' AND Risk_Acceptance_Expiry__c != null AND Risk_Acceptance_Expiry__c <= :riskAcceptanceLookaheadDate'
      );
      binds.put(
        'riskAcceptanceLookaheadDate',
        Date.today().addDays(RISK_ACCEPTANCE_EXPIRY_LOOKAHEAD_DAYS)
      );
    }
    if (filter.onlyOverdue == true) {
      clauses.add(
        'Due_Date__c != null AND Due_Date__c < :todayDate AND Status__c NOT IN :overdueExcludedStatuses'
      );
      binds.put('todayDate', Date.today());
      binds.put('overdueExcludedStatuses', TERMINAL_STATUSES);
    }
    return clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND ');
  }

  /** A literal substring search, not a wildcard pattern — a search box user typing "50%" or "Account_Name" expects those characters matched literally, not interpreted as SOQL LIKE wildcards. */
  @TestVisible
  private String escapeLikeWildcards(String rawText) {
    return rawText.replace('\\', '\\\\')
      .replace('%', '\\%')
      .replace('_', '\\_');
  }

  private String buildOrderByClause(OI_RemediationFilterDTO filter) {
    String field = resolveSortField(filter);
    Boolean isDefaultField = field == DEFAULT_SORT_FIELD;
    String direction = resolveSortDirection(filter, isDefaultField);
    String tiebreak = isDefaultField ? ', Last_Detected__c DESC' : '';
    return ' ORDER BY ' + field + ' ' + direction + tiebreak;
  }

  private String resolveSortField(OI_RemediationFilterDTO filter) {
    String sortField = filter == null ? null : filter.sortField;
    if (String.isBlank(sortField) || !SORTABLE_FIELDS.containsKey(sortField)) {
      return DEFAULT_SORT_FIELD;
    }
    return SORTABLE_FIELDS.get(sortField);
  }

  /** Worst-first (ascending Severity_Rank__c) is the natural default; every other sortable field defaults to descending (newest/highest first) unless the caller says otherwise. */
  private String resolveSortDirection(
    OI_RemediationFilterDTO filter,
    Boolean isDefaultField
  ) {
    String direction = filter == null ? null : filter.sortDirection;
    if (direction == 'ASC' || direction == 'DESC') {
      return direction;
    }
    return isDefaultField ? 'ASC' : 'DESC';
  }

  private Integer resolvePageSize(OI_RemediationFilterDTO filter) {
    Integer pageSize = filter == null ? null : filter.pageSize;
    if (pageSize == null || pageSize <= 0) {
      return DEFAULT_PAGE_SIZE;
    }
    return Math.min(pageSize, MAX_PAGE_SIZE);
  }

  private Integer resolvePageNumber(OI_RemediationFilterDTO filter) {
    Integer pageNumber = filter == null ? null : filter.pageNumber;
    return pageNumber == null || pageNumber < 1 ? 1 : pageNumber;
  }

  private Integer resolveOffset(OI_RemediationFilterDTO filter) {
    Integer offset = (resolvePageNumber(filter) - 1) * resolvePageSize(filter);
    return Math.min(offset, MAX_OFFSET);
  }
}
