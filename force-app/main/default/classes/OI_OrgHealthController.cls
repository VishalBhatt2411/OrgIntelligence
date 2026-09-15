/**
 * Purpose: The @AuraEnabled boundary for the Org Health tab (ADR-0026) — backs
 *          oiOrgHealthDashboard and its section containers. One domain Controller grouping
 *          several thin, related methods, mirroring OI_GraphController's actual shape
 *          rather than a literal one-controller-per-method reading.
 * Responsibilities: Permission check -> call exactly one section Service -> map to a DTO ->
 *                    return, or translate to a sanitized AuraHandledException
 *                    (CodingStandards.md §6), matching OI_GraphController's own established
 *                    translate() pattern exactly. Each method here delegates to exactly one
 *                    section-specific Service (OI_OrgHealthSummaryService,
 *                    OI_OrgOverviewService, OI_StorageHealthService,
 *                    OI_HealthSeverityService) — this class contains no computation of its
 *                    own.
 * Dependencies: OI_SecurityService, OI_OrgHealthSummaryService, OI_OrgOverviewService,
 *               OI_StorageHealthService, OI_MetadataHealthService, OI_AutomationHealthService,
 *               OI_CodeHealthService, OI_SecurityHealthService, OI_DataHealthService,
 *               OI_DataHealthComputeBatchable, OI_HealthSeverityService,
 *               OI_OrgHealthFindingService (the unified finding model, ADR-0027).
 * Limitations: recomputeDataHealth and syncMetadataHealthFindings are gated by the narrower
 *              OI_Run_Org_Health_Compute permission and are non-cacheable (they write), and
 *              updateFindingStatus is gated by the still narrower OI_Manage_Finding_Workflow —
 *              every other method here is a pure, cacheable, OI_View_Org_Health-gated read.
 */
