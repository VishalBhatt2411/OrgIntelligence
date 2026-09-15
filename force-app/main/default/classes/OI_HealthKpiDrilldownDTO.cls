/**
 * Purpose: The full object list behind one KPI tile on an Org Health detail view (e.g. "High
 *          field-count objects: 12") — a KPI tile is a live-computed aggregate over every
 *          scanned object, while a section's breakdown table is deliberately capped to its
 *          top N worst rows, so a tile's own count and the breakdown table's row count
 *          usually disagree. This DTO is what a clicked KPI tile actually shows.
 * Responsibilities: Carry a title, the same metric column labels the breakdown table uses (so
 *                    the two can share the same oiHealthBreakdownList primitive), a coverage
 *                    caption ("N of M"), and every matching row — never re-truncated to a
 *                    top-N, since the whole point is showing the objects a capped table hid.
 * Dependencies: OI_HealthBreakdownRowDTO.
 * Limitations: None.
 */
public class OI_HealthKpiDrilldownDTO {
  @AuraEnabled
  public String title;
  @AuraEnabled
  public String coverageCaption;
  @AuraEnabled
  public List<String> metricColumnLabels = new List<String>();
  @AuraEnabled
  public List<OI_HealthBreakdownRowDTO> rows = new List<OI_HealthBreakdownRowDTO>();
}
