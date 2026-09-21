/**
 * Purpose: The @AuraEnabled wire shape for the Object panel's reworked Relationships section
 *          (outgoing side) — a list of OI_RelationshipFieldDTO rows plus an honest truncation
 *          flag, mirroring OI_RecordSharingDTO's own "never silently cap" convention.
 * Responsibilities: Carry the field rows and whether the live cardinality lookups were bounded.
 *                    Pure data; all derivation lives in OI_RelationshipFieldDetailService.
 * Dependencies: OI_RelationshipFieldDTO.
 * Limitations: None.
 */
public class OI_RelationshipFieldDetailDTO {
  @AuraEnabled
  public List<OI_RelationshipFieldDTO> fields;
  /** True when this object has more distinct target objects across its relationship fields than MAX_TARGET_OBJECTS_FOR_CARDINALITY — those beyond the bound still appear as rows, just without a record count, rather than being dropped. */
  @AuraEnabled
  public Boolean cardinalityTruncated;

  public OI_RelationshipFieldDetailDTO(
    List<OI_RelationshipFieldDTO> fields,
    Boolean cardinalityTruncated
  ) {
    this.fields = fields == null ? new List<OI_RelationshipFieldDTO>() : fields;
    this.cardinalityTruncated = cardinalityTruncated == null
      ? false
      : cardinalityTruncated;
  }
}