public with sharing class OI_OrgHealthController {
  @AuraEnabled(cacheable=true)
  public static OI_OrgHealthSummaryDTO getOrgHealthSummary() {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_OrgHealthSummaryService().getSummary();
    } catch (Exception e) {
      throw translate(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static OI_OrgOverviewDTO getOrgOverviewDetail() {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_OrgOverviewService().getOrgOverview();
    } catch (Exception e) {
      throw translate(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static OI_StorageHealthDTO getStorageDetail() {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_StorageHealthService().getStorageHealth();
    } catch (Exception e) {
      throw translate(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static OI_MetadataHealthDTO getMetadataHealthDetail() {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_MetadataHealthService().getMetadataHealthDetail();
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** The full object list behind one Metadata Health KPI tile — see OI_HealthKpiDrilldownDTO. */
  @AuraEnabled(cacheable=true)
  public static OI_HealthKpiDrilldownDTO getMetadataHealthKpiDrilldown(
    String metricKey
  ) {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_MetadataHealthService().getKpiDrilldown(metricKey);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static OI_AutomationHealthDTO getAutomationHealthDetail() {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_AutomationHealthService().getAutomationHealthDetail();
    } catch (Exception e) {
      throw translate(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static OI_CodeHealthDTO getCodeHealthDetail() {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_CodeHealthService().getCodeHealthDetail();
    } catch (Exception e) {
      throw translate(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static OI_SecurityHealthDTO getSecurityHealthDetail() {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_SecurityHealthService().getSecurityHealthDetail();
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** Not cacheable: unlike every other read method above, this reflects a live, changing async run status (queued/processing/completed) that the UI polls — a cacheable result would let Lightning Data Service serve a stale snapshot back to the poller instead of hitting the server. */
  @AuraEnabled
  public static OI_DataHealthDTO getDataHealthDetail() {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_DataHealthService().getDataHealthDetail();
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** Not cacheable — enqueues Database.executeBatch, a side effect. Gated by a separate, narrower permission than every read method above (§0.8). */
  @AuraEnabled
  public static String recomputeDataHealth() {
    try {
      OI_SecurityService.assertPermission('OI_Run_Org_Health_Compute');
      Database.executeBatch(
        new OI_DataHealthComputeBatchable(UserInfo.getUserId()),
        50
      );
      return 'Queued';
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /**
   * Read path for the unified finding model (ADR-0027) — Data Health's own findings. Unlike
   * the Tier-2 live sections, there is no separate syncDataHealthFindings write method: Data
   * Health's only write action is recomputeDataHealth, and OI_DataHealthComputeBatchable's own
   * finish() already syncs findings as part of that same bounded async run.
   */
  @AuraEnabled(cacheable=true)
  public static List<OI_OrgHealthFindingDTO> getDataHealthFindings() {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_OrgHealthFindingService()
        .getFindingsForSection('DataHealth');
    } catch (Exception e) {
      throw translate(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<OI_HealthSeverityDescriptorDTO> getSeverityRegistry() {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_HealthSeverityService().getSeverityRegistry();
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** Read path for the unified finding model (ADR-0027) — a pure SOQL read, so cacheable like every other read method above. */
  @AuraEnabled(cacheable=true)
  public static List<OI_OrgHealthFindingDTO> getMetadataHealthFindings() {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_OrgHealthFindingService()
        .getFindingsForSection('MetadataHealth');
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /**
   * Write path for the unified finding model — computes this section's live candidates and
   * upserts/auto-resolves them as findings (ADR-0027). Not cacheable: performs DML, exactly
   * like recomputeDataHealth. Gated by the same narrower OI_Run_Org_Health_Compute permission
   * as recomputeDataHealth, not OI_View_Org_Health — computing findings is a write action,
   * distinct from merely viewing the live (unpersisted) Metadata Health detail.
   */
  @AuraEnabled
  public static String syncMetadataHealthFindings() {
    try {
      OI_SecurityService.assertPermission('OI_Run_Org_Health_Compute');
      List<OI_OrgHealthFindingCandidate> candidates = new OI_MetadataHealthService()
        .getFindingCandidates();
      new OI_OrgHealthFindingService()
        .sync('MetadataHealth', candidates, generateComputeRunId());
      return 'Synced';
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** Read path for the unified finding model (ADR-0027) — Automation Health's own findings, mirroring getMetadataHealthFindings exactly. */
  @AuraEnabled(cacheable=true)
  public static List<OI_OrgHealthFindingDTO> getAutomationHealthFindings() {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_OrgHealthFindingService()
        .getFindingsForSection('AutomationHealth');
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** Write path for the unified finding model — Automation Health's own sync, mirroring syncMetadataHealthFindings exactly. Not cacheable: performs DML. Gated by OI_Run_Org_Health_Compute, not OI_View_Org_Health. */
  @AuraEnabled
  public static String syncAutomationHealthFindings() {
    try {
      OI_SecurityService.assertPermission('OI_Run_Org_Health_Compute');
      List<OI_OrgHealthFindingCandidate> candidates = new OI_AutomationHealthService()
        .getFindingCandidates();
      new OI_OrgHealthFindingService()
        .sync('AutomationHealth', candidates, generateComputeRunId());
      return 'Synced';
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** Read path for the unified finding model (ADR-0027) — Code Health's own findings, mirroring getAutomationHealthFindings exactly. */
  @AuraEnabled(cacheable=true)
  public static List<OI_OrgHealthFindingDTO> getCodeHealthFindings() {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_OrgHealthFindingService()
        .getFindingsForSection('CodeHealth');
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** Write path for the unified finding model — Code Health's own sync, mirroring syncAutomationHealthFindings exactly. Not cacheable: performs DML. Gated by OI_Run_Org_Health_Compute, not OI_View_Org_Health. */
  @AuraEnabled
  public static String syncCodeHealthFindings() {
    try {
      OI_SecurityService.assertPermission('OI_Run_Org_Health_Compute');
      List<OI_OrgHealthFindingCandidate> candidates = new OI_CodeHealthService()
        .getFindingCandidates();
      new OI_OrgHealthFindingService()
        .sync('CodeHealth', candidates, generateComputeRunId());
      return 'Synced';
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** Read path for the unified finding model (ADR-0027) — Security Health's own findings, mirroring getCodeHealthFindings exactly. */
  @AuraEnabled(cacheable=true)
  public static List<OI_OrgHealthFindingDTO> getSecurityHealthFindings() {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_OrgHealthFindingService()
        .getFindingsForSection('SecurityHealth');
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** Write path for the unified finding model — Security Health's own sync, mirroring syncCodeHealthFindings exactly. Not cacheable: performs DML. Gated by OI_Run_Org_Health_Compute, not OI_View_Org_Health. */
  @AuraEnabled
  public static String syncSecurityHealthFindings() {
    try {
      OI_SecurityService.assertPermission('OI_Run_Org_Health_Compute');
      List<OI_OrgHealthFindingCandidate> candidates = new OI_SecurityHealthService()
        .getFindingCandidates();
      new OI_OrgHealthFindingService()
        .sync('SecurityHealth', candidates, generateComputeRunId());
      return 'Synced';
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /**
   * Applies an administrator's explicit triage decision to one finding — status, notes, due
   * date, owner, or a compensating-control note. Gated by OI_Manage_Finding_Workflow, a
   * narrower permission than either OI_View_Org_Health or OI_Run_Org_Health_Compute: viewing
   * and computing findings do not imply the right to change their remediation lifecycle.
   */
  @AuraEnabled
  public static void updateFindingStatus(
    Id findingId,
    String status,
    String notes,
    Date dueDate,
    Id ownerId,
    String compensatingControl,
    Date riskAcceptanceExpiry,
    String falsePositiveJustification
  ) {
    try {
      OI_SecurityService.assertPermission('OI_Manage_Finding_Workflow');
      new OI_OrgHealthFindingService()
        .updateStatus(
          findingId,
          status,
          notes,
          dueDate,
          ownerId,
          compensatingControl,
          riskAcceptanceExpiry,
          falsePositiveJustification
        );
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** The drawer's "related findings" panel — other findings affecting the same graph component (ADR-0027 lifecycle extension). Pure read, cacheable like every other finding read above. */
  @AuraEnabled(cacheable=true)
  public static List<OI_OrgHealthFindingDTO> getRelatedFindings(
    String componentKey,
    Id excludeFindingId
  ) {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_OrgHealthFindingService()
        .getRelatedFindings(componentKey, excludeFindingId);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /**
   * The Remediation Management workspace's cross-section queue (ADR-0027 lifecycle extension —
   * "a shared remediation workspace, explicitly on this package's roadmap"). Cacheable like
   * every other read here — Aura's client cache keys on the full parameter value, so a changed
   * filter/page is always a fresh request, never a stale cache hit.
   */
  @AuraEnabled(cacheable=true)
  public static OI_RemediationQueryResultDTO getRemediationQueue(
    OI_RemediationFilterDTO filter
  ) {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_OrgHealthFindingService().getRemediationQueue(filter);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** The workspace's summary metrics strip — org-wide counts independent of the queue's current page/filter. */
  @AuraEnabled(cacheable=true)
  public static OI_RemediationSummaryDTO getRemediationSummary() {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_OrgHealthFindingService().getRemediationSummary();
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** The workspace's "Export" action — every row matching the filter, for a client-side CSV download. Not cacheable: an explicit, on-demand action, not a passive read the UI repeats every render. */
  @AuraEnabled
  public static List<OI_OrgHealthFindingDTO> exportRemediationQueue(
    OI_RemediationFilterDTO filter
  ) {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_OrgHealthFindingService().exportRemediationQueue(filter);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** One finding's audit-trail panel — native Field History Tracking (ADR-0027 lifecycle extension). */
  @AuraEnabled(cacheable=true)
  public static List<OI_FindingHistoryDTO> getFindingHistory(Id findingId) {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      return new OI_OrgHealthFindingService().getFindingHistory(findingId);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /**
   * The drawer's "open related graph component" action — resolves a finding's Component_Key__c
   * (a graph node key, opaque outside the graph) through OI_GraphEngine.getNodeDetail to learn
   * its real type/API name, then through OI_MetadataNavigationService for a real Setup/graph
   * target, exactly the same resolution path a graph row's own click-through already uses.
   */
  @AuraEnabled(cacheable=true)
  public static OI_NavigationTargetDTO getFindingComponentNavigation(
    String componentKey
  ) {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      if (String.isBlank(componentKey)) {
        return OI_NavigationTargetDTO.unsupported(
          'This finding is not tied to a specific graph component.'
        );
      }
      OI_VersionRecord nodeDetail = new OI_GraphEngine()
        .getNodeDetail(componentKey);
      if (nodeDetail == null) {
        return OI_NavigationTargetDTO.unsupported(
          'This component is no longer present in the org, or is not visible to you.'
        );
      }
      return new OI_MetadataNavigationService()
        .resolve(nodeDetail.typeKey, nodeDetail.secondaryKey);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** Mirrors OI_DataHealthComputeBatchable.generateComputeRunId exactly — a short, human-scannable run identifier, not a strict RFC-4122 UUID (no collision-resistance guarantee needed beyond "distinct per invocation," which a 128-bit random key already provides many times over). */
  private static String generateComputeRunId() {
    String hex = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
    return hex.substring(0, 8) +
      '-' +
      hex.substring(8, 12) +
      '-' +
      hex.substring(12, 16) +
      '-' +
      hex.substring(16, 20) +
      '-' +
      hex.substring(20, 32);
  }

  /** Sanitized Controller-boundary translation (CodingStandards.md §6) — mirrors OI_GraphController.translate exactly. */
  private static AuraHandledException translate(Exception e) {
    String message;
    if (e instanceof OI_SecurityException) {
      message = 'You don\'t have permission to perform this Org Health action.';
    } else if (
      e instanceof OI_ValidationException || e instanceof OI_ServiceException
    ) {
      message = e.getMessage();
    } else {
      message = 'Something went wrong retrieving Org Health. Please try again.';
    }
    AuraHandledException handled = new AuraHandledException(message);
    handled.setMessage(message);
    return handled;
  }
}
