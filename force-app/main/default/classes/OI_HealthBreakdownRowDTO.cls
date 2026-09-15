/**
 * Purpose: One row of Org Health's ranked breakdown table (ADR-0026 Phase 2) — shapes a
 *          scored section's real, evidence-based findings for oiHealthBreakdownList.
 * Responsibilities: Carry a stable row key, the primary (object/field) label, one metric
 *                    value per configured column, and the row's own severity.
 * Dependencies: OI_HealthMetricValueDTO.
 * Limitations: `explanation` is optional and section-specific — a Service that has not been
 *              updated to populate it leaves it blank, and the consuming LWC must treat a
 *              blank explanation as "nothing to show," never render an empty sentence.
 */
public class OI_HealthBreakdownRowDTO {
  @AuraEnabled
  public String key;
  @AuraEnabled
  public String primaryLabel;
  @AuraEnabled
  public List<OI_HealthMetricValueDTO> metricValues = new List<OI_HealthMetricValueDTO>();
  @AuraEnabled
  public String severityKey;
  @AuraEnabled
  public String severityLabel;
  /**
   * A short, plain-English statement of why THIS row has the severity it does — e.g. "34
   * custom fields — at or above this org's threshold of 60." Lets a row remain informative
   * before any finding has ever been synced/persisted for it (ADR-0027's persisted finding
   * model is richer — triage, history — but is opt-in via "Sync findings"; this is the live,
   * always-available answer to "why is this here").
   */
  @AuraEnabled
  public String explanation;
}
