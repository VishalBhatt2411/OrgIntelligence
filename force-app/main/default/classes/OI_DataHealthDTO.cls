/**
 * Purpose: Org Health's Data Health detail view (ADR-0026 Phase 5, Tier 3 — async, persisted)
 *          — ProductSpecs.md's bounded, configurable data-quality analysis: stale records,
 *          completeness (null density), and duplicates. Is_Scored__c = true (matching the
 *          CMDT's own pre-existing value): the section carries a real, formula-disclosed
 *          score once a run has completed.
 * Responsibilities: Carry the async run status alongside the same score/formula/KPI/breakdown/
 *                    heatmap shape every other scored section uses — runStatus lets the
 *                    container render the correct one of its "not yet run / queued / running /
 *                    completed / failed" states (ADR-0026's loading/empty/error state
 *                    contract) without inventing a result for a run that hasn't finished.
 * Dependencies: OI_HealthKeyValueDTO, OI_HealthBreakdownRowDTO, OI_HealthHeatmapRowDTO.
 * Limitations: None.
 */
public class OI_DataHealthDTO {
  /** One of: NotYetRun, Queued, Processing, Completed, Failed, Aborted — mirrors the real Salesforce AsyncApexJob.Status vocabulary this DTO is built from, never an invented state. */
  @AuraEnabled
  public String runStatus;
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
