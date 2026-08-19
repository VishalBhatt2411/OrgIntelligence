/**
 * Purpose: Persisted/wire/cache representation shaping (GraphEngine.md §8) — the
 *          facade-internal component that builds an OI_GraphFragment from
 *          OI_Node/OI_Edge results.
 * Responsibilities: Reachable only through OI_GraphEngine (ADR-0013). Nothing outside
 *                    the facade constructs a GraphFragment directly.
 * Dependencies: None (pure shaping over already-fetched data).
 * Limitations: Sprint 7 scope is the seam only — nothing yet produces the node/edge
 *              sets this class would shape (OI_GraphTraversal ships in Roadmap Phase 2).
 */
public class OI_GraphSerializer {
    /** Shapes a bounded node/edge result set into the wire-level OI_GraphFragment (GraphEngine.md §4). */
    public OI_GraphFragment toFragment(
        String centerNodeKey,
        List<OI_Node> nodes,
        List<OI_Edge> edges,
        List<String> frontier,
        Boolean hasMore,
        String nextCursor
    ) {
        List<OI_NodeSummary> nodeSummaries = new List<OI_NodeSummary>();
        for (OI_Node node : nodes) {
            nodeSummaries.add(new OI_NodeSummary(node.nodeKey, node.typeKey, node.label, node.secondaryKey, node.state));
        }
        List<OI_EdgeSummary> edgeSummaries = new List<OI_EdgeSummary>();
        for (OI_Edge edge : edges) {
            edgeSummaries.add(new OI_EdgeSummary(edge.edgeKey, edge.typeKey, edge.sourceNodeKey, edge.targetNodeKey));
        }
        return new OI_GraphFragment(centerNodeKey, nodeSummaries, edgeSummaries, frontier, hasMore, nextCursor);
    }
}
