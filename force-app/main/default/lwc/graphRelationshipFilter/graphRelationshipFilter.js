/**
 * Purpose: Client-side relationship-view filtering (GraphUI.md §22's "client-side visual
 *          filter" layer, Backlog UI-4) — a plain, framework-free JS module, exactly like
 *          graphViewState.js/presentationRegistry.js. Answers "of the already-fetched
 *          nodes/edges, which ones does the user's current relationship-view selection
 *          actually reveal," never a server call and never a mutation of the real
 *          GraphViewState.
 * Responsibilities: A directed breadth-first search from the current center node, restricted
 *                    to caller-selected edge typeKeys and traversal direction, bounded by an
 *                    optional max hop depth — the general mechanism "Object Relationships,"
 *                    "Parent Objects," "Parent + Grandparent Objects," "Child Objects," and
 *                    "Fields" (an ordinary edge-type checkbox, since HAS_FIELD is just another
 *                    typeKey here) all reduce to, given the right filter combination. A flat,
 *                    non-directional edge-type filter (the plain "which typeKeys are checked"
 *                    case) is directional BFS with direction 'both' and unlimited depth —
 *                    the same algorithm, not a special case.
 * Dependencies: None.
 * Limitations: Operates only over the already-loaded working set (GraphUI.md §17's
 *              layout-decision-not-correctness-decision framing, applied to filtering
 *              instead of ring assignment) — going further than what's loaded is still the
 *              existing expand action's job, unaffected by this module. Edges whose target
 *              node isn't currently loaded (a dangling reference into data the client
 *              doesn't hold) are silently excluded rather than erroring, consistent with how
 *              oiGraphCanvas.js's own renderableEdges already treats an unresolvable
 *              endpoint.
 */

/** direction: 'both' | 'outgoing' | 'incoming' — relative to whichever node is nearer the center at that specific hop, not always the center itself (a grandparent's own direction is evaluated from its parent, not from the original center). */
export function createRelationshipFilter() {
    return {
        edgeTypeKeys: null, // null = every currently-known edge type is allowed (the "All Relationships" default)
        direction: 'both',
        maxDepth: null // null = unbounded (limited only by what's actually loaded)
    };
}

/**
 * Returns the subset of nodes/edges reachable from centerNodeKey under the given filter.
 * Always includes the center node itself, even if every edge type is excluded, so the
 * canvas never renders a fully-empty view just because a filter hid everything around it.
 */
export function applyRelationshipFilter(nodes, edges, centerNodeKey, filter) {
    const allNodes = nodes || [];
    const allEdges = edges || [];
    const nodeByKey = new Map(allNodes.map((node) => [node.nodeKey, node]));
    if (!centerNodeKey || !nodeByKey.has(centerNodeKey)) {
        return { nodes: allNodes, edges: allEdges };
    }

    const effectiveFilter = { ...createRelationshipFilter(), ...(filter || {}) };
    const { outgoingFrom, incomingTo } = buildDirectedAdjacency(allEdges, effectiveFilter.edgeTypeKeys);

    const reachableNodeKeys = new Set([centerNodeKey]);
    const reachableEdgeKeys = new Set();
    let frontier = [centerNodeKey];
    let depth = 0;
    while (frontier.length > 0 && (effectiveFilter.maxDepth == null || depth < effectiveFilter.maxDepth)) {
        depth += 1;
        const next = [];
        for (const key of frontier) {
            const candidates = neighborsOf(key, effectiveFilter.direction, outgoingFrom, incomingTo);
            for (const { edge, neighborKey } of candidates) {
                if (!nodeByKey.has(neighborKey)) {
                    continue;
                }
                reachableEdgeKeys.add(edge.edgeKey);
                if (!reachableNodeKeys.has(neighborKey)) {
                    reachableNodeKeys.add(neighborKey);
                    next.push(neighborKey);
                }
            }
        }
        frontier = next;
    }

    return {
        nodes: allNodes.filter((node) => reachableNodeKeys.has(node.nodeKey)),
        edges: allEdges.filter((edge) => reachableEdgeKeys.has(edge.edgeKey) && reachableNodeKeys.has(edge.sourceNodeKey) && reachableNodeKeys.has(edge.targetNodeKey))
    };
}

function buildDirectedAdjacency(edges, edgeTypeKeys) {
    const outgoingFrom = new Map();
    const incomingTo = new Map();
    for (const edge of edges) {
        if (edgeTypeKeys && !edgeTypeKeys.has(edge.typeKey)) {
            continue;
        }
        pushInto(outgoingFrom, edge.sourceNodeKey, { edge, neighborKey: edge.targetNodeKey });
        pushInto(incomingTo, edge.targetNodeKey, { edge, neighborKey: edge.sourceNodeKey });
    }
    return { outgoingFrom, incomingTo };
}

function pushInto(map, key, value) {
    if (!map.has(key)) {
        map.set(key, []);
    }
    map.get(key).push(value);
}

function neighborsOf(nodeKey, direction, outgoingFrom, incomingTo) {
    const forward = direction === 'incoming' ? [] : outgoingFrom.get(nodeKey) || [];
    const backward = direction === 'outgoing' ? [] : incomingTo.get(nodeKey) || [];
    return forward.concat(backward);
}
