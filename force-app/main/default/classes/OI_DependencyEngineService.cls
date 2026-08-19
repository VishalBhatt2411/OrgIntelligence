/**
 * Purpose: Interpretation layer over the Graph Engine's directional traversal primitive
 *          (Architecture.md §7) — forward/reverse Impact Analysis, cycle detection, and the
 *          flat "affected components" list. Reads the graph exclusively through
 *          OI_GraphEngine (ADR-0013) — never OI_GraphTraversal/OI_GraphRepository/
 *          OI_EdgeSelector directly — and never writes it.
 * Responsibilities: getImpact(nodeKey, direction, depth) -> OI_ImpactResult. Checks
 *                    OI_ImpactCacheRepository first (the cache key folds in the root's
 *                    current checksum, mirroring OI_GraphCache's L1 key convention — a new
 *                    version produces a natural miss with no explicit eviction needed); on a
 *                    miss, calls OI_GraphEngine.getImpactSubgraph, runs a BFS hop-distance
 *                    pass and a DFS white/gray/black cycle-detection pass over the
 *                    already-small, already-bounded result (cheap, since the set is bounded
 *                    by construction), builds the flat affected-components list, caches the
 *                    computed result, and returns it. invalidateForScanDelta(...) is DE-7's
 *                    mechanism — callable today, not yet wired into the live scan pipeline
 *                    (see Limitations).
 * Dependencies: OI_GraphEngine, OI_ImpactCacheRepository, OI_SettingsService (all
 *               constructor-injected for testability, ADR-0003).
 * Limitations: Coverage is exactly what the scanners currently discover: Apex class-to-class
 *              REFERENCES (OI_ApexClassScanner, DE-0); Apex trigger-to-class REFERENCES and the
 *              exact trigger-to-object EXECUTES_ON edge (OI_ApexTriggerScanner, DE-9); the
 *              exact record-triggered-Flow-to-object EXECUTES_ON edge (OI_FlowScanner, DE-8
 *              partial); and exact permission-set-to-object/ApexClass GRANTS_ACCESS_TO edges
 *              (OI_PermissionSetScanner, DE-11).
 *              Genuinely NOT covered, and each blocked on named work rather than overlooked:
 *              a Flow's internal field/Apex/subflow references (needs the Flow metadata
 *              definition, reachable only via the still-unbuilt OI_ToolingApiAdapter, MS-2);
 *              Validation Rule field references (same MS-2 blocker, DE-10); FIELD-level
 *              permission grants (FieldPermissions volume needs Batch Apex chunking, DE-11's
 *              own documented follow-up); and Report field usage (DE-12). The practical
 *              consequence worth stating plainly: a Flow that updates a field, or a permission
 *              set that grants access to one, will NOT appear in that FIELD's impact analysis
 *              today, even though the same question about an OBJECT is fully answerable.
 *              Every OI_ImpactResult
 *              this service returns carries a non-null coverageCaveat precisely because of
 *              this, per GraphUI.md §26/§29's "no silent caps" honesty principle — a UI that
 *              hid this fact would overstate what "Impact Analysis" actually covers today.
 *              Cache invalidation (invalidateForScanDelta) only covers a 1-hop neighborhood
 *              of a changed key — a change two or more hops inside an already-cached
 *              subgraph goes stale until Expires_At__c; an accepted, bounded risk, kept
 *              small by a short default TTL (OI_Settings__mdt.Cache_TTL_Minutes__c).
 *              invalidateForScanDelta is not yet called automatically by the scan pipeline
 *              (OI_ScanOrchestratorQueueable/OI_MutationGenerator) — a small, named
 *              follow-up (Backlog.md's Dependency Engine epic), not silently skipped.
 */
