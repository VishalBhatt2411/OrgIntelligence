/**
 * Purpose: BFS traversal over Repository-supplied edge sets (GraphEngine.md §12) —
 *          expand/filter, the traversal primitive the Graph UI's expand action is built on
 *          (Sprint 10, completing the Sprint 7 seam).
 * Responsibilities: Reachable only through OI_GraphEngine (ADR-0013). Every read is
 *                    implicitly scoped to isCurrent = true, via OI_GraphRepository/
 *                    OI_NodeSelector/OI_EdgeSelector. Bounds every call by both hop depth
 *                    and total node count (GraphEngine.md §12 — whichever ceiling is hit
 *                    first stops the ring loop; the node-count ceiling is then applied
 *                    precisely via pagination over the revealed key set, never a silent
 *                    truncation without hasMore/nextCursor).
 * Dependencies: OI_GraphRepository, OI_NodeSelector, OI_EdgeSelector, OI_SettingsService.
 * Limitations: nodeTypeFilter[]/edgeTypeFilter[] (GraphEngine.md §18's documented input
 *              shape) are not implemented — deferred alongside oiFilterPanel (Backlog
 *              UI-4, tagged Phase 3), consistent with Sprint 10's MVP scope. retiredKeys[]
 *              (the same table's documented output) is not implemented either — this
 *              requires the client's full held-key set for a neighborhood, which nothing
 *              in the current API.md/GraphUI.md contract actually passes, and
 *              OI_GraphFragment itself has no field for it; a pre-existing spec gap, not
 *              one introduced here. knownChecksums is honored (a node whose current
 *              checksum matches is omitted from nodes[]) but the Sprint 10 LWC client
 *              always passes an empty map, since OI_NodeSummary itself carries no checksum
 *              for the client to track — GraphEngine.md §9's incremental-loading mechanism
 *              is accepted at this layer for contract fidelity and future wiring, not yet
 *              exercised end-to-end.
 */
public class OI_GraphTraversal {
    private static final Integer DEFAULT_HOP_DEPTH = 1;
    private static final Integer DEFAULT_MAX_NODE_COUNT = 50;

    private final OI_GraphRepository repository;
    private final OI_NodeSelector nodeSelector;
    private final OI_EdgeSelector edgeSelector;

    public OI_GraphTraversal() {
        this(new OI_GraphRepository());
    }

    public OI_GraphTraversal(OI_GraphRepository repository) {
        this.repository = repository;
        this.nodeSelector = new OI_NodeSelector();
        this.edgeSelector = new OI_EdgeSelector();
    }

    /** Convenience overload — no pagination cursor, starting from the first page. */
    public OI_GraphFragment expand(String nodeKey, Integer hopDepth, Map<String, String> knownChecksums) {
        return expand(nodeKey, hopDepth, null, knownChecksums);
    }

