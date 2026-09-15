/**
 * Purpose: The client-facing record of exactly what one OI_HealthSignal contributed to a
 *          finding's final score (OI_HealthScoringEngine) — what the finding drawer renders
 *          under "why this severity."
 * Responsibilities: Carry every factor that fed the contribution (magnitude, confidence,
 *                    impact, exposure, compensating control) plus the resulting point value, so
 *                    the drawer never has to re-derive or guess at the arithmetic.
 * Dependencies: None.
 * Limitations: None.
 */
public class OI_HealthScoreContributor {
  @AuraEnabled
  public String key;
  @AuraEnabled
  public String label;
  @AuraEnabled
  public Decimal weight;
  @AuraEnabled
  public Decimal magnitude;
  @AuraEnabled
  public Decimal confidence;
  @AuraEnabled
  public Decimal impactMultiplier;
  @AuraEnabled
  public Decimal exposureMultiplier;
  @AuraEnabled
  public Boolean hasCompensatingControl;
  @AuraEnabled
  public Boolean wasCorrelatedOut;
  @AuraEnabled
  public Decimal contribution;
  @AuraEnabled
  public String note;
}
