/**
 * Purpose: The @AuraEnabled wire shape for one Org Health landing-grid card (ADR-0026).
 * Responsibilities: Carry enough for the summary grid without the section's full detail
 *                    payload — score/severity, a few top signals, coverage, and whether
 *                    this section's backend exists yet. isImplemented is a rollout-phase
 *                    flag, not a product state: it lets the landing grid render a "coming
 *                    soon" card for a section whose Service doesn't exist yet in this
 *                    package version, distinct from that section's own true-zero/
 *                    unscanned/not-obtainable states once it is implemented.
 * Dependencies: None.
 * Limitations: None.
 */
public class OI_OrgHealthSectionSummaryDTO {
  @AuraEnabled
  public String sectionKey;
  @AuraEnabled
  public String displayLabel;
  @AuraEnabled
  public Boolean isImplemented;
  @AuraEnabled
  public Boolean isScored;
  @AuraEnabled
  public Decimal score;
  @AuraEnabled
  public String severityKey;
  @AuraEnabled
  public List<OI_HealthKeyValueDTO> topSignals = new List<OI_HealthKeyValueDTO>();
  @AuraEnabled
  public String coverageNote;
}
