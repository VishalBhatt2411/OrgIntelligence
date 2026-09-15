/**
 * Purpose: The output of OI_HealthScoringEngine.score — a finding's final multi-signal
 *          severity, fully explained.
 * Responsibilities: Carry the combined badness score (0–100, higher = worse), the severity key
 *                    resolved from it via the same band registry the rest of Org Health uses,
 *                    every contributor that fed it, and a one-line human explanation naming the
 *                    top contributor(s) — so "why is this Critical" never requires reading code.
 * Dependencies: OI_HealthScoreContributor.
 * Limitations: None.
 */
public class OI_HealthScoreResult {
  @AuraEnabled
  public Decimal score;
  @AuraEnabled
  public String severityKey;
  @AuraEnabled
  public String explanation;
  @AuraEnabled
  public List<OI_HealthScoreContributor> contributors = new List<OI_HealthScoreContributor>();
}
