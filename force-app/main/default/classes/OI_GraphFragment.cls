/**
 * Purpose: The sole shape ever returned across the Graph Engine's public boundary
 *          (GraphEngine.md §4) — a bounded, paginated slice of the graph.
 * Responsibilities: Carry nodes/edges plus a frontier (nodes with unexplored neighbors) and
 *                    pagination state. Never "the whole graph."
 * Dependencies: OI_NodeSummary, OI_EdgeSummary.
 * Limitations: Construction/population is OI_GraphSerializer's job (GraphEngine.md §8) — this
 *              class only defines the shape.
 */
public class OI_GraphFragment {
    public final String centerNodeKey;
    public final List<OI_NodeSummary> nodes;
    public final List<OI_EdgeSummary> edges;
    public final List<String> frontier;
    public final Boolean hasMore;
    public final String nextCursor;

    public OI_GraphFragment(
        String centerNodeKey,
        List<OI_NodeSummary> nodes,
        List<OI_EdgeSummary> edges,
        List<String> frontier,
        Boolean hasMore,
        String nextCursor
    ) {
        this.centerNodeKey = centerNodeKey;
        this.nodes = nodes == null ? new List<OI_NodeSummary>() : nodes;
        this.edges = edges == null ? new List<OI_EdgeSummary>() : edges;
        this.frontier = frontier == null ? new List<String>() : frontier;
        this.hasMore = hasMore == null ? false : hasMore;
        this.nextCursor = nextCursor;
    }
}
