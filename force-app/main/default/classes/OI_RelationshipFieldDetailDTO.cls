/**
 * Purpose: The @AuraEnabled wire shape for the Object panel's reworked Relationships section
 *          (outgoing side) — a list of OI_RelationshipFieldDTO rows. Never carries record
 *          counts itself; those are resolved on demand via OI_TargetObjectRecordCountsDTO (see
 *          OI_RelationshipFieldDetailService's own doc comment for why counts are a separate,
 *          explicit round-trip rather than part of this read).
 * Responsibilities: Carry the field rows. Pure data; all derivation lives in
 *                    OI_RelationshipFieldDetailService.
 * Dependencies: OI_RelationshipFieldDTO.
 * Limitations: None.
 */
public class OI_RelationshipFieldDetailDTO {
  @AuraEnabled
  public List<OI_RelationshipFieldDTO> fields;

  public OI_RelationshipFieldDetailDTO(List<OI_RelationshipFieldDTO> fields) {
    this.fields = fields == null ? new List<OI_RelationshipFieldDTO>() : fields;
  }
}
