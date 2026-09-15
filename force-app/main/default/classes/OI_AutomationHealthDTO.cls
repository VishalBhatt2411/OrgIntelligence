/**
 * Purpose: Org Health's Automation Health detail view (ADR-0026 Phase 3, Tier 2 — live,
 *          bounded, unpersisted) — ProductSpecs.md's facts for automation: per-object
 *          automation count, high fan-in/fan-out components, and cycles. Is_Scored__c = false
 *          for this section (§0.3) — the spec never asks Automation Health for a score, so
 *          this DTO deliberately carries no score/severityKey/formula fields, unlike
 *          OI_CodeHealthDTO. Individual breakdown/heatmap rows still carry a real,
 *          threshold-derived severityKey — that is evidence-based coloring of one metric, not
 *          an invented composite score.
 * Responsibilities: Carry the KPI row and the breakdown table + heatmap's shared row evidence.
 * Dependencies: OI_HealthKeyValueDTO, OI_HealthBreakdownRowDTO, OI_HealthHeatmapRowDTO.
 * Limitations: None.
 */
public class OI_AutomationHealthDTO {
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
