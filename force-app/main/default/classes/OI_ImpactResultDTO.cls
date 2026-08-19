/**
 * Purpose: The @AuraEnabled wire shape for OI_ImpactResult (Architecture.md §7,
 *          API.md-adjacent) — the sole shape OI_DependencyController.getImpact returns.
 * Responsibilities: Map every field of OI_ImpactResult, including its nested subgraph, into
 *                    its @AuraEnabled DTO equivalent. subgraph is deliberately typed as the
 *                    already-existing OI_GraphFragmentDTO (not a new nested shape) — exactly
 *                    so the client's existing GraphViewState "Highlight on Graph" merge
 *                    (graphViewState.js's applyExpand) can consume impactResult.subgraph
 *                    unchanged, with zero new client-side transformation code (GraphUI.md §7).
 * Dependencies: OI_ImpactResult, OI_GraphFragmentDTO, OI_AffectedComponentDTO.
 * Limitations: None.
 */
public class OI_ImpactResultDTO {
    @AuraEnabled
    public String rootNodeKey;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public Integer depth;
    @AuraEnabled
    public OI_GraphFragmentDTO subgraph;
    @AuraEnabled
    public List<OI_AffectedComponentDTO> affectedComponents;
    @AuraEnabled
    public Boolean truncated;
    @AuraEnabled
    public String coverageCaveat;

    public OI_ImpactResultDTO(OI_ImpactResult result) {
        this.rootNodeKey = result.rootNodeKey;
        this.direction = result.direction;
        this.depth = result.depth;
        this.subgraph = new OI_GraphFragmentDTO(result.subgraph);
        this.affectedComponents = new List<OI_AffectedComponentDTO>();
        for (OI_AffectedComponent component : result.affectedComponents) {
            this.affectedComponents.add(new OI_AffectedComponentDTO(component));
        }
        this.truncated = result.truncated;
        this.coverageCaveat = result.coverageCaveat;
    }
}
