/**
 * Purpose: The single public entry point for anything graph-related (GraphEngine.md §1.1,
 *          ADR-0013). External application code — Controllers, other Services, the
 *          Metadata Scanner subsystem — interacts with the Graph Engine only through
 *          this class.
 * Responsibilities: A thin pass-through facade composing five internal, single-
 *                    responsibility components (OI_GraphBuilder, OI_GraphTraversal,
 *                    OI_GraphRepository, OI_GraphSerializer, OI_GraphCache). Contains no
 *                    business logic of its own — every method routes to exactly one
 *                    (occasionally two) internal component and returns its result.
 * Dependencies: OI_GraphBuilder, OI_GraphTraversal, OI_GraphRepository, OI_GraphSerializer,
 *               OI_GraphCache (all constructor-injected for testability, ADR-0003).
 * Limitations: nothing outside this class references OI_GraphBuilder, OI_GraphTraversal,
 *              OI_GraphRepository, OI_GraphSerializer, or OI_GraphCache by name
 *              (CodingStandards.md §2) — a review blocker if violated. ingest() is fully
 *              implemented as of Sprint 8 (OI_GraphBuilder's three-way version decision).
 *              getGraphFragment() is implemented as of Sprint 10 (OI_GraphTraversal's real
 *              BFS expand, completing the Roadmap Phase 2 seam Sprint 7/8 deliberately left
 *              as a stub).
 */
public class OI_GraphEngine {
    private final OI_GraphBuilder builder;
    private final OI_GraphTraversal traversal;
    private final OI_GraphRepository repository;
    private final OI_GraphSerializer serializer;
    private final OI_GraphCache cache;

    public OI_GraphEngine() {
        this(new OI_GraphRepository());
    }

    private OI_GraphEngine(OI_GraphRepository repository) {
        this(new OI_GraphBuilder(repository), new OI_GraphTraversal(repository), repository, new OI_GraphSerializer(), new OI_GraphCache());
    }

    public OI_GraphEngine(
        OI_GraphBuilder builder,
        OI_GraphTraversal traversal,
        OI_GraphRepository repository,
        OI_GraphSerializer serializer,
        OI_GraphCache cache
    ) {
        this.builder = builder;
        this.traversal = traversal;
        this.repository = repository;
        this.serializer = serializer;
        this.cache = cache;
    }

    /** Ingests a bulk Mutation batch and passes through what genuinely changed (OI_IngestDelta). Delegates entirely to OI_GraphBuilder (GraphEngine.md §7) — this facade adds no logic of its own (ADR-0013), including none of its own change detection. */
    public OI_IngestDelta ingest(List<OI_GraphMutation> mutations) {
        return builder.ingest(mutations);
    }

    /** Bulk 1-hop neighborhood of a whole key set (both directions, keys only) — delegates entirely to OI_GraphTraversal. Used by scan-delta cache invalidation, which must not degrade into per-key traversal; see that method's own doc comment for the limit arithmetic. */
    public Set<String> getOneHopNeighborKeys(Set<String> nodeKeys) {
        return traversal.getOneHopNeighborKeys(nodeKeys);
    }

    /** Fetches a bounded graph fragment. Delegates entirely to OI_GraphTraversal (GraphEngine.md §12). */
    public OI_GraphFragment getGraphFragment(String nodeKey, Integer hopDepth, Map<String, String> knownChecksums) {
        return traversal.expand(nodeKey, hopDepth, knownChecksums);
    }

    /** Paginated overload (Sprint 10) — GraphEngine.md §18's documented pageCursor input, for a hub node's "load more neighbors" (GraphUI.md §15). */
    public OI_GraphFragment getGraphFragment(String nodeKey, Integer hopDepth, String pageCursor, Map<String, String> knownChecksums) {
        return traversal.expand(nodeKey, hopDepth, pageCursor, knownChecksums);
    }

