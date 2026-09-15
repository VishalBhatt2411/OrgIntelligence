/**
 * Purpose: The Remediation Management workspace's query filter (ADR-0027 lifecycle extension —
 *          "a shared remediation workspace, explicitly on this package's roadmap") — every
 *          field the client can narrow the cross-section finding queue by, plus paging and
 *          sorting. Pure input shape.
 * Responsibilities: Carry an @AuraEnabled-serializable filter from the LWC to
 *                    OI_OrgHealthFindingService.getRemediationQueue /
 *                    exportRemediationQueue. Every field is optional — an empty filter means
 *                    "every non-deleted finding, page 1, most-severe-first."
 * Dependencies: None.
 * Limitations: sortField accepts only a small allow-listed set of friendly keys (see
 *              OI_OrgHealthFindingRepository.SORTABLE_FIELDS) — never a raw SOQL field name —
 *              so a client cannot inject an arbitrary ORDER BY expression.
 */
public class OI_RemediationFilterDTO {
  @AuraEnabled
  public List<String> sectionKeys;
  @AuraEnabled
  public List<String> severityKeys;
  @AuraEnabled
  public List<String> statuses;
  @AuraEnabled
  public Id ownerId;
  @AuraEnabled
  public String searchText;
  @AuraEnabled
  public Boolean onlyExpiringRiskAcceptance;
  @AuraEnabled
  public Boolean onlyOverdue;
  @AuraEnabled
  public String sortField;
  @AuraEnabled
  public String sortDirection;
  @AuraEnabled
  public Integer pageNumber;
  @AuraEnabled
  public Integer pageSize;
}