    /**
     * Expands nodeKey by up to hopDepth hops (bounded, GraphEngine.md §11/§12).
     * hopDepth == 0 is a special case (GraphUI.md §8/§9): resolve exactly the center node
     * itself, no neighbors — the zero-hop fetch a search/breadcrumb selection uses.
     */
    public OI_GraphFragment expand(String nodeKey, Integer hopDepth, String pageCursor, Map<String, String> knownChecksums) {
        if (String.isBlank(nodeKey)) {
            return new OI_GraphFragment(nodeKey, new List<OI_NodeSummary>(), new List<OI_EdgeSummary>(), new List<String>(), false, null);
        }

        Integer effectiveHopDepth = boundedHopDepth(hopDepth);
        if (effectiveHopDepth == 0) {
            return expandZeroHop(nodeKey);
        }

        Integer maxNodeCount = boundedNodeCount();
        Set<String> visited = new Set<String>{ nodeKey };
        Set<String> currentRing = new Set<String>{ nodeKey };
        Map<String, OI_Graph_Edge__c> edgesByKey = new Map<String, OI_Graph_Edge__c>();
        Set<String> revealedKeys = new Set<String>();

        for (Integer hop = 0; hop < effectiveHopDepth && !currentRing.isEmpty(); hop++) {
            Set<String> nextRing = new Set<String>();
            collectRing(currentRing, edgesByKey, revealedKeys, visited, nextRing);
            visited.addAll(nextRing);
            currentRing = nextRing;
            if (visited.size() > maxNodeCount) {
                break;
            }
        }
        revealedKeys.remove(nodeKey);

        List<String> sortedRevealedKeys = new List<String>(revealedKeys);
        sortedRevealedKeys.sort();
        PageWindow page = paginate(sortedRevealedKeys, pageCursor, maxNodeCount);

        Set<String> keysToHydrate = new Set<String>(page.keys);
        keysToHydrate.add(nodeKey);
        Map<String, OI_VersionRecord> versions = repository.getCurrentVersions(keysToHydrate, false);

        List<OI_NodeSummary> nodes = new List<OI_NodeSummary>();
        addIfChanged(nodes, versions.get(nodeKey), knownChecksums);
        for (String key : page.keys) {
            addIfChanged(nodes, versions.get(key), knownChecksums);
        }

        // Built from resolved *versions*, not raw revealed keys — a revealed key that never
        // resolved to a current version (e.g. a stale edge pointing at a node with no
        // current row) must not make its edge appear visible with a missing endpoint.
        // Deliberately independent of addIfChanged's checksum-elision: a key the client
        // already holds (and was therefore omitted from nodes[]) still counts as visible.
        Set<String> visibleKeys = new Set<String>();
        if (versions.containsKey(nodeKey)) {
            visibleKeys.add(nodeKey);
        }
        for (String key : page.keys) {
            if (versions.containsKey(key)) {
                visibleKeys.add(key);
            }
        }
        List<OI_EdgeSummary> edges = new List<OI_EdgeSummary>();
        for (OI_Graph_Edge__c edge : edgesByKey.values()) {
            if (visibleKeys.contains(edge.Source_Node_Key__c) && visibleKeys.contains(edge.Target_Node_Key__c)) {
                edges.add(
                    new OI_EdgeSummary(edge.Edge_Key__c, edge.Edge_Type__c, edge.Source_Node_Key__c, edge.Target_Node_Key__c, extractViaFieldApiName(edge))
                );
            }
        }

        return new OI_GraphFragment(nodeKey, nodes, edges, page.keys, page.hasMore, page.nextCursor);
    }

    /**
     * Directional, edge-type-filtered BFS — the primitive Impact Analysis needs
     * (OI_DependencyEngineService, reached only through OI_GraphEngine.getImpactSubgraph,
     * ADR-0013) that expand() cannot provide: expand() always walks both edge directions in
     * one ring with no type filter — correct for ordinary UI "show me everything one hop
     * away," wrong for "what does X depend on" (source->target only) vs "what depends on X"
     * (target->source only). Bounded by maxDepth and maxNodeCount exactly like expand()
     * (GraphEngine.md §12) — whichever limit is hit first stops the ring loop, reported via
     * hasMore (true means the node-count ceiling cut exploration short, not that more pages
     * exist to request — this method does not paginate, unlike expand()). Depth-per-node and
     * cycle detection are deliberately NOT computed here — that is traversal *interpretation*,
     * OI_DependencyEngineService's job (Architecture.md §4), operating over this method's
     * already-small, already-bounded result rather than this method growing a
     * dependency-analysis-specific output shape.
     */
    public OI_GraphFragment traverseDirectional(String nodeKey, String direction, Set<String> edgeTypeKeys, Integer maxDepth, Integer maxNodeCount) {
        if (String.isBlank(nodeKey)) {
            return new OI_GraphFragment(nodeKey, new List<OI_NodeSummary>(), new List<OI_EdgeSummary>(), new List<String>(), false, null);
        }
        Integer effectiveMaxDepth = maxDepth == null ? 1 : Math.max(maxDepth, 0);
        Integer effectiveMaxNodeCount = maxNodeCount == null ? DEFAULT_MAX_NODE_COUNT : Math.max(maxNodeCount, 1);
        Boolean isForward = direction != 'reverse';

        Set<String> visited = new Set<String>{ nodeKey };
        Set<String> currentRing = new Set<String>{ nodeKey };
        Map<String, OI_Graph_Edge__c> edgesByKey = new Map<String, OI_Graph_Edge__c>();
        Boolean truncated = false;

        for (Integer hop = 0; hop < effectiveMaxDepth && !currentRing.isEmpty(); hop++) {
            Set<String> nextRing = new Set<String>();
            List<OI_Graph_Edge__c> ringEdges = isForward ? edgeSelector.selectCurrentBySourceKeys(currentRing) : edgeSelector.selectCurrentByTargetKeys(currentRing);
            for (OI_Graph_Edge__c edge : ringEdges) {
                if (edgeTypeKeys != null && !edgeTypeKeys.isEmpty() && !edgeTypeKeys.contains(edge.Edge_Type__c)) {
                    continue;
                }
                String neighborKey = isForward ? edge.Target_Node_Key__c : edge.Source_Node_Key__c;
                edgesByKey.put(edge.Edge_Key__c, edge);
                if (!visited.contains(neighborKey)) {
                    nextRing.add(neighborKey);
                }
            }
            visited.addAll(nextRing);
            currentRing = nextRing;
            if (visited.size() > effectiveMaxNodeCount) {
                truncated = true;
                break;
            }
        }

        Map<String, OI_VersionRecord> versions = repository.getCurrentVersions(visited, false);
        List<OI_NodeSummary> nodes = new List<OI_NodeSummary>();
        for (String key : visited) {
            OI_VersionRecord version = versions.get(key);
            if (version != null) {
                nodes.add(new OI_NodeSummary(version.key, version.typeKey, version.label, version.secondaryKey, version.state));
            }
        }

        List<OI_EdgeSummary> edges = new List<OI_EdgeSummary>();
        for (OI_Graph_Edge__c edge : edgesByKey.values()) {
            if (versions.containsKey(edge.Source_Node_Key__c) && versions.containsKey(edge.Target_Node_Key__c)) {
                edges.add(
                    new OI_EdgeSummary(edge.Edge_Key__c, edge.Edge_Type__c, edge.Source_Node_Key__c, edge.Target_Node_Key__c, extractViaFieldApiName(edge))
                );
            }
        }

        Set<String> revealedKeySet = new Set<String>(visited);
        revealedKeySet.remove(nodeKey);
        return new OI_GraphFragment(nodeKey, nodes, edges, new List<String>(revealedKeySet), truncated, null);
    }

