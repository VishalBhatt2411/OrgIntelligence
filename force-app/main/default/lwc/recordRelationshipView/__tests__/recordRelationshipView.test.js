import { buildRecordRelationshipView } from 'c/recordRelationshipView';

const LOOKUP_TO = 'SalesforceRecord.LOOKUP_TO';
const CHILD_OF = 'SalesforceRecord.CHILD_OF';

function recordNode(objectApiName, recordId, label) {
    return { nodeKey: `Record::${objectApiName}::${recordId}`, typeKey: `SalesforceRecord.${objectApiName}`, label, secondaryKey: objectApiName, state: 'Active', iconName: 'standard:record', colorToken: 'neutral' };
}

function key(objectApiName, recordId) {
    return `Record::${objectApiName}::${recordId}`;
}

describe('recordRelationshipView', () => {
    describe('buildRecordRelationshipView', () => {
        it('returns null rootObject and empty lanes when the center node is not in the working set', () => {
            const view = buildRecordRelationshipView([], [], 'missing');
            expect(view.rootObject).toBeNull();
            expect(view.incomingRelationships).toEqual([]);
            expect(view.outgoingRelationships).toEqual([]);
            expect(view.selfRelationships).toEqual([]);
            expect(view.counts).toEqual({ incomingTotal: 0, outgoingTotal: 0, selfTotal: 0 });
        });

        it('classifies an outgoing relationship: a LOOKUP_TO edge FROM the center to a different-object record', () => {
            const nodes = [recordNode('Account', '001x1', 'Acme Corp'), recordNode('User', '005x1', 'Jane Admin')];
            const edges = [{ edgeKey: 'e1', typeKey: LOOKUP_TO, sourceNodeKey: key('Account', '001x1'), targetNodeKey: key('User', '005x1') }];
            const view = buildRecordRelationshipView(nodes, edges, key('Account', '001x1'));

            expect(view.outgoingRelationships).toHaveLength(1);
            expect(view.outgoingRelationships[0].counterpartObject.nodeKey).toBe(key('User', '005x1'));
            expect(view.outgoingRelationships[0].direction).toBe('outgoing');
            expect(view.incomingRelationships).toHaveLength(0);
        });

        it('classifies an incoming relationship: a LOOKUP_TO edge FROM another record TO the center', () => {
            const nodes = [recordNode('Account', '001x1', 'Acme Corp'), recordNode('Opportunity', '006x1', 'Acme Deal')];
            const edges = [{ edgeKey: 'e1', typeKey: LOOKUP_TO, sourceNodeKey: key('Opportunity', '006x1'), targetNodeKey: key('Account', '001x1') }];
            const view = buildRecordRelationshipView(nodes, edges, key('Account', '001x1'));

            expect(view.incomingRelationships).toHaveLength(1);
            expect(view.incomingRelationships[0].counterpartObject.nodeKey).toBe(key('Opportunity', '006x1'));
            expect(view.incomingRelationships[0].direction).toBe('incoming');
        });

        it('classifies a CHILD_OF edge (stored center->child) as incoming — the child references the center as its parent', () => {
            const nodes = [recordNode('Account', '001x1', 'Acme Corp'), recordNode('Contact', '003x1', 'Jane Doe')];
            const edges = [{ edgeKey: 'e1', typeKey: CHILD_OF, sourceNodeKey: key('Account', '001x1'), targetNodeKey: key('Contact', '003x1') }];
            const view = buildRecordRelationshipView(nodes, edges, key('Account', '001x1'));

            expect(view.incomingRelationships).toHaveLength(1);
            expect(view.incomingRelationships[0].counterpartObject.nodeKey).toBe(key('Contact', '003x1'));
            expect(view.outgoingRelationships).toHaveLength(0);
        });

        it('treats a counterpart record of the SAME object type as the center as a self relationship, never incoming/outgoing (record-mode analog of an object referencing itself)', () => {
            const nodes = [recordNode('Account', '001x1', 'Acme Corp'), recordNode('Account', '001x2', 'Acme Corp — West')];
            const edges = [{ edgeKey: 'e1', typeKey: LOOKUP_TO, sourceNodeKey: key('Account', '001x1'), targetNodeKey: key('Account', '001x2') }];
            const view = buildRecordRelationshipView(nodes, edges, key('Account', '001x1'));

            expect(view.selfRelationships).toHaveLength(1);
            expect(view.selfRelationships[0].direction).toBe('self');
            expect(view.selfRelationships[0].counterpartObject.nodeKey).toBe(key('Account', '001x2'));
            expect(view.incomingRelationships).toHaveLength(0);
            expect(view.outgoingRelationships).toHaveLength(0);
        });

        it('aggregates multiple edges to the same counterpart record into one connector, plainly stating the count', () => {
            const nodes = [recordNode('Account', '001x1', 'Acme Corp'), recordNode('Contact', '003x1', 'Jane Doe')];
            const edges = [
                { edgeKey: 'e1', typeKey: CHILD_OF, sourceNodeKey: key('Account', '001x1'), targetNodeKey: key('Contact', '003x1') },
                { edgeKey: 'e2', typeKey: CHILD_OF, sourceNodeKey: key('Account', '001x1'), targetNodeKey: key('Contact', '003x1') }
            ];
            const view = buildRecordRelationshipView(nodes, edges, key('Account', '001x1'));

            expect(view.incomingRelationships).toHaveLength(1);
            const connector = view.incomingRelationships[0];
            expect(connector.relationshipCount).toBe(2);
            expect(connector.relationshipTypeLabel).toBe('Related Records');
        });

        it('carries no per-field detail — a record connector always has an empty fields[] array, since OI_RecordHierarchyService fragments carry no originating field', () => {
            const nodes = [recordNode('Account', '001x1', 'Acme Corp'), recordNode('Contact', '003x1', 'Jane Doe')];
            const edges = [{ edgeKey: 'e1', typeKey: CHILD_OF, sourceNodeKey: key('Account', '001x1'), targetNodeKey: key('Contact', '003x1') }];
            const view = buildRecordRelationshipView(nodes, edges, key('Account', '001x1'));

            expect(view.incomingRelationships[0].fields).toEqual([]);
            expect(view.incomingRelationships[0].isSystemRelationship).toBe(false);
        });

        it('excludes a relationship between two non-center records that both happen to be in the working set — center-anchored only, exactly like objectRelationshipView', () => {
            const nodes = [recordNode('Account', '001x1', 'Acme Corp'), recordNode('Contact', '003x1', 'Jane Doe'), recordNode('Opportunity', '006x1', 'Other Deal')];
            const edges = [
                { edgeKey: 'e1', typeKey: CHILD_OF, sourceNodeKey: key('Account', '001x1'), targetNodeKey: key('Contact', '003x1') },
                { edgeKey: 'e2', typeKey: LOOKUP_TO, sourceNodeKey: key('Opportunity', '006x1'), targetNodeKey: key('Contact', '003x1') }
            ];
            const view = buildRecordRelationshipView(nodes, edges, key('Account', '001x1'));

            expect(view.incomingRelationships).toHaveLength(1);
            expect(view.incomingRelationships[0].counterpartObject.nodeKey).toBe(key('Contact', '003x1'));
        });

        it('resolves objectApiName/recordId on the root and counterpart refs via c/recordNodeKey, for connector-detail navigation', () => {
            const nodes = [recordNode('Account', '001x1', 'Acme Corp'), recordNode('Contact', '003x1', 'Jane Doe')];
            const edges = [{ edgeKey: 'e1', typeKey: CHILD_OF, sourceNodeKey: key('Account', '001x1'), targetNodeKey: key('Contact', '003x1') }];
            const view = buildRecordRelationshipView(nodes, edges, key('Account', '001x1'));

            expect(view.rootObject.objectApiName).toBe('Account');
            expect(view.rootObject.recordId).toBe('001x1');
            expect(view.incomingRelationships[0].counterpartObject.objectApiName).toBe('Contact');
            expect(view.incomingRelationships[0].counterpartObject.recordId).toBe('003x1');
        });
    });
});
