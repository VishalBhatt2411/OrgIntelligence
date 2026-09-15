/**
 * Purpose: The Remediation Management workspace's summary metrics strip — org-wide counts
 *          across every section, independent of whatever page/filter the queue table is
 *          currently showing.
 * Responsibilities: Carry pre-aggregated counts (never computed client-side from a possibly
 *                    filtered/paged findings list, which would silently under-count).
 * Dependencies: OI_HealthKeyValueDTO (reused rather than a new label/value shape).
 * Limitations: expiringRiskAcceptanceCount uses a fixed 30-day lookahead window
 *              (OI_OrgHealthFindingRepository.RISK_ACCEPTANCE_EXPIRY_LOOKAHEAD_DAYS) — not yet
 *              admin-configurable.
 */
public class OI_RemediationSummaryDTO {
  @AuraEnabled
  public Integer totalOpenFindings = 0;
  @AuraEnabled
  public List<OI_HealthKeyValueDTO> countBySeverity = new List<OI_HealthKeyValueDTO>();
  @AuraEnabled
  public List<OI_HealthKeyValueDTO> countByStatus = new List<OI_HealthKeyValueDTO>();
  @AuraEnabled
  public List<OI_HealthKeyValueDTO> countBySection = new List<OI_HealthKeyValueDTO>();
  @AuraEnabled
  public Integer expiringRiskAcceptanceCount = 0;
  @AuraEnabled
  public Integer overdueCount = 0;
}