    /**
     * The relationship field an edge travels through, e.g. "AccountId" for a lookup — read from
     * the edge's own stored attributes (`relationshipName`, set by OI_FieldScanner) rather than
     * derived or guessed. Null for every edge kind that carries no such attribute (HAS_FIELD,
     * REFERENCES, EXECUTES_ON, GRANTS_ACCESS_TO) — the graph explorer's "why is this here?" chip
     * must never invent a field name that was not actually scanned.
     */
    private String extractViaFieldApiName(OI_Graph_Edge__c edge) {
        if (String.isBlank(edge.Attributes_Json__c)) {
            return null;
        }
        try {
            Map<String, Object> attributes = (Map<String, Object>) JSON.deserializeUntyped(edge.Attributes_Json__c);
            Object relationshipName = attributes.get('relationshipName');
            return relationshipName == null ? null : String.valueOf(relationshipName);
        } catch (Exception malformedAttributes) {
            /** Malformed stored attributes must never break graph traversal — the edge still renders, just without its optional "via field" context. */
            return null;
        }
    }

    /**
     * Every node within one hop of ANY key in nodeKeys, either direction, as a single bulk
     * pair of reads — the input set itself is included in the result.
     *
     * Exists specifically for scan-delta cache invalidation (DE-7), which needs the 1-hop
     * neighborhood of a whole changed-key SET at once. The obvious alternative — calling a
     * single-node traversal once per changed key — costs 2 SOQL queries PER KEY and blows the
     * per-transaction query limit well before a normal scan chunk's worth of changes (60 keys
     * would issue 120 queries against a ceiling of 100). This costs exactly 2 queries no matter
     * how many keys are passed, which is the same bulk discipline collectRing already uses for
     * an ordinary BFS ring.
     *
     * Deliberately returns only KEYS, not hydrated nodes: the caller evicts cache rows by key
     * and never needs node content, so fetching it would be pure waste.
     */
    public Set<String> getOneHopNeighborKeys(Set<String> nodeKeys) {
        Set<String> neighborKeys = new Set<String>();
        if (nodeKeys == null || nodeKeys.isEmpty()) {
            return neighborKeys;
        }
        neighborKeys.addAll(nodeKeys);
        for (OI_Graph_Edge__c edge : edgeSelector.selectCurrentBySourceKeys(nodeKeys)) {
            neighborKeys.add(edge.Target_Node_Key__c);
        }
        for (OI_Graph_Edge__c edge : edgeSelector.selectCurrentByTargetKeys(nodeKeys)) {
            neighborKeys.add(edge.Source_Node_Key__c);
        }
        return neighborKeys;
    }

