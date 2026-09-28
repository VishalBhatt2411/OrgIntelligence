/**
 * Purpose: The @AuraEnabled wire shape for the Object panel's on-demand "Load record counts"
 *          action on the Relationships section — a live COUNT() per distinct target object,
 *          requested explicitly rather than computed inline (see
 *          OI_RelationshipFieldDetailService's own doc comment for why).
 * Responsibilities: Carry the resolved counts, keyed by object API name, and an honest
 *                    truncation flag when more distinct target objects were requested than the
 *                    service will resolve in one call. Pure data; all derivation lives in
 *                    OI_RelationshipFieldDetailService.
 * Dependencies: None.
 * Limitations: A missing key in countsByObjectApiName means that object's count could not be
 *              resolved (inaccessible, unqueryable, or beyond the bound) — never a fabricated
 *              zero, mirroring OI_RelationshipFieldDTO.TargetObjectCardinality's own convention.
 */
public class OI_TargetObjectRecordCountsDTO {
  @AuraEnabled
  public Map<String, Integer> countsByObjectApiName;
  /** True when more distinct target objects were requested than the service resolves in one call — those beyond the bound are simply absent from countsByObjectApiName, never silently dropped without explanation. */
  @AuraEnabled
  public Boolean truncated;

  public OI_TargetObjectRecordCountsDTO(
    Map<String, Integer> countsByObjectApiName,
    Boolean truncated
  ) {
    this.countsByObjectApiName = countsByObjectApiName == null
      ? new Map<String, Integer>()
      : countsByObjectApiName;
    this.truncated = truncated == null ? false : truncated;
  }
}
