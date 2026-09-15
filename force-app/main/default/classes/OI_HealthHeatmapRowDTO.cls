/**
 * Purpose: One row of Org Health's signal heatmap (ADR-0026 Phase 2) — the same evidence
 *          oiHealthBreakdownList shows as a table row, reshaped as colored cells for
 *          oiHealthHeatmapGrid.
 * Responsibilities: Carry a row label and one severity-colored cell per configured column.
 * Dependencies: OI_HealthMetricValueDTO.
 * Limitations: None.
 */
public class OI_HealthHeatmapRowDTO {
  @AuraEnabled
  public String rowLabel;
  @AuraEnabled
  public List<OI_HealthMetricValueDTO> cells = new List<OI_HealthMetricValueDTO>();
}