    /** One BFS ring: every edge touching currentRing, bulk-selected both directions. */
    private void collectRing(Set<String> currentRing, Map<String, OI_Graph_Edge__c> edgesByKey, Set<String> revealedKeys, Set<String> visited, Set<String> nextRing) {
        for (OI_Graph_Edge__c edge : edgeSelector.selectCurrentBySourceKeys(currentRing)) {
            edgesByKey.put(edge.Edge_Key__c, edge);
            revealedKeys.add(edge.Target_Node_Key__c);
            if (!visited.contains(edge.Target_Node_Key__c)) {
                nextRing.add(edge.Target_Node_Key__c);
            }
        }
        for (OI_Graph_Edge__c edge : edgeSelector.selectCurrentByTargetKeys(currentRing)) {
            edgesByKey.put(edge.Edge_Key__c, edge);
            revealedKeys.add(edge.Source_Node_Key__c);
            if (!visited.contains(edge.Source_Node_Key__c)) {
                nextRing.add(edge.Source_Node_Key__c);
            }
        }
    }

    private class PageWindow {
        List<String> keys = new List<String>();
        Boolean hasMore = false;
        String nextCursor;
    }

    /** Lexicographic-key pagination over the revealed set — deterministic, cursor-resumable, mirrors the pattern already used by OI_NodeSelector/OI_EdgeSelector's own keyset pagination. */
    private PageWindow paginate(List<String> sortedKeys, String cursor, Integer pageSize) {
        Integer startIndex = 0;
        if (String.isNotBlank(cursor)) {
            startIndex = sortedKeys.size();
            for (Integer i = 0; i < sortedKeys.size(); i++) {
                if (sortedKeys[i] > cursor) {
                    startIndex = i;
                    break;
                }
            }
        }
        Integer endIndex = Math.min(startIndex + pageSize, sortedKeys.size());
        PageWindow page = new PageWindow();
        for (Integer i = startIndex; i < endIndex; i++) {
            page.keys.add(sortedKeys[i]);
        }
        page.hasMore = endIndex < sortedKeys.size();
        page.nextCursor = page.hasMore ? page.keys[page.keys.size() - 1] : null;
        return page;
    }

    private void addIfChanged(List<OI_NodeSummary> nodes, OI_VersionRecord version, Map<String, String> knownChecksums) {
        if (version == null) {
            return;
        }
        String knownChecksum = knownChecksums == null ? null : knownChecksums.get(version.key);
        if (knownChecksum != null && knownChecksum == version.checksum) {
            return;
        }
        nodes.add(new OI_NodeSummary(version.key, version.typeKey, version.label, version.secondaryKey, version.state));
    }

    private OI_GraphFragment expandZeroHop(String nodeKey) {
        Map<String, OI_VersionRecord> versions = repository.getCurrentVersions(new Set<String>{ nodeKey }, false);
        OI_VersionRecord center = versions.get(nodeKey);
        List<OI_NodeSummary> nodes = new List<OI_NodeSummary>();
        List<String> frontier = new List<String>();
        if (center != null) {
            nodes.add(new OI_NodeSummary(center.key, center.typeKey, center.label, center.secondaryKey, center.state));
            frontier.add(nodeKey);
        }
        return new OI_GraphFragment(nodeKey, nodes, new List<OI_EdgeSummary>(), frontier, false, null);
    }

    private Integer boundedHopDepth(Integer requested) {
        Integer configuredMax = safeInt(new OI_SettingsService().getSettings().Max_Hop_Depth__c, DEFAULT_HOP_DEPTH);
        Integer effective = requested == null ? 1 : requested;
        return Math.min(Math.max(effective, 0), configuredMax);
    }

    private Integer boundedNodeCount() {
        return safeInt(new OI_SettingsService().getSettings().Max_Traversal_Node_Count__c, DEFAULT_MAX_NODE_COUNT);
    }

    private Integer safeInt(Decimal value, Integer fallback) {
        return value == null ? fallback : Integer.valueOf(value);
    }
}
