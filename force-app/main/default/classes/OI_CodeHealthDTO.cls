/**
 * Purpose: Org Health's Code Health detail view (ADR-0026 Phase 3, Tier 2 — live, bounded,
 *          unpersisted) — ProductSpecs.md's "measurable facts" for Apex: test coverage,
 *          dependency fan-in/out, cycles, and stale API versions. Is_Scored__c = true for
 *          this section (unlike Automation Health), so it carries the same score/formula
 *          shape as OI_MetadataHealthDTO — "any score must expose formula."
 * Responsibilities: Carry the score/severity, the formula disclosure content, the KPI row,
 *                    and the breakdown table + heatmap's shared row evidence.
 * Dependencies: OI_HealthKeyValueDTO, OI_HealthBreakdownRowDTO, OI_HealthHeatmapRowDTO.
 * Limitations: None.
 */
public class OI_CodeHealthDTO {
  @AuraEnabled
  public Decimal score;
  @AuraEnabled
  public String severityKey;
  @AuraEnabled
  public String formulaSummary;
  @AuraEnabled
  public List<OI_HealthKeyValueDTO> formulaComponents = new List<OI_HealthKeyValueDTO>();
  @AuraEnabled
  public String coverageNote;
  @AuraEnabled
  public Boolean isCoverageComplete;
  @AuraEnabled
  public Datetime computedAt;
  @AuraEnabled
  public List<OI_HealthKeyValueDTO> kpiTiles = new List<OI_HealthKeyValueDTO>();
  @AuraEnabled
  public String breakdownTitle;
  @AuraEnabled
  public String breakdownCoverageCaption;
  @AuraEnabled
  public List<String> metricColumnLabels = new List<String>();
  @AuraEnabled
  public List<OI_HealthBreakdownRowDTO> breakdownRows = new List<OI_HealthBreakdownRowDTO>();
  @AuraEnabled
  public List<String> heatmapColumnLabels = new List<String>();
  @AuraEnabled
  public List<OI_HealthHeatmapRowDTO> heatmapRows = new List<OI_HealthHeatmapRowDTO>();
}
