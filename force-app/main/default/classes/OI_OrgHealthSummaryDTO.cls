/**
 * Purpose: The @AuraEnabled wire shape for the Org Health landing grid — one round trip
 *          for all seven section cards (ADR-0026).
 * Responsibilities: Carry the ordered section list (OI_Org_Health_Section_Config__mdt's
 *                    Display_Order__c) plus a snapshot-independent overview block reused as
 *                    the KPI hero strip.
 * Dependencies: OI_OrgOverviewDTO.
 * Limitations: None.
 */
public class OI_OrgHealthSummaryDTO {
  @AuraEnabled
  public OI_OrgOverviewDTO overview;
  @AuraEnabled
  public List<OI_OrgHealthSectionSummaryDTO> sections = new List<OI_OrgHealthSectionSummaryDTO>();
}
