/**
 * Purpose: The unified finding model's business-logic layer (ADR-0027) — the one place a
 *          domain Health Service's candidates become persisted, identity-stable findings, and
 *          the one place an administrator's status edit is validated before it reaches the
 *          Repository. Also the Remediation Management workspace's business-logic layer
 *          (ADR-0027 lifecycle extension) — the cross-section queue, its summary metrics, its
 *          CSV export, and one finding's audit-trail history.
 * Responsibilities: sync(sectionKey, candidates, computeRunId) — upsert this scan's candidates
 *                    and auto-resolve whatever the scan no longer detected, as one atomic unit
 *                    of work; getFindingsForSection(sectionKey) — the drawer/list read path;
 *                    updateStatus(...) — validate the requested status against the finding's
 *                    real lifecycle before writing it; getRemediationQueue(filter) — the
 *                    workspace's paginated cross-section table; getRemediationSummary() — its
 *                    metrics strip; exportRemediationQueue(filter) — every matching row for a
 *                    client-side CSV download; getFindingHistory(findingId) — one finding's
 *                    native Field History Tracking timeline.
 * Dependencies: OI_OrgHealthFindingRepository, OI_OrgHealthFindingHistorySelector,
 *               OI_Org_Health_Section_Config__mdt.
 * Limitations: Permission enforcement (OI_View_Org_Health / OI_Run_Org_Health_Compute /
 *              OI_Manage_Finding_Workflow) is the calling Controller's responsibility
 *              (OI_OrgHealthController already asserts a custom permission before calling any
 *              method here), matching every other Org Health Service in this package.
 */
