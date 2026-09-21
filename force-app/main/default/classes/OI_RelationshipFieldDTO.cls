/**
 * Purpose: One outgoing Lookup/Master-Detail field on an Object node, for the Intelligence
 *          Panel's reworked Relationships section (replacing the flat "Outgoing Lookups — N"
 *          count with the actual fields behind it — see OI_RelationshipFieldDetailService's own
 *          doc comment for why).
 * Responsibilities: Carry one field's relationship shape — type, required-ness, cascade-delete
 *                    behavior where knowable, and its target object(s) with a live record count
 *                    each. Pure data; all derivation lives in OI_RelationshipFieldDetailService.
 * Dependencies: None.
 * Limitations: cascadeDeleteBehavior is populated only for Master-Detail ('Cascade', a fixed
 *              platform invariant); a Lookup field's own configured delete constraint
 *              (Clear/Restrict/Cascade-on-special-lookups) is Metadata/Tooling API-only
 *              information with no Apex Describe accessor (same category of gap OI_ObjectScanner
 *              already documents for sharing model) — left null rather than guessed.
 */
public class OI_RelationshipFieldDTO {
  public class TargetObjectCardinality {
    @AuraEnabled
    public String objectApiName;
    /** Null when the count could not be resolved (object inaccessible, unqueryable, or beyond MAX_TARGET_OBJECTS_FOR_CARDINALITY) — never a fabricated zero. */
    @AuraEnabled
    public Integer recordCount;

    public TargetObjectCardinality(String objectApiName, Integer recordCount) {
      this.objectApiName = objectApiName;
      this.recordCount = recordCount;
    }
  }

  @AuraEnabled
  public String fieldNodeKey;
  @AuraEnabled
  public String label;
  @AuraEnabled
  public String apiName;
  /** 'Lookup' or 'Master-Detail' — never the raw internal edge-type taxonomy (LOOKUP_TO/MASTER_DETAIL_TO), matching this whole panel's existing curated-label convention. */
  @AuraEnabled
  public String relationshipType;
  @AuraEnabled
  public Boolean isRequired;
  @AuraEnabled
  public String cascadeDeleteBehavior;
  /** Plural because a polymorphic field (WhatId/OwnerId-style) can reference more than one object — collapsing that into a single count, as the old aggregate did, loses exactly this distinction. */
  @AuraEnabled
  public List<TargetObjectCardinality> targetObjects;

  public OI_RelationshipFieldDTO(
    String fieldNodeKey,
    String label,
    String apiName,
    String relationshipType,
    Boolean isRequired,
    String cascadeDeleteBehavior,
    List<TargetObjectCardinality> targetObjects
  ) {
    this.fieldNodeKey = fieldNodeKey;
    this.label = label;
    this.apiName = apiName;
    this.relationshipType = relationshipType;
    this.isRequired = isRequired;
    this.cascadeDeleteBehavior = cascadeDeleteBehavior;
    this.targetObjects = targetObjects == null
      ? new List<TargetObjectCardinality>()
      : targetObjects;
  }
}