    /** Fetches the current version for a node key. Delegates entirely to OI_GraphRepository. */
    public OI_VersionRecord getNodeDetail(String nodeKey) {
        Map<String, OI_VersionRecord> results = repository.getCurrentVersions(new Set<String>{ nodeKey }, false);
        return results.get(nodeKey);
    }

    /**
     * Read-only, paginated enumeration of every currently-Active key for a type — the
     * operation OI_MutationGenerator's retire-detection needs (MetadataScanner.md §15,
     * GraphRepository.md §2/§9). Delegates entirely to OI_GraphRepository; added this
     * sprint to close a real gap between MetadataScanner.md §15's explicit requirement
     * ("a read-only, paginated call to OI_GraphEngine") and the Sprint 7 facade, which did
     * not yet expose it.
     */
    public OI_KeysPage getCurrentActiveKeysByType(String typeKey, String cursor, Integer pageSize, Boolean isEdgeFlavor) {
        return repository.getCurrentKeysByType(typeKey, cursor, pageSize, isEdgeFlavor);
    }

    /**
     * Directional, edge-type-filtered subgraph — the Dependency Engine's read primitive
     * (OI_DependencyEngineService, the only caller). Delegates entirely to
     * OI_GraphTraversal.traverseDirectional (GraphEngine.md §12 elaborated for Impact
     * Analysis) — this facade method adds no logic of its own, exactly like every other
     * method here (ADR-0013).
     */
    public OI_GraphFragment getImpactSubgraph(String nodeKey, String direction, Set<String> edgeTypeKeys, Integer maxDepth, Integer maxNodeCount) {
        return traversal.traverseDirectional(nodeKey, direction, edgeTypeKeys, maxDepth, maxNodeCount);
    }

    /**
     * Structural relationship counts for a node, grouped by edge type and direction — the
     * one real, honest number available today in place of a full Impact/Dependency Engine
     * (Roadmap Phase 4, not yet built). Reads directly via OI_EdgeSelector rather than
     * round-tripping through OI_GraphRepository/StorageProvider, mirroring OI_GraphTraversal's
     * own established precedent for edge reads (Sprint 10) — aggregate counts are meaningful
     * only for current-state edges, never archived history, so the Repository's
     * archive-aware abstraction has nothing to add here.
     */
    public OI_RelationshipCounts getRelationshipCounts(String nodeKey) {
        OI_EdgeSelector edgeSelector = new OI_EdgeSelector();
        return new OI_RelationshipCounts(
            edgeSelector.countCurrentBySourceKeyGroupedByType(nodeKey),
            edgeSelector.countCurrentByTargetKeyGroupedByType(nodeKey)
        );
    }

    /**
     * Bulk lookup of every node directly reachable from parentNodeKey via an edge of exactly
     * edgeTypeKey — a generic "get this node's typed members" read, deliberately unaware of
     * what edgeTypeKey means (the caller supplies it, e.g. a Salesforce-metadata-domain
     * caller passing its own field-membership edge type key to list an object's fields; the
     * Engine itself never hardcodes a domain-specific type string, GraphEngine.md §1's
     * genericity rule). Reads edges via OI_EdgeSelector directly — the same real-SOQL
     * precedent getRelationshipCounts above already established for this Engine — then
     * resolves the member keys through the injected Repository so member lookups stay
     * mockable exactly like getNodeDetail's.
     */
    public List<OI_VersionRecord> getMembersByEdgeType(String parentNodeKey, String edgeTypeKey) {
        OI_EdgeSelector edgeSelector = new OI_EdgeSelector();
        List<OI_Graph_Edge__c> edges = edgeSelector.selectCurrentBySourceKeys(new Set<String>{ parentNodeKey });
        Set<String> memberKeys = new Set<String>();
        for (OI_Graph_Edge__c edge : edges) {
            if (edge.Edge_Type__c == edgeTypeKey) {
                memberKeys.add(edge.Target_Node_Key__c);
            }
        }
        if (memberKeys.isEmpty()) {
            return new List<OI_VersionRecord>();
        }
        return repository.getCurrentVersions(memberKeys, false).values();
    }
}
