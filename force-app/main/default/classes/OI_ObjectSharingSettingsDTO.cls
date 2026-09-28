/**
 * Purpose: The @AuraEnabled wire shape for one object's own Sharing Settings (Org-Wide
 *          Default) — the Object Intelligence Panel's Sharing Settings section, and this
 *          platform's first Tooling-API-sourced fact (Apex Describe has no accessor for
 *          sharing model at all — see OI_ObjectScanner's own documented gap and
 *          OI_ToolingApiAdapter's own doc comment).
 * Responsibilities: Carry the object's internal and external sharing model, or an honest
 *                    unavailable reason when the Tooling API could not answer (a describe-
 *                    accessible object can still be un-introspectable this way — same "report
 *                    unsupported rather than fail the whole panel" convention as
 *                    OI_RecordSharingDTO.supportsSharing). Pure data; all resolution lives in
 *                    OI_ObjectSharingSettingsService.
 * Dependencies: None.
 * Limitations: Internal/external sharing MODEL only (e.g. "Private", "ReadWrite",
 *              "ControlledByParent") — sharing RULES (criteria-based, owner-based) are a
 *              separate, unbuilt capability this DTO does not attempt. Never cached: OWD is
 *              admin-changeable at any time, and this platform's own convention (see
 *              OI_RelationshipFieldDetailDTO) is that a fact an admin can change stays a live
 *              read rather than a scanned/cached one.
 */
public class OI_ObjectSharingSettingsDTO {
  /** False when the Tooling API could not resolve a sharing model for this object at all (see unavailableReason) — never a fabricated default. */
  @AuraEnabled
  public Boolean supported;
  /** Explains a false supported — a Tooling API/permission failure, or this object's EntityDefinition genuinely has no answer. Null whenever supported is true. */
  @AuraEnabled
  public String unavailableReason;
  /** EntityDefinition.InternalSharingModel — e.g. Private, Read, ReadWrite, ReadWriteTransfer, ControlledByParent, ControlledByCampaign, ControlledByLeadOrContact, FullAccess. The platform's own vocabulary, never reworded. */
  @AuraEnabled
  public String internalSharingModel;
  /** EntityDefinition.ExternalSharingModel — null when External Sharing Model is not enabled for this object/org edition (a real, common case, not an error). */
  @AuraEnabled
  public String externalSharingModel;

  public OI_ObjectSharingSettingsDTO(
    Boolean supported,
    String unavailableReason,
    String internalSharingModel,
    String externalSharingModel
  ) {
    this.supported = supported == null ? false : supported;
    this.unavailableReason = unavailableReason;
    this.internalSharingModel = internalSharingModel;
    this.externalSharingModel = externalSharingModel;
  }
}
