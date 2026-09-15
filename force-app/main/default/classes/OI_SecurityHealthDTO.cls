/**
 * Purpose: Org Health's Security Health detail view (ADR-0026 Phase 4, Tier 2 — live, bounded,
 *          unpersisted) — ProductSpecs.md's evidence-based checks: broad Object grants,
 *          sensitive metadata with broad grants, Permission Set coverage, elevated
 *          permissions. Facts-only — Is_Scored__c = false (§0.3, matching the CMDT's own
 *          pre-existing value): the spec explicitly says "No fake score" for this section, so
 *          this DTO deliberately carries no score/severityKey/formula fields, mirroring
 *          OI_AutomationHealthDTO. Individual breakdown/heatmap rows still carry a real,
 *          threshold-derived severityKey — evidence-based coloring of real grants, not an
 *          invented composite score.
 * Responsibilities: Carry the KPI row and the breakdown table + heatmap's shared row evidence.
 * Dependencies: OI_HealthKeyValueDTO, OI_HealthBreakdownRowDTO, OI_HealthHeatmapRowDTO.
 * Limitations: None.
 */
public class OI_SecurityHealthDTO {
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
