/**
 * Purpose: The sole shape OI_DependencyEngineService.getImpact returns (Architecture.md §7) —
 *          a bounded subgraph plus a flat "affected components" list, suitable for both graph
 *          and table rendering.
 * Responsibilities: Carry rootNodeKey/direction/depth (the question asked), subgraph (the
 *                    bounded traversal result, shaped identically to OI_GraphFragment so the
 *                    client's existing merge/"Highlight on Graph" logic needs no new code
 *                    path — GraphUI.md §7), affectedComponents (the flat-list rendering),
 *                    truncated (the node-count ceiling was hit), and coverageCaveat (an
 *                    honest, user-facing statement of what this scan does and does not cover
 *                    yet — GraphUI.md §26/§29's "no silent caps" principle).
 * Dependencies: OI_GraphFragment, OI_AffectedComponent.
 * Limitations: Construction is OI_DependencyEngineService's job — this class only defines
 *              the shape.
 */
public class OI_ImpactResult {
    public final String rootNodeKey;
    public final String direction;
    public final Integer depth;
    public final OI_GraphFragment subgraph;
    public final List<OI_AffectedComponent> affectedComponents;
    public final Boolean truncated;
    public final String coverageCaveat;

    public OI_ImpactResult(
        String rootNodeKey,
        String direction,
        Integer depth,
        OI_GraphFragment subgraph,
        List<OI_AffectedComponent> affectedComponents,
        Boolean truncated,
        String coverageCaveat
    ) {
        this.rootNodeKey = rootNodeKey;
        this.direction = direction;
        this.depth = depth;
        this.subgraph = subgraph;
        this.affectedComponents = affectedComponents == null ? new List<OI_AffectedComponent>() : affectedComponents;
        this.truncated = truncated == null ? false : truncated;
        this.coverageCaveat = coverageCaveat;
    }
}