public with sharing class OI_OrgHealthFindingService {
  @TestVisible
  private static final Set<String> VALID_STATUSES = new Set<String>{
    'Open',
    'Acknowledged',
    'In Progress',
    'Risk Accepted',
    'Resolved',
    'False Positive'
  };

  private final OI_OrgHealthFindingRepository repository;
  private final OI_OrgHealthFindingHistorySelector historySelector;

  public OI_OrgHealthFindingService() {
    this(
      new OI_OrgHealthFindingRepository(),
      new OI_OrgHealthFindingHistorySelector()
    );
  }

  public OI_OrgHealthFindingService(
    OI_OrgHealthFindingRepository repository,
    OI_OrgHealthFindingHistorySelector historySelector
  ) {
    this.repository = repository;
    this.historySelector = historySelector;
  }

  /**
   * Upserts one scan's candidates and resolves whatever this section previously had open that
   * the scan no longer detected — the two halves of "a finding's identity and status survive
   * across scans" (ProductSpecs.md). computeRunId ties both halves to the same run for the
   * historical-comparison view.
   */
  public void sync(
    String sectionKey,
    List<OI_OrgHealthFindingCandidate> candidates,
    String computeRunId
  ) {
    Datetime runTimestamp = Datetime.now();
    Set<String> presentFingerprints = repository.upsertCandidates(
      candidates,
      computeRunId,
      runTimestamp
    );
    repository.resolveMissingFindings(
      sectionKey,
      presentFingerprints,
      computeRunId,
      runTimestamp
    );
  }

  public List<OI_OrgHealthFindingDTO> getFindingsForSection(String sectionKey) {
    List<OI_OrgHealthFindingDTO> results = new List<OI_OrgHealthFindingDTO>();
    for (
      OI_Org_Health_Finding__c record : repository.getBySectionKey(sectionKey)
    ) {
      results.add(toDTO(record));
    }
    return results;
  }

  /** Rejects a status outside the finding's own defined lifecycle before it ever reaches the Repository — defense in depth alongside the field's own restricted Picklist. */
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
    if (findingId == null) {
      throw new OI_ServiceException(
        'A finding Id is required to update its status.'
      );
    }
    if (String.isNotBlank(status) && !VALID_STATUSES.contains(status)) {
      throw new OI_ServiceException('Unrecognized finding status: ' + status);
    }
    repository.updateStatus(
      findingId,
      status,
      notes,
      dueDate,
      ownerId,
      compensatingControl,
      riskAcceptanceExpiry,
      falsePositiveJustification
    );
  }

  /** Other findings affecting the same graph component — the drawer's "related findings" panel, computed on demand rather than a maintained junction object (ADR-0027 lifecycle extension). */
  public List<OI_OrgHealthFindingDTO> getRelatedFindings(
    String componentKey,
    Id excludeFindingId
  ) {
    List<OI_OrgHealthFindingDTO> results = new List<OI_OrgHealthFindingDTO>();
    for (
      OI_Org_Health_Finding__c record : repository.getRelatedByComponentKey(
        componentKey,
        excludeFindingId
      )
    ) {
      results.add(toDTO(record));
    }
    return results;
  }

  /** The Remediation Management workspace's cross-section queue — one filtered/sorted page of findings, plus the paging metadata needed to render it (ADR-0027 lifecycle extension). */
  public OI_RemediationQueryResultDTO getRemediationQueue(
    OI_RemediationFilterDTO filter
  ) {
    OI_RemediationQueryResultDTO result = new OI_RemediationQueryResultDTO();
    result.totalCount = repository.getFindingsCountByFilter(filter);
    for (
      OI_Org_Health_Finding__c record : repository.getFindingsByFilter(filter)
    ) {
      result.findings.add(toDTO(record));
    }
    result.pageNumber = filter == null ||
      filter.pageNumber == null ||
      filter.pageNumber < 1
      ? 1
      : filter.pageNumber;
    result.pageSize = filter == null ||
      filter.pageSize == null ||
      filter.pageSize <= 0
      ? 25
      : Math.min(filter.pageSize, 100);
    result.totalPages = Math.max(
      1,
      Integer.valueOf(
        Math.ceil(Decimal.valueOf(result.totalCount) / result.pageSize)
      )
    );
    return result;
  }

  /** The workspace's org-wide metrics strip — independent of whatever page/filter the queue table is currently showing (ADR-0027 lifecycle extension). */
  public OI_RemediationSummaryDTO getRemediationSummary() {
    OI_RemediationSummaryDTO summary = new OI_RemediationSummaryDTO();
    summary.totalOpenFindings = repository.getTotalOpenCount();
    summary.expiringRiskAcceptanceCount = repository.getExpiringRiskAcceptanceCount();
    summary.overdueCount = repository.getOverdueCount();

    for (AggregateResult severityRow : repository.getOpenCountsBySeverity()) {
      summary.countBySeverity.add(
        new OI_HealthKeyValueDTO(
          (String) severityRow.get('sev'),
          String.valueOf(severityRow.get('total'))
        )
      );
    }
    for (AggregateResult statusRow : repository.getCountsByStatus()) {
      summary.countByStatus.add(
        new OI_HealthKeyValueDTO(
          (String) statusRow.get('stat'),
          String.valueOf(statusRow.get('total'))
        )
      );
    }
    Map<String, String> sectionLabelByKey = loadSectionLabelByKey();
    for (AggregateResult sectionRow : repository.getOpenCountsBySection()) {
      String sectionKey = (String) sectionRow.get('sec');
      String label = sectionLabelByKey.containsKey(sectionKey)
        ? sectionLabelByKey.get(sectionKey)
        : sectionKey;
      summary.countBySection.add(
        new OI_HealthKeyValueDTO(label, String.valueOf(sectionRow.get('total')))
      );
    }
    return summary;
  }

  /** Every row matching the filter (not just the current page) — the workspace's "Export" action hands this to the client for a CSV download (ADR-0027 lifecycle extension). Bounded by OI_OrgHealthFindingRepository's own export row ceiling, never unbounded. */
  public List<OI_OrgHealthFindingDTO> exportRemediationQueue(
    OI_RemediationFilterDTO filter
  ) {
    List<OI_OrgHealthFindingDTO> results = new List<OI_OrgHealthFindingDTO>();
    for (
      OI_Org_Health_Finding__c record : repository.getFindingsForExport(filter)
    ) {
      results.add(toDTO(record));
    }
    return results;
  }

  /** One finding's audit trail — native Field History Tracking, resolved to human-readable field labels via Schema describe rather than a maintained lookup map (ADR-0027 lifecycle extension). */
  public List<OI_FindingHistoryDTO> getFindingHistory(Id findingId) {
    Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.OI_Org_Health_Finding__c.fields.getMap();
    List<OI_FindingHistoryDTO> history = new List<OI_FindingHistoryDTO>();
    for (
      OI_Org_Health_Finding__History historyRow : historySelector.selectByFindingId(
        findingId
      )
    ) {
      OI_FindingHistoryDTO entry = new OI_FindingHistoryDTO();
      entry.fieldLabel = resolveHistoryFieldLabel(historyRow.Field, fieldMap);
      entry.oldValue = historyRow.OldValue == null
        ? null
        : String.valueOf(historyRow.OldValue);
      entry.newValue = historyRow.NewValue == null
        ? null
        : String.valueOf(historyRow.NewValue);
      entry.changedDate = historyRow.CreatedDate;
      entry.changedByName = historyRow.CreatedBy?.Name;
      history.add(entry);
    }
    return history;
  }

  /** The platform reports Owner history as Field = 'Owner', which has no corresponding custom-field Schema entry to describe — everything else is a real field API name resolvable via describe. */
  private String resolveHistoryFieldLabel(
    String fieldApiName,
    Map<String, Schema.SObjectField> fieldMap
  ) {
    if (fieldApiName == 'Owner') {
      return 'Owner';
    }
    Schema.SObjectField field = fieldMap.get(fieldApiName);
    return field == null ? fieldApiName : field.getDescribe().getLabel();
  }

  private Map<String, String> loadSectionLabelByKey() {
    Map<String, String> labelByKey = new Map<String, String>();
    for (
      OI_Org_Health_Section_Config__mdt config : OI_Org_Health_Section_Config__mdt.getAll()
        .values()
    ) {
      labelByKey.put(config.Section_Key__c, config.Display_Label__c);
    }
    return labelByKey;
  }

  private OI_OrgHealthFindingDTO toDTO(OI_Org_Health_Finding__c record) {
    OI_OrgHealthFindingDTO dto = new OI_OrgHealthFindingDTO();
    dto.id = record.Id;
    dto.fingerprint = record.Fingerprint__c;
    dto.sectionKey = record.Section_Key__c;
    dto.ruleId = record.Rule_Id__c;
    dto.ruleVersion = record.Rule_Version__c == null
      ? null
      : record.Rule_Version__c.intValue();
    dto.title = record.Title__c;
    dto.severityKey = record.Severity__c;
    dto.score = record.Score__c;
    dto.scoreExplanation = record.Score_Explanation__c;
    if (String.isNotBlank(record.Severity_Contributors_Json__c)) {
      try {
        dto.scoreContributors = (List<OI_HealthScoreContributor>) JSON.deserialize(
          record.Severity_Contributors_Json__c,
          List<OI_HealthScoreContributor>.class
        );
      } catch (Exception e) {
        dto.scoreContributors = new List<OI_HealthScoreContributor>();
      }
    }
    dto.confidence = record.Confidence__c;
    dto.componentKey = record.Component_Key__c;
    dto.componentType = record.Component_Type__c;
    dto.componentLabel = record.Component_Label__c;
    dto.namespace = record.Namespace__c;
    dto.isManaged = record.Is_Managed__c;
    dto.evidence = record.Evidence__c;
    dto.measuredValue = record.Measured_Value__c;
    dto.expectedValue = record.Expected_Value__c;
    dto.explanation = record.Explanation__c;
    dto.orgRisk = record.Org_Risk__c;
    dto.potentialImpact = record.Potential_Impact__c;
    dto.remediation = record.Remediation__c;
    dto.validationSteps = record.Validation_Steps__c;
    dto.firstDetected = record.First_Detected__c;
    dto.lastDetected = record.Last_Detected__c;
    dto.status = record.Status__c;
    dto.ownerId = record.OwnerId;
    dto.ownerName = record.Owner != null ? record.Owner.Name : null;
    dto.dueDate = record.Due_Date__c;
    dto.notes = record.Notes__c;
    dto.compensatingControl = record.Compensating_Control__c;
    dto.resolutionEvidence = record.Resolution_Evidence__c;
    dto.resolvedDate = record.Resolved_Date__c;
    dto.riskAcceptanceExpiry = record.Risk_Acceptance_Expiry__c;
    dto.isRiskAcceptanceExpired =
      record.Status__c == 'Risk Accepted' &&
      record.Risk_Acceptance_Expiry__c != null &&
      record.Risk_Acceptance_Expiry__c < Date.today();
    dto.falsePositiveJustification = record.False_Positive_Justification__c;
    dto.computeRunId = record.Compute_Run_Id__c;
    dto.hasAutomaticAction = record.Has_Automatic_Action__c;
    dto.requiredPermission = record.Required_Permission__c;
    return dto;
  }
}
