/**
 * Purpose: The @AuraEnabled wire shape for one OI_Health_Severity_Descriptor__mdt row —
 *          ADR-0026's severity registry, resolved once per session by
 *          oiOrgHealthDashboard and passed down to presentational components, mirroring
 *          the Node/Edge Type Descriptor registry pattern (GraphUI.md §20-21).
 * Responsibilities: Flatten the CMDT row. No behavior.
 * Dependencies: OI_Health_Severity_Descriptor__mdt.
 * Limitations: None.
 */
public class OI_HealthSeverityDescriptorDTO {
  @AuraEnabled
  public String severityKey;
  @AuraEnabled
  public String displayLabel;
  @AuraEnabled
  public String iconName;
  @AuraEnabled
  public String colorToken;

  public OI_HealthSeverityDescriptorDTO(
    OI_Health_Severity_Descriptor__mdt row
  ) {
    this.severityKey = row.Severity_Key__c;
    this.displayLabel = row.Display_Label__c;
    this.iconName = row.Icon_Name__c;
    this.colorToken = row.Color_Token__c;
  }
}