public with sharing class OI_DependencyEngineService {
    private static final String COVERAGE_CAVEAT =
        'Impact Analysis covers: Apex class and trigger references (a best-effort name-matching heuristic), the object each Apex trigger and record-triggered Flow fires on, ' +
        'and the objects and Apex classes each permission set grants access to. Not yet covered: what a Flow reads or updates internally, Validation Rule field references, ' +
        'field-level permission grants, and Report field usage.';
    private static final String FORWARD = 'forward';
    private static final String REVERSE = 'reverse';
    /**
     * Every edge type Impact Analysis treats as a dependency. Traversal itself
     * (OI_GraphTraversal) is fully generic over edge type — this set is the ONLY thing that
     * decides what counts as a dependency, so adding a scanner's new edge type here is all
     * that is required to bring it into Impact Analysis (Backlog DE-13).
     *
     * A note on confidence, deliberately recorded next to the set rather than buried in a
     * scanner: REFERENCES edges are a documented regex heuristic (OI_ApexClassScanner /
     * OI_ApexTriggerScanner both say so), whereas EXECUTES_ON is exact — a trigger's target
     * object is declared in source, not inferred. Both are real dependencies and both belong
     * here; the distinction matters only when judging how much to trust a given result row,
     * which is what COVERAGE_CAVEAT exists to communicate to the user.
     */
    private static final Set<String> DEPENDENCY_EDGE_TYPE_KEYS = new Set<String>{
        'SalesforceMetadata.REFERENCES',
        'SalesforceMetadata.EXECUTES_ON',
        'SalesforceMetadata.GRANTS_ACCESS_TO'
    };
    private static final Integer DEFAULT_MAX_DEPTH = 3;
    private static final Integer DEFAULT_MAX_NODE_COUNT = 150;
    private static final Integer DEFAULT_TTL_MINUTES = 15;

    private final OI_GraphEngine graphEngine;
    private final OI_ImpactCacheRepository cacheRepository;
    private final OI_SettingsService settingsService;

    public OI_DependencyEngineService() {
        this(new OI_GraphEngine(), new OI_ImpactCacheRepository(), new OI_SettingsService());
    }

    public OI_DependencyEngineService(OI_GraphEngine graphEngine, OI_ImpactCacheRepository cacheRepository, OI_SettingsService settingsService) {
        this.graphEngine = graphEngine;
        this.cacheRepository = cacheRepository;
        this.settingsService = settingsService;
    }

    public OI_ImpactResult getImpact(String nodeKey, String direction, Integer depth) {
        if (String.isBlank(nodeKey)) {
            throw new OI_ValidationException('A node key is required for Impact Analysis.');
        }
        String effectiveDirection = REVERSE.equalsIgnoreCase(direction) ? REVERSE : FORWARD;
        Boolean isForward = FORWARD.equals(effectiveDirection);
        Integer effectiveDepth = boundedDepth(depth);

        OI_VersionRecord root = graphEngine.getNodeDetail(nodeKey);
        String rootChecksum = root == null ? 'missing' : root.checksum;
        String cacheKey = buildCacheKey(nodeKey, effectiveDirection, effectiveDepth, rootChecksum);

        OI_Impact_Cache__c cached = cacheRepository.getUnexpired(cacheKey);
        if (cached != null) {
            return deserializeResult(cached.Manual_Test_Json__c);
        }

        OI_GraphFragment subgraph = graphEngine.getImpactSubgraph(nodeKey, effectiveDirection, DEPENDENCY_EDGE_TYPE_KEYS, effectiveDepth, boundedNodeCount());

        Map<String, Integer> hopDistanceByKey = computeHopDistances(nodeKey, subgraph, isForward);
        Set<String> cyclicKeys = detectCycleParticipants(subgraph, isForward);

        List<OI_AffectedComponent> affectedComponents = new List<OI_AffectedComponent>();
        for (OI_NodeSummary summary : subgraph.nodes) {
            if (summary.nodeKey == nodeKey) {
                continue;
            }
            affectedComponents.add(
                new OI_AffectedComponent(summary.nodeKey, summary.typeKey, summary.label, hopDistanceByKey.get(summary.nodeKey), cyclicKeys.contains(summary.nodeKey))
            );
        }

        OI_ImpactResult result = new OI_ImpactResult(nodeKey, effectiveDirection, effectiveDepth, subgraph, affectedComponents, subgraph.hasMore, COVERAGE_CAVEAT);

        Datetime now = Datetime.now();
        cacheRepository.put(cacheKey, nodeKey, capitalizeDirection(effectiveDirection), effectiveDepth, JSON.serialize(result), now, now.addMinutes(ttlMinutes()));

        return result;
    }

    /**
     * DE-7: evicts every cached impact result rooted at a node in changedNodeKeys, plus any
     * cached result rooted at a node with a current 1-hop edge (either direction, any type) to
     * one — the documented 1-hop invalidation rule. Reads exclusively through OI_GraphEngine,
     * honoring this service's own "reads the graph exclusively through OI_GraphEngine" rule.
     *
     * Bulk by construction (corrected 2026-08-19, when this was first wired into the live scan
     * pipeline): the 1-hop expansion is ONE call over the whole changed set, costing 2 SOQL
     * queries regardless of set size. The previous implementation looped per changed key at 2
     * queries each — correct in a unit test with 2 keys, but guaranteed to exceed the
     * 100-query transaction limit on any real scan chunk (60 changed keys would have issued
     * 120 queries). It was never exercised at scale because nothing called it; wiring it up is
     * exactly what surfaced this.
     */
    public void invalidateForScanDelta(Set<String> changedNodeKeys) {
        if (changedNodeKeys == null || changedNodeKeys.isEmpty()) {
            return;
        }
        cacheRepository.evictByRootNodeKeys(graphEngine.getOneHopNeighborKeys(changedNodeKeys));
    }

    /** BFS over the already-bounded subgraph's own edges (never a new SOQL round-trip) — hop distance from the root, in the same direction the subgraph was traversed. */
    private Map<String, Integer> computeHopDistances(String rootKey, OI_GraphFragment subgraph, Boolean isForward) {
        Map<String, List<String>> adjacency = buildAdjacency(subgraph, isForward);
        Map<String, Integer> distanceByKey = new Map<String, Integer>{ rootKey => 0 };
        List<String> frontier = new List<String>{ rootKey };
        Integer hop = 0;
        while (!frontier.isEmpty()) {
            hop++;
            List<String> nextFrontier = new List<String>();
            for (String key : frontier) {
                List<String> neighbors = adjacency.get(key);
                if (neighbors == null) {
                    continue;
                }
                for (String neighbor : neighbors) {
                    if (!distanceByKey.containsKey(neighbor)) {
                        distanceByKey.put(neighbor, hop);
                        nextFrontier.add(neighbor);
                    }
                }
            }
            frontier = nextFrontier;
        }
        return distanceByKey;
    }

    /**
     * Classic DFS white/gray/black cycle detection over the already-bounded subgraph — cheap
     * even though it's DFS, since the node/edge set is small by construction (bounded by
     * maxNodeCount before this method ever runs). Every node on a back-edge's cycle is
     * marked, not just the two endpoints of the closing edge.
     */
    private Set<String> detectCycleParticipants(OI_GraphFragment subgraph, Boolean isForward) {
        Map<String, List<String>> adjacency = buildAdjacency(subgraph, isForward);
        Map<String, Integer> color = new Map<String, Integer>();
        Set<String> cyclicKeys = new Set<String>();
        for (String startKey : adjacency.keySet()) {
            if (color.get(startKey) == null) {
                dfsDetectCycle(startKey, adjacency, color, new List<String>(), cyclicKeys);
            }
        }
        return cyclicKeys;
    }

    private void dfsDetectCycle(String key, Map<String, List<String>> adjacency, Map<String, Integer> color, List<String> stack, Set<String> cyclicKeys) {
        color.put(key, 1);
        stack.add(key);
        List<String> neighbors = adjacency.get(key);
        if (neighbors != null) {
            for (String neighbor : neighbors) {
                Integer neighborColor = color.get(neighbor);
                if (neighborColor == null) {
                    dfsDetectCycle(neighbor, adjacency, color, stack, cyclicKeys);
                } else if (neighborColor == 1) {
                    Boolean onCycle = false;
                    for (String stackKey : stack) {
                        if (stackKey == neighbor) {
                            onCycle = true;
                        }
                        if (onCycle) {
                            cyclicKeys.add(stackKey);
                        }
                    }
                }
            }
        }
        stack.remove(stack.size() - 1);
        color.put(key, 2);
    }

    private Map<String, List<String>> buildAdjacency(OI_GraphFragment subgraph, Boolean isForward) {
        Map<String, List<String>> adjacency = new Map<String, List<String>>();
        for (OI_NodeSummary summary : subgraph.nodes) {
            adjacency.put(summary.nodeKey, new List<String>());
        }
        for (OI_EdgeSummary edge : subgraph.edges) {
            String fromKey = isForward ? edge.sourceNodeKey : edge.targetNodeKey;
            String toKey = isForward ? edge.targetNodeKey : edge.sourceNodeKey;
            if (adjacency.containsKey(fromKey)) {
                adjacency.get(fromKey).add(toKey);
            }
        }
        return adjacency;
    }

    /** Mirrors OI_GraphCache.buildFragmentCacheKey's exact convention (Architecture §11) — folding the root's current checksum in means a new version is a natural miss, no explicit eviction required for "the origin itself changed." */
    private String buildCacheKey(String nodeKey, String direction, Integer depth, String checksum) {
        String raw = nodeKey + ':' + direction + ':' + depth + ':' + checksum;
        Blob hashed = Crypto.generateDigest('SHA-256', Blob.valueOf(raw));
        return EncodingUtil.convertToHex(hashed);
    }

    private String capitalizeDirection(String direction) {
        return REVERSE.equals(direction) ? 'Reverse' : 'Forward';
    }

    private Integer boundedDepth(Integer requested) {
        Integer configuredMax = safeInt(settingsService.getSettings().Max_Impact_Depth__c, DEFAULT_MAX_DEPTH);
        Integer effective = requested == null ? configuredMax : requested;
        return Math.min(Math.max(effective, 1), configuredMax);
    }

    private Integer boundedNodeCount() {
        return safeInt(settingsService.getSettings().Max_Impact_Traversal_Node_Count__c, DEFAULT_MAX_NODE_COUNT);
    }

    private Integer ttlMinutes() {
        return safeInt(settingsService.getSettings().Cache_TTL_Minutes__c, DEFAULT_TTL_MINUTES);
    }

    private Integer safeInt(Decimal value, Integer fallback) {
        return value == null ? fallback : Integer.valueOf(value);
    }

    /** JSON.serialize(result) is safe regardless of OI_ImpactResult's public-final fields (serialization only reads values); reconstruction is the risky direction for a final-field-only class, so this deliberately deserializes untyped and rebuilds every object through its normal constructor rather than JSON.deserialize(json, OI_ImpactResult.class). */
    /** Named jsonText, deliberately, not json — Apex identifiers are case-insensitive, so a local variable literally named json (or JSON) shadows the System.JSON class within this method's scope, breaking every JSON.* call inside it. */
    private OI_ImpactResult deserializeResult(String jsonText) {
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(jsonText);
        OI_GraphFragment subgraph = deserializeFragment((Map<String, Object>) root.get('subgraph'));
        List<OI_AffectedComponent> affectedComponents = new List<OI_AffectedComponent>();
        for (Object rawComponent : (List<Object>) root.get('affectedComponents')) {
            Map<String, Object> componentMap = (Map<String, Object>) rawComponent;
            affectedComponents.add(
                new OI_AffectedComponent(
                    (String) componentMap.get('nodeKey'),
                    (String) componentMap.get('typeKey'),
                    (String) componentMap.get('label'),
                    asInteger(componentMap.get('hopDistance')),
                    (Boolean) componentMap.get('isInCycle')
                )
            );
        }
        return new OI_ImpactResult(
            (String) root.get('rootNodeKey'),
            (String) root.get('direction'),
            asInteger(root.get('depth')),
            subgraph,
            affectedComponents,
            (Boolean) root.get('truncated'),
            (String) root.get('coverageCaveat')
        );
    }

    private OI_GraphFragment deserializeFragment(Map<String, Object> fragmentMap) {
        if (fragmentMap == null) {
            return new OI_GraphFragment(null, new List<OI_NodeSummary>(), new List<OI_EdgeSummary>(), new List<String>(), false, null);
        }
        List<OI_NodeSummary> nodes = new List<OI_NodeSummary>();
        for (Object rawNode : (List<Object>) fragmentMap.get('nodes')) {
            Map<String, Object> nodeMap = (Map<String, Object>) rawNode;
            nodes.add(
                new OI_NodeSummary((String) nodeMap.get('nodeKey'), (String) nodeMap.get('typeKey'), (String) nodeMap.get('label'), (String) nodeMap.get('secondaryKey'), (String) nodeMap.get('state'))
            );
        }
        List<OI_EdgeSummary> edges = new List<OI_EdgeSummary>();
        for (Object rawEdge : (List<Object>) fragmentMap.get('edges')) {
            Map<String, Object> edgeMap = (Map<String, Object>) rawEdge;
            edges.add(new OI_EdgeSummary((String) edgeMap.get('edgeKey'), (String) edgeMap.get('typeKey'), (String) edgeMap.get('sourceNodeKey'), (String) edgeMap.get('targetNodeKey')));
        }
        List<String> frontier = new List<String>();
        for (Object rawKey : (List<Object>) fragmentMap.get('frontier')) {
            frontier.add((String) rawKey);
        }
        return new OI_GraphFragment((String) fragmentMap.get('centerNodeKey'), nodes, edges, frontier, (Boolean) fragmentMap.get('hasMore'), (String) fragmentMap.get('nextCursor'));
    }

    private Integer asInteger(Object value) {
        return value == null ? null : Integer.valueOf((Decimal) value);
    }
}
