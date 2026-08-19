/**
 * Purpose: The bounded result of OI_HierarchyQueryService.getDescendants — a relationship
 *          list plus an honest "more exist beyond the bound" flag, mirroring OI_GraphFragment's
 *          hasMore convention rather than a silent truncation.
 * Dependencies: None.
 * Limitations: None.
 */
public class OI_HierarchyDescendantsResult {
    public final List<OI_Hierarchy_Relationship__c> descendants;
    public final Boolean hasMore;

    public OI_HierarchyDescendantsResult(List<OI_Hierarchy_Relationship__c> descendants, Boolean hasMore) {
        this.descendants = descendants == null ? new List<OI_Hierarchy_Relationship__c>() : descendants;
        this.hasMore = hasMore == null ? false : hasMore;
    }
}
