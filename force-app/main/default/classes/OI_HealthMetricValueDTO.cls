/**
 * Purpose: A positional metric cell for Org Health's breakdown table and heatmap grid
 *          (ADR-0026 Phase 2) — deliberately distinct from OI_HealthKeyValueDTO, whose
 *          `label` is a display string; here `key` lines up positionally with the caller's
 *          own column-label list instead.
 * Responsibilities: Carry one pre-formatted metric value, plus an optional per-cell severity
 *                    for heatmap rendering (null and unused in plain breakdown rows, where
 *                    severity is shown once at the row level instead).
 * Dependencies: None.
 * Limitations: None.
 */
public class OI_HealthMetricValueDTO {
  @AuraEnabled
  public String key;
  @AuraEnabled
  public String value;
  @AuraEnabled
  public String severityKey;

  public OI_HealthMetricValueDTO(String key, String value) {
    this(key, value, null);
  }

  public OI_HealthMetricValueDTO(String key, String value, String severityKey) {
    this.key = key;
    this.value = value;
    this.severityKey = severityKey;
  }
}
