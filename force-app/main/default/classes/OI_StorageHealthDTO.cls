/**
 * Purpose: The @AuraEnabled wire shape for the Storage section of Org Health (ADR-0026,
 *          ProductSpecs.md Phase 4 "Storage").
 * Responsibilities: Carry real org limit values plus an explicit unavailableMetrics list —
 *                    the structural home for the spec's "if some desired metric is not
 *                    actually obtainable, state it" rule, so a missing limit renders as an
 *                    honest "not obtainable" state rather than a silent zero.
 * Dependencies: None.
 * Limitations: None.
 */
public class OI_StorageHealthDTO {
  @AuraEnabled
  public Integer dataUsedMb;
  @AuraEnabled
  public Integer dataLimitMb;
  @AuraEnabled
  public Integer dataRemainingMb;
  @AuraEnabled
  public Integer fileUsedMb;
  @AuraEnabled
  public Integer fileLimitMb;
  @AuraEnabled
  public Integer fileRemainingMb;
  @AuraEnabled
  public List<String> unavailableMetrics = new List<String>();
}
