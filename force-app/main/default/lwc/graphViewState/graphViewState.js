/**
 * Purpose: The client-side reference-counting graph visibility model (GraphUI.md §10-13) —
 *          a plain, framework-free JS module, not a heavyweight state library (ADR-0008
 *          stands). Note: GraphUI.md's file tree shows this nested under `oiSharedUtils/`;
 *          LWC modules cannot be nested under a shared namespace folder, so this ships as
 *          its own top-level module (`c/graphViewState`) — an organizational adaptation,
 *          not an architectural one.
 * Responsibilities: Own the visible node/edge set, expand/collapse via reference counting
 *                    (the diamond-shared-descendant case, §13), selection, and the
 *                    working-set-ceiling check (§26). Never calls Apex — the container
 *                    (oiGraphExplorer) owns fetching and passes fragments in.
 */

const ROOT_ANCESTOR = '__root__';

export function createGraphViewState() {
    return {
        centerNodeKey: null,
        visibleNodes: new Map(),
        visibleEdges: new Map(),
        selectedNodeKey: null,
        workingSetSize: 0
    };
}

/** Replaces the entire view with a new center — a fresh view, never a partial edit (GraphUI.md §11). */
export function setCenter(state, nodeSummary) {
    state.centerNodeKey = nodeSummary.nodeKey;
    state.visibleNodes = new Map();
    state.visibleEdges = new Map();
    state.selectedNodeKey = nodeSummary.nodeKey;
    state.visibleNodes.set(nodeSummary.nodeKey, newEntry(nodeSummary, new Set([ROOT_ANCESTOR])));
    state.workingSetSize = state.visibleNodes.size;
}

/**
 * Replaces the entire view with a new center, pre-populated from a multi-hop fragment
 * (e.g. hopDepth 2 for an Object-centered Analyze view, or hopDepth 1 for a Field-centered
 * one — see oiGraphExplorer's hierarchyHopDepth) rather than the single-node,
 * zero-hop fragment setCenter expects. Every non-center node is attributed to the center's
 * own supportingAncestors/revealedSet — regardless of its real hop distance — so a single
 * collapse of the center tears the whole curated reveal back down in one action, exactly
 * like a normal single-hop expand/collapse would for a shallower reveal.
 */
export function setCenterFromFragment(state, fragment) {
    const nodes = fragment.nodes || [];
    const centerSummary = nodes.find((n) => n.nodeKey === fragment.centerNodeKey) || nodes[0];
    if (!centerSummary) {
        return;
    }
    state.centerNodeKey = centerSummary.nodeKey;
    state.visibleNodes = new Map();
    state.visibleEdges = new Map();
    state.selectedNodeKey = centerSummary.nodeKey;

    const centerEntry = newEntry(centerSummary, new Set([ROOT_ANCESTOR]));
    state.visibleNodes.set(centerSummary.nodeKey, centerEntry);

    for (const nodeSummary of nodes) {
        if (nodeSummary.nodeKey === centerSummary.nodeKey) {
            continue;
        }
        state.visibleNodes.set(nodeSummary.nodeKey, newEntry(nodeSummary, new Set([centerSummary.nodeKey])));
        centerEntry.revealedSet.add(nodeSummary.nodeKey);
    }
    for (const edgeSummary of fragment.edges || []) {
        state.visibleEdges.set(edgeSummary.edgeKey, edgeSummary);
    }
    centerEntry.isExpanded = nodes.length > 1;
    centerEntry.pageCursor = fragment.nextCursor || null;
    centerEntry.hasMoreNeighbors = !!fragment.hasMore;
    state.workingSetSize = state.visibleNodes.size;
}

function newEntry(summary, supportingAncestors) {
    return {
        summary,
        supportingAncestors: supportingAncestors || new Set(),
        revealedSet: new Set(),
        isExpanded: false,
        pageCursor: null,
        hasMoreNeighbors: false
    };
}

