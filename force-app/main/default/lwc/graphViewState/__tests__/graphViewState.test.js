import {
    createGraphViewState,
    setCenter,
    setCenterFromFragment,
    applyExpand,
    applyCollapse,
    selectNode,
    isWorkingSetCeilingHit,
    snapshotNodes,
    snapshotEdges
} from 'c/graphViewState';

function nodeSummary(nodeKey) {
    return { nodeKey, typeKey: 'SalesforceMetadata.Test', label: nodeKey, secondaryKey: nodeKey, state: 'Active' };
}

function edgeSummary(edgeKey, sourceNodeKey, targetNodeKey) {
    return { edgeKey, typeKey: 'SalesforceMetadata.TestRel', sourceNodeKey, targetNodeKey };
}

describe('graphViewState', () => {
    it('setCenter replaces the entire view and anchors the center with a permanent synthetic ancestor', () => {
        const state = createGraphViewState();
        setCenter(state, nodeSummary('root'));
        expect(state.centerNodeKey).toBe('root');
        expect(state.selectedNodeKey).toBe('root');
        expect(snapshotNodes(state)).toHaveLength(1);
    });

    it('applyExpand reveals new neighbors and records them in the expanding node\'s own revealedSet', () => {
        const state = createGraphViewState();
        setCenter(state, nodeSummary('root'));
        applyExpand(state, 'root', {
            nodes: [nodeSummary('root'), nodeSummary('child1'), nodeSummary('child2')],
            edges: [edgeSummary('e1', 'root', 'child1'), edgeSummary('e2', 'root', 'child2')],
            hasMore: false,
            nextCursor: null
        });
        const nodes = snapshotNodes(state).map((n) => n.nodeKey);
        expect(nodes.sort()).toEqual(['child1', 'child2', 'root']);
        expect(snapshotEdges(state)).toHaveLength(2);
    });

    it('collapse removes a node only when its supporting-ancestor count reaches zero — the diamond-shared-descendant case (GraphUI.md §13, required test)', () => {
        const state = createGraphViewState();
        setCenter(state, nodeSummary('root'));
        // root -> A, root -> B (both expanded ancestors), both independently reveal D.
        applyExpand(state, 'root', {
            nodes: [nodeSummary('root'), nodeSummary('a'), nodeSummary('b')],
            edges: [edgeSummary('e1', 'root', 'a'), edgeSummary('e2', 'root', 'b')],
            hasMore: false,
            nextCursor: null
        });
        applyExpand(state, 'a', {
            nodes: [nodeSummary('a'), nodeSummary('d')],
            edges: [edgeSummary('e3', 'a', 'd')],
            hasMore: false,
            nextCursor: null
        });
        applyExpand(state, 'b', {
            nodes: [nodeSummary('b'), nodeSummary('d')],
            edges: [edgeSummary('e4', 'b', 'd')],
            hasMore: false,
            nextCursor: null
        });

        // D is now supported by both A and B. Collapsing A only decrements A's OWN
        // contribution (per §12/§13, collapse never removes the collapsed node itself,
        // only what it revealed) — D survives on B's remaining support, and A itself
        // remains visible (still supported by root, which has not been collapsed).
        applyCollapse(state, 'a');
        let nodeKeys = snapshotNodes(state).map((n) => n.nodeKey).sort();
        expect(nodeKeys).toEqual(['a', 'b', 'd', 'root']);
        expect(snapshotNodes(state).find((n) => n.nodeKey === 'a').isExpanded).toBe(false);
        // Both edges remain — every endpoint (a, b, d, root) is still visible.
        let edgeKeys = snapshotEdges(state).map((e) => e.edgeKey).sort();
        expect(edgeKeys).toEqual(['e1', 'e2', 'e3', 'e4']);

        // Now collapse B too — D's LAST supporting ancestor is gone, D must be removed.
        // A and B themselves remain (still supported by root).
        applyCollapse(state, 'b');
        nodeKeys = snapshotNodes(state).map((n) => n.nodeKey).sort();
        expect(nodeKeys).toEqual(['a', 'b', 'root']);
        edgeKeys = snapshotEdges(state).map((e) => e.edgeKey).sort();
        expect(edgeKeys).toEqual(['e1', 'e2'], 'Both e3 (a->d) and e4 (b->d) must be pruned once d itself is removed.');
    });

    it('the center node survives an unrelated collapse regardless of exploration depth', () => {
        const state = createGraphViewState();
        setCenter(state, nodeSummary('root'));
        applyExpand(state, 'root', {
            nodes: [nodeSummary('root'), nodeSummary('a')],
            edges: [edgeSummary('e1', 'root', 'a')],
            hasMore: false,
            nextCursor: null
        });
        applyCollapse(state, 'root');
        const nodeKeys = snapshotNodes(state).map((n) => n.nodeKey);
        expect(nodeKeys).toEqual(['root']);
    });

    it('selectNode updates selection without altering the visible set', () => {
        const state = createGraphViewState();
        setCenter(state, nodeSummary('root'));
        selectNode(state, 'root');
        expect(state.selectedNodeKey).toBe('root');
    });

    it('setCenterFromFragment pre-populates a multi-hop reveal in one call (Object Analyze mode)', () => {
        const state = createGraphViewState();
        setCenterFromFragment(state, {
            centerNodeKey: 'account',
            nodes: [nodeSummary('account'), nodeSummary('ownerIdField'), nodeSummary('user')],
            edges: [edgeSummary('e1', 'account', 'ownerIdField'), edgeSummary('e2', 'ownerIdField', 'user')],
            hasMore: false,
            nextCursor: null
        });

        expect(state.centerNodeKey).toBe('account');
        expect(state.selectedNodeKey).toBe('account');
        const nodeKeys = snapshotNodes(state).map((n) => n.nodeKey).sort();
        expect(nodeKeys).toEqual(['account', 'ownerIdField', 'user']);
        expect(snapshotEdges(state)).toHaveLength(2);
        expect(snapshotNodes(state).find((n) => n.nodeKey === 'account').isExpanded).toBe(true);
    });

    it('collapsing the center after setCenterFromFragment tears the entire curated reveal back down in one action', () => {
        const state = createGraphViewState();
        setCenterFromFragment(state, {
            centerNodeKey: 'account',
            nodes: [nodeSummary('account'), nodeSummary('ownerIdField'), nodeSummary('user')],
            edges: [edgeSummary('e1', 'account', 'ownerIdField'), edgeSummary('e2', 'ownerIdField', 'user')],
            hasMore: false,
            nextCursor: null
        });

        applyCollapse(state, 'account');

        expect(snapshotNodes(state).map((n) => n.nodeKey)).toEqual(['account']);
        expect(snapshotEdges(state)).toHaveLength(0);
    });

    it('setCenterFromFragment resolves a trivial single-node fragment the same as setCenter', () => {
        const state = createGraphViewState();
        setCenterFromFragment(state, { centerNodeKey: 'solo', nodes: [nodeSummary('solo')], edges: [], hasMore: false, nextCursor: null });
        expect(snapshotNodes(state)).toHaveLength(1);
        expect(snapshotNodes(state)[0].isExpanded).toBe(false);
    });

    it('isWorkingSetCeilingHit compares workingSetSize against the configured ceiling', () => {
        const state = createGraphViewState();
        setCenter(state, nodeSummary('root'));
        expect(isWorkingSetCeilingHit(state, 1)).toBe(true);
        expect(isWorkingSetCeilingHit(state, 5)).toBe(false);
        expect(isWorkingSetCeilingHit(state, null)).toBe(false);
    });
});
