/**
 * Purpose: What a domain Health Service (Metadata/Automation/Code/Security/Data Health)
 *          currently believes about one finding, right now, in this scan (ADR-0027) — the
 *          input side of the unified finding model. Never returned to the client directly;
 *          OI_OrgHealthFindingRepository consumes it to upsert OI_Org_Health_Finding__c by
 *          fingerprint.
 * Responsibilities: Carry every fact a rule computes about one detected condition — evidence,
 *                    explanation, org-specific risk, impact, remediation, and validation —
 *                    so "answer the 5 questions" is enforced at the type level: a Health
 *                    Service literally cannot build a candidate without populating them.
 * Dependencies: None.
 * Limitations: Deliberately excludes every lifecycle field (status, owner, notes, due date,
 *              compensating control, resolution evidence, first/last detected) — those belong
 *              to the persisted record's own history, never to a fresh scan's opinion, and
 *              OI_OrgHealthFindingRepository never lets a candidate overwrite them.
 */
public class OI_OrgHealthFindingCandidate {
  public String sectionKey;
  public String ruleId;
  public Integer ruleVersion = 1;
  public String title;
  public String severityKey;
  /** The multi-signal badness score (0-100, higher = worse) OI_HealthScoringEngine computed for this finding — null for a rule that has not yet been ported onto the shared engine. */
  public Decimal score;
  /** One-line "why this severity" summary from the same engine call that produced score/severityKey. */
  public String scoreExplanation;
  /** JSON-serialized List<OI_HealthScoreContributor> — the full per-signal breakdown the finding drawer renders. */
  public String scoreContributorsJson;
  public String confidence;
  public String componentKey;
  public String componentType;
  public String componentLabel;
  public String namespace;
  public Boolean isManaged = false;
  public String evidence;
  public String measuredValue;
  public String expectedValue;
  public String explanation;
  public String orgRisk;
  public String potentialImpact;
  public String remediation;
  public String validationSteps;
}
