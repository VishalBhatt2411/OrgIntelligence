/**
 * Purpose: One page of the Remediation Management workspace's cross-section finding queue.
 * Responsibilities: Carry the page of findings plus the paging metadata the client needs to
 *                    render "Page 2 of 5 (rows 26-50 of 118)" and enable/disable next/previous
 *                    controls, without a second round-trip.
 * Dependencies: OI_OrgHealthFindingDTO.
 * Limitations: None.
 */
public class OI_RemediationQueryResultDTO {
  @AuraEnabled
  public List<OI_OrgHealthFindingDTO> findings = new List<OI_OrgHealthFindingDTO>();
  @AuraEnabled
  public Integer totalCount = 0;
  @AuraEnabled
  public Integer pageNumber = 1;
  @AuraEnabled
  public Integer pageSize = 25;
  @AuraEnabled
  public Integer totalPages = 1;
}
