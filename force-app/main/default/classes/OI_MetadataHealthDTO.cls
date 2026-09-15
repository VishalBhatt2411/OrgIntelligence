/**
 * Purpose: Org Health's Metadata Health detail view (ADR-0026 Phase 2, Tier 2 — live,
 *          bounded, unpersisted) — the pixel-fidelity-bound exemplar detail view
 *          (OrgHealthVisualDesignSpecification.md §3.3).
 * Responsibilities: Carry the score/severity, the formula disclosure content (structurally
 *                    guaranteeing "any score must expose its formula"), the 4-tile KPI row,
 *                    and the breakdown table + heatmap's shared row evidence.
 * Dependencies: OI_HealthKeyValueDTO, OI_HealthBreakdownRowDTO, OI_HealthHeatmapRowDTO.
 * Limitations: None.
 */
public class OI_MetadataHealthDTO {
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
