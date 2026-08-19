import { createRelationshipFilter, applyRelationshipFilter } from 'c/graphRelationshipFilter';

function node(nodeKey) {
    return { nodeKey, typeKey: 'T', label: nodeKey, secondaryKey: nodeKey, state: 'Active' };
}

function edge(edgeKey, typeKey, sourceNodeKey, targetNodeKey) {
    return { edgeKey, typeKey, sourceNodeKey, targetNodeKey };
}

const LOOKUP = 'SalesforceMetadata.LOOKUP_TO';
const MASTER_DETAIL = 'SalesforceMetadata.MASTER_DETAIL_TO';
const HAS_FIELD = 'SalesforceMetadata.HAS_FIELD';

describe('graphRelationshipFilter', () => {
    it('createRelationshipFilter defaults to unrestricted: every type, both directions, unbounded depth', () => {
        const filter = createRelationshipFilter();
        expect(filter.edgeTypeKeys).toBeNull();
        expect(filter.direction).toBe('both');
        expect(filter.maxDepth).toBeNull();
    });

    it('with the default filter, every already-loaded node/edge passes through unchanged', () => {
        const nodes = [node('a'), node('b'), node('c')];
        const edges = [edge('e1', LOOKUP, 'a', 'b'), edge('e2', HAS_FIELD, 'a', 'c')];
        const result = applyRelationshipFilter(nodes, edges, 'a', createRelationshipFilter());
        expect(result.nodes.map((n) => n.nodeKey).sort()).toEqual(['a', 'b', 'c']);
        expect(result.edges).toHaveLength(2);
    });

    it('restricting edgeTypeKeys to Lookup only excludes nodes reachable solely via a different type (Object Relationships / Fields toggle)', () => {
        const nodes = [node('account'), node('contact'), node('nameField')];
        const edges = [edge('e1', LOOKUP, 'contact', 'account'), edge('e2', HAS_FIELD, 'account', 'nameField')];
        const result = applyRelationshipFilter(nodes, edges, 'account', { ...createRelationshipFilter(), edgeTypeKeys: new Set([LOOKUP]) });
        const keys = result.nodes.map((n) => n.nodeKey).sort();
        expect(keys).toEqual(['account', 'contact']);
        expect(result.edges.map((e) => e.edgeKey)).toEqual(['e1']);
    });

    it('direction "outgoing" keeps only the parent chain — a node reachable exclusively via an incoming edge is excluded ("Parent Objects")', () => {
        const nodes = [node('contact'), node('account'), node('opportunity')];
        // contact -> account (contact's parent is account); opportunity -> contact (contact is opportunity's parent, i.e. an INCOMING edge relative to contact).
        const edges = [edge('e1', LOOKUP, 'contact', 'account'), edge('e2', LOOKUP, 'opportunity', 'contact')];
        const result = applyRelationshipFilter(nodes, edges, 'contact', { ...createRelationshipFilter(), direction: 'outgoing' });
        const keys = result.nodes.map((n) => n.nodeKey).sort();
        expect(keys).toEqual(['account', 'contact']);
    });

    it('direction "incoming" keeps only the child chain — the mirror image of "outgoing" ("Child Objects")', () => {
        const nodes = [node('contact'), node('account'), node('opportunity')];
        const edges = [edge('e1', LOOKUP, 'contact', 'account'), edge('e2', LOOKUP, 'opportunity', 'contact')];
        const result = applyRelationshipFilter(nodes, edges, 'contact', { ...createRelationshipFilter(), direction: 'incoming' });
        const keys = result.nodes.map((n) => n.nodeKey).sort();
        expect(keys).toEqual(['contact', 'opportunity']);
    });

    it('direction is evaluated relative to whichever node is nearer the center at that hop, not always the original center (a real "Parent of Parent" chain)', () => {
        // contact -> account -> parentAccount, all via outgoing Lookup edges from the perspective of the node one hop closer to center each time.
        const nodes = [node('contact'), node('account'), node('parentAccount')];
        const edges = [edge('e1', LOOKUP, 'contact', 'account'), edge('e2', LOOKUP, 'account', 'parentAccount')];
        const result = applyRelationshipFilter(nodes, edges, 'contact', { ...createRelationshipFilter(), direction: 'outgoing' });
        expect(result.nodes.map((n) => n.nodeKey).sort()).toEqual(['account', 'contact', 'parentAccount']);
    });

    it('maxDepth caps how far the parent chain extends ("Parent Objects" vs "Parent + Grandparent Objects")', () => {
        const nodes = [node('contact'), node('account'), node('parentAccount')];
        const edges = [edge('e1', LOOKUP, 'contact', 'account'), edge('e2', LOOKUP, 'account', 'parentAccount')];
        const depthOne = applyRelationshipFilter(nodes, edges, 'contact', { ...createRelationshipFilter(), direction: 'outgoing', maxDepth: 1 });
        expect(depthOne.nodes.map((n) => n.nodeKey).sort()).toEqual(['account', 'contact']);

        const depthTwo = applyRelationshipFilter(nodes, edges, 'contact', { ...createRelationshipFilter(), direction: 'outgoing', maxDepth: 2 });
        expect(depthTwo.nodes.map((n) => n.nodeKey).sort()).toEqual(['account', 'contact', 'parentAccount']);
    });

    it('a node reachable via two independently-expanded ancestors (a diamond) still appears exactly once, with both connecting edges kept', () => {
        const nodes = [node('center'), node('left'), node('right'), node('shared')];
        const edges = [
            edge('e1', LOOKUP, 'center', 'left'),
            edge('e2', LOOKUP, 'center', 'right'),
            edge('e3', LOOKUP, 'left', 'shared'),
            edge('e4', LOOKUP, 'right', 'shared')
        ];
        const result = applyRelationshipFilter(nodes, edges, 'center', { ...createRelationshipFilter(), direction: 'outgoing' });
        expect(result.nodes.map((n) => n.nodeKey).sort()).toEqual(['center', 'left', 'right', 'shared']);
        expect(result.edges.map((e) => e.edgeKey).sort()).toEqual(['e1', 'e2', 'e3', 'e4']);
    });

    it('an edge pointing at a node the client has not loaded is silently excluded, never thrown', () => {
        const nodes = [node('account')];
        const edges = [edge('e1', LOOKUP, 'account', 'notLoadedNode')];
        const result = applyRelationshipFilter(nodes, edges, 'account', createRelationshipFilter());
        expect(result.nodes.map((n) => n.nodeKey)).toEqual(['account']);
        expect(result.edges).toHaveLength(0);
    });

    it('the center node is always present even when every edge type is excluded, so the canvas never renders a fully-empty view', () => {
        const nodes = [node('account'), node('contact')];
        const edges = [edge('e1', LOOKUP, 'contact', 'account')];
        const result = applyRelationshipFilter(nodes, edges, 'account', { ...createRelationshipFilter(), edgeTypeKeys: new Set([MASTER_DETAIL]) });
        expect(result.nodes.map((n) => n.nodeKey)).toEqual(['account']);
        expect(result.edges).toHaveLength(0);
    });

    it('an unknown centerNodeKey (not among the loaded nodes) passes everything through unchanged rather than filtering to nothing', () => {
        const nodes = [node('a'), node('b')];
        const edges = [edge('e1', LOOKUP, 'a', 'b')];
        const result = applyRelationshipFilter(nodes, edges, 'notLoaded', { ...createRelationshipFilter(), edgeTypeKeys: new Set([MASTER_DETAIL]) });
        expect(result.nodes).toEqual(nodes);
        expect(result.edges).toEqual(edges);
    });
});
