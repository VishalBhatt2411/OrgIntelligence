/**
 * Purpose: A generic label/value pair for Org Health's KPI rows (landing-grid category
 *          cards, detail-view KPI tiles) — ADR-0026.
 * Responsibilities: Carry a display label and a pre-formatted display value. Deliberately
 *                    a String value, not a typed number — formatting (units, thousands
 *                    separators, percentages) is a section Service's job, done once
 *                    server-side rather than repeated per LWC.
 * Dependencies: None.
 * Limitations: None.
 */
public class OI_HealthKeyValueDTO {
  @AuraEnabled
  public String label;
  @AuraEnabled
  public String value;
  /**
   * Optional machine key identifying which live metric this tile summarizes (e.g.
   * 'HighFieldCount') — null for a tile with no drill-down behind it. A section Service
   * that sets this on a KPI tile is declaring that tile clickable; oiHealthKpiTile treats
   * a blank metricKey as "not interactive" so existing non-drillable tiles are unaffected.
   */
  @AuraEnabled
  public String metricKey;

  public OI_HealthKeyValueDTO(String label, String value) {
    this(label, value, null);
  }

  public OI_HealthKeyValueDTO(String label, String value, String metricKey) {
    this.label = label;
    this.value = value;
    this.metricKey = metricKey;
  }
}