/**
 * Expand(nodeKey) per GraphUI.md §12: for every node the fragment returns, add nodeKey to
 * its supportingAncestors (creating the entry fresh at count 1 if it's new); record every
 * returned key (new or already-visible) into nodeKey's OWN revealedSet — this is §13's
 * central correctness requirement, tracked separately from supportingAncestors so a later
 * collapse of nodeKey decrements exactly what nodeKey's own expand contributed, never a
 * neighbor some other still-expanded ancestor is independently supporting.
 */
export function applyExpand(state, nodeKey, fragment) {
    const entry = state.visibleNodes.get(nodeKey);
    if (!entry) {
        return;
    }
    for (const nodeSummary of fragment.nodes || []) {
        if (nodeSummary.nodeKey === nodeKey) {
            continue;
        }
        let neighbor = state.visibleNodes.get(nodeSummary.nodeKey);
        if (!neighbor) {
            neighbor = newEntry(nodeSummary, new Set());
            state.visibleNodes.set(nodeSummary.nodeKey, neighbor);
        } else {
            neighbor.summary = nodeSummary;
        }
        neighbor.supportingAncestors.add(nodeKey);
        entry.revealedSet.add(nodeSummary.nodeKey);
    }
    for (const edgeSummary of fragment.edges || []) {
        state.visibleEdges.set(edgeSummary.edgeKey, edgeSummary);
    }
    entry.isExpanded = true;
    entry.pageCursor = fragment.nextCursor || null;
    entry.hasMoreNeighbors = !!fragment.hasMore;
    state.workingSetSize = state.visibleNodes.size;
}

/**
 * Collapse(nodeKey) per GraphUI.md §12/§13: decrement support only for nodes in
 * revealedSet(nodeKey) — not "every node nodeKey has a visible edge to" — removing a node
 * only when its supporting-ancestor count reaches zero. revealedSet itself is NOT cleared
 * (a future re-expand still benefits from anything the client kept).
 */
export function applyCollapse(state, nodeKey) {
    const entry = state.visibleNodes.get(nodeKey);
    if (!entry) {
        return;
    }
    for (const revealedKey of entry.revealedSet) {
        const target = state.visibleNodes.get(revealedKey);
        if (!target) {
            continue;
        }
        target.supportingAncestors.delete(nodeKey);
        if (target.supportingAncestors.size === 0) {
            state.visibleNodes.delete(revealedKey);
        }
    }
    entry.isExpanded = false;
    pruneDanglingEdges(state);
    state.workingSetSize = state.visibleNodes.size;
}

/** An edge is visible iff both endpoints are currently visible nodes — no independent edge reference count (GraphUI.md §6). */
function pruneDanglingEdges(state) {
    for (const [edgeKey, edge] of state.visibleEdges) {
        if (!state.visibleNodes.has(edge.sourceNodeKey) || !state.visibleNodes.has(edge.targetNodeKey)) {
            state.visibleEdges.delete(edgeKey);
        }
    }
}

export function selectNode(state, nodeKey) {
    state.selectedNodeKey = nodeKey;
}

export function isWorkingSetCeilingHit(state, ceiling) {
    return typeof ceiling === 'number' && state.workingSetSize >= ceiling;
}

/** Plain-array snapshot for template binding — Maps/Sets are not tracked reactively by LWC. */
export function snapshotNodes(state) {
    const nodes = [];
    for (const [nodeKey, entry] of state.visibleNodes) {
        nodes.push({
            nodeKey,
            typeKey: entry.summary.typeKey,
            label: entry.summary.label,
            secondaryKey: entry.summary.secondaryKey,
            state: entry.summary.state,
            isSelected: state.selectedNodeKey === nodeKey,
            isExpanded: entry.isExpanded,
            hasMoreNeighbors: entry.hasMoreNeighbors,
            pageCursor: entry.pageCursor
        });
    }
    return nodes;
}

export function snapshotEdges(state) {
    return Array.from(state.visibleEdges.values());
}
