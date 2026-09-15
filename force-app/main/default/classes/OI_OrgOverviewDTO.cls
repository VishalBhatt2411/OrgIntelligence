/**
 * Purpose: The @AuraEnabled wire shape for Org Health's Org Overview section (ADR-0026,
 *          ProductSpecs.md Phase 4 "Org Overview").
 * Responsibilities: Carry per-type node counts plus the two edge-derived counts
 *                    (dependencyCount, relationshipCount) and scan freshness. No score —
 *                    the spec asks this section for counts, not a rating.
 * Dependencies: None.
 * Limitations: None.
 */
public class OI_OrgOverviewDTO {
  @AuraEnabled
  public Integer objectCount;
  @AuraEnabled
  public Integer fieldCount;
  @AuraEnabled
  public Integer apexClassCount;
  @AuraEnabled
  public Integer triggerCount;
  @AuraEnabled
  public Integer flowCount;
  @AuraEnabled
  public Integer permissionSetCount;
  @AuraEnabled
  public Integer dependencyCount;
  @AuraEnabled
  public Integer relationshipCount;
  @AuraEnabled
  public Datetime lastScannedAt;
}
