/**
 * Purpose: The @AuraEnabled wire shape for OI_HierarchyDescendantsResult — an honest
 *          hasMore flag alongside the relationship list, never a silent truncation.
 * Dependencies: OI_HierarchyDescendantsResult, OI_HierarchyRelationshipDTO.
 * Limitations: None.
 */
public class OI_HierarchyDescendantsResultDTO {
    @AuraEnabled
    public List<OI_HierarchyRelationshipDTO> descendants;
    @AuraEnabled
    public Boolean hasMore;

    public OI_HierarchyDescendantsResultDTO(List<OI_HierarchyRelationshipDTO> descendants, Boolean hasMore) {
        this.descendants = descendants == null ? new List<OI_HierarchyRelationshipDTO>() : descendants;
        this.hasMore = hasMore == null ? false : hasMore;
    }
}
