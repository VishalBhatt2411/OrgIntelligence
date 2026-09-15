/**
 * Purpose: One audit-trail entry for a finding's drawer "History" panel — a single tracked
 *          field change, sourced from the platform's own OI_Org_Health_Finding__History object
 *          (native Field History Tracking, never a hand-rolled audit table).
 * Responsibilities: Carry a human-readable field label (resolved via Schema describe, never a
 *                    raw API name) plus the old/new value and who/when changed it.
 * Dependencies: None.
 * Limitations: Only fields with trackHistory enabled on OI_Org_Health_Finding__c appear here
 *              (currently Status__c, Due_Date__c, Risk_Acceptance_Expiry__c, plus Owner —
 *              tracked automatically by the platform once object-level history is on). A
 *              picklist field's old/new values are already the human-readable label text
 *              Salesforce stores in history, not a code needing further translation.
 */
public class OI_FindingHistoryDTO {
  @AuraEnabled
  public String fieldLabel;
  @AuraEnabled
  public String oldValue;
  @AuraEnabled
  public String newValue;
  @AuraEnabled
  public Datetime changedDate;
  @AuraEnabled
  public String changedByName;
}
