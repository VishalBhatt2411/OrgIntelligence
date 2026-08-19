/**
 * Purpose: The @AuraEnabled wire shape for OI_GraphFragment (API.md §2.1, GraphEngine.md
 *          §18) — the sole shape OI_GraphController.getGraphFragment returns.
 * Responsibilities: Map every field of the plain Apex OI_GraphFragment (and its
 *                    nodes[]/edges[]) into its @AuraEnabled DTO equivalent.
 * Dependencies: OI_GraphFragment, OI_NodeSummaryDTO, OI_EdgeSummaryDTO.
 * Limitations: retiredKeys[] (GraphEngine.md §18's documented output field) is not carried
 *              — OI_GraphFragment itself has no such field yet (a pre-existing gap between
 *              that table and the shipped class, not introduced by Sprint 10).
 */
public class OI_GraphFragmentDTO {
    @AuraEnabled
    public String centerNodeKey;
    @AuraEnabled
    public List<OI_NodeSummaryDTO> nodes;
    @AuraEnabled
    public List<OI_EdgeSummaryDTO> edges;
    @AuraEnabled
    public List<String> frontier;
    @AuraEnabled
    public Boolean hasMore;
    @AuraEnabled
    public String nextCursor;

    public OI_GraphFragmentDTO(OI_GraphFragment fragment) {
        this.centerNodeKey = fragment.centerNodeKey;
        this.nodes = new List<OI_NodeSummaryDTO>();
        for (OI_NodeSummary summary : fragment.nodes) {
            this.nodes.add(new OI_NodeSummaryDTO(summary));
        }
        this.edges = new List<OI_EdgeSummaryDTO>();
        for (OI_EdgeSummary summary : fragment.edges) {
            this.edges.add(new OI_EdgeSummaryDTO(summary));
        }
        this.frontier = fragment.frontier;
        this.hasMore = fragment.hasMore;
        this.nextCursor = fragment.nextCursor;
    }
}
