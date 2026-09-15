/**
 * Purpose: The unified Org Health finding, shaped for the client (ADR-0027) — the full
 *          answer to "what was detected, why, does it matter here, what could it damage,
 *          and what should the administrator do," plus its remediation lifecycle.
 * Responsibilities: Carry every field OI_Org_Health_Finding__c stores, mapped to a plain,
 *                    Aura-serializable shape so the finding-detail drawer never needs a second
 *                    round-trip for evidence/remediation text already on the record.
 * Dependencies: None.
 * Limitations: None.
 */
public class OI_OrgHealthFindingDTO {
  @AuraEnabled
  public Id id;
  @AuraEnabled
  public String fingerprint;
  @AuraEnabled
  public String sectionKey;
  @AuraEnabled
  public String ruleId;
  @AuraEnabled
  public Integer ruleVersion;
  @AuraEnabled
  public String title;
  @AuraEnabled
  public String severityKey;
  @AuraEnabled
  public Decimal score;
  @AuraEnabled
  public String scoreExplanation;
  @AuraEnabled
  public List<OI_HealthScoreContributor> scoreContributors = new List<OI_HealthScoreContributor>();
  @AuraEnabled
  public String confidence;
  @AuraEnabled
  public String componentKey;
  @AuraEnabled
  public String componentType;
  @AuraEnabled
  public String componentLabel;
  @AuraEnabled
  public String namespace;
  @AuraEnabled
  public Boolean isManaged;
  @AuraEnabled
  public String evidence;
  @AuraEnabled
  public String measuredValue;
  @AuraEnabled
  public String expectedValue;
  @AuraEnabled
  public String explanation;
  @AuraEnabled
  public String orgRisk;
  @AuraEnabled
  public String potentialImpact;
  @AuraEnabled
  public String remediation;
  @AuraEnabled
  public String validationSteps;
  @AuraEnabled
  public Datetime firstDetected;
  @AuraEnabled
  public Datetime lastDetected;
  @AuraEnabled
  public String status;
  @AuraEnabled
  public Id ownerId;
  @AuraEnabled
  public String ownerName;
  @AuraEnabled
  public Date dueDate;
  @AuraEnabled
  public String notes;
  @AuraEnabled
  public String compensatingControl;
  @AuraEnabled
  public String resolutionEvidence;
  @AuraEnabled
  public Datetime resolvedDate;
  @AuraEnabled
  public Date riskAcceptanceExpiry;
  @AuraEnabled
  public Boolean isRiskAcceptanceExpired;
  @AuraEnabled
  public String falsePositiveJustification;
  @AuraEnabled
  public String computeRunId;
  @AuraEnabled
  public Boolean hasAutomaticAction;
  @AuraEnabled
  public String requiredPermission;
}
