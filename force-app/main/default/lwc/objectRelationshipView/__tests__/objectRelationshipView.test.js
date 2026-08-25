import { buildObjectRelationshipView, isSystemField, isCustomApiName, OBJECT_TYPE_KEY, SYSTEM_FIELD_API_NAMES, DEFAULT_VISIBLE_PER_LANE } from 'c/objectRelationshipView';

const HAS_FIELD = 'SalesforceMetadata.HAS_FIELD';
const LOOKUP_TO = 'SalesforceMetadata.LOOKUP_TO';
const MASTER_DETAIL_TO = 'SalesforceMetadata.MASTER_DETAIL_TO';
const APEX_CLASS_TYPE_KEY = 'SalesforceMetadata.ApexClass';
const EXECUTES_ON = 'SalesforceMetadata.EXECUTES_ON';

function objectNode(nodeKey, label, secondaryKey) {
    return { nodeKey, typeKey: OBJECT_TYPE_KEY, label, secondaryKey, iconName: 'standard:account', colorToken: 'blue' };
}

function fieldNode(nodeKey, label) {
    return { nodeKey, typeKey: 'SalesforceMetadata.CustomField', label, secondaryKey: label };
}

function hasFieldEdge(ownerKey, fieldKey) {
    return { edgeKey: ownerKey + '-hf-' + fieldKey, typeKey: HAS_FIELD, sourceNodeKey: ownerKey, targetNodeKey: fieldKey };
}

function lookupEdge(fieldKey, referencedObjectKey, viaFieldApiName, typeKey = LOOKUP_TO) {
    return { edgeKey: fieldKey + '-lu-' + referencedObjectKey, typeKey, sourceNodeKey: fieldKey, targetNodeKey: referencedObjectKey, viaFieldApiName };
}

describe('objectRelationshipView', () => {
    describe('buildObjectRelationshipView', () => {
        it('returns null rootObject and empty lanes when the center node is not in the working set', () => {
            const view = buildObjectRelationshipView([], [], 'missing');
            expect(view.rootObject).toBeNull();
            expect(view.incomingRelationships).toEqual([]);
            expect(view.outgoingRelationships).toEqual([]);
            expect(view.selfRelationships).toEqual([]);
            expect(view.counts).toEqual({ incomingTotal: 0, outgoingTotal: 0, selfTotal: 0 });
        });

        it('classifies an outgoing relationship: center object owns the lookup field', () => {
            const nodes = [objectNode('account', 'Account', 'Account'), objectNode('user', 'User', 'User'), fieldNode('ownerId', 'OwnerId')];
            const edges = [hasFieldEdge('account', 'ownerId'), lookupEdge('ownerId', 'user', 'OwnerId')];
            const view = buildObjectRelationshipView(nodes, edges, 'account');
            expect(view.outgoingRelationships).toHaveLength(1);
            expect(view.outgoingRelationships[0].counterpartObject.nodeKey).toBe('user');
            expect(view.outgoingRelationships[0].direction).toBe('outgoing');
            expect(view.incomingRelationships).toHaveLength(0);
        });

        it('classifies an incoming relationship: another object owns a lookup field pointing at the center', () => {
            const nodes = [objectNode('account', 'Account', 'Account'), objectNode('opportunity', 'Opportunity', 'Opportunity'), fieldNode('accountId', 'AccountId')];
            const edges = [hasFieldEdge('opportunity', 'accountId'), lookupEdge('accountId', 'account', 'AccountId', MASTER_DETAIL_TO)];
            const view = buildObjectRelationshipView(nodes, edges, 'account');
            expect(view.incomingRelationships).toHaveLength(1);
            expect(view.incomingRelationships[0].counterpartObject.nodeKey).toBe('opportunity');
            expect(view.incomingRelationships[0].direction).toBe('incoming');
            expect(view.incomingRelationships[0].primaryRelationshipType).toBe('MasterDetail');
        });

        it('classifies a self relationship into selfRelationships, never incoming/outgoing', () => {
            const nodes = [objectNode('account', 'Account', 'Account'), fieldNode('parentId', 'ParentId')];
            const edges = [hasFieldEdge('account', 'parentId'), lookupEdge('parentId', 'account', 'ParentId')];
            const view = buildObjectRelationshipView(nodes, edges, 'account');
            expect(view.selfRelationships).toHaveLength(1);
            expect(view.selfRelationships[0].direction).toBe('self');
            expect(view.selfRelationships[0].counterpartObject.nodeKey).toBe('account');
            expect(view.incomingRelationships).toHaveLength(0);
            expect(view.outgoingRelationships).toHaveLength(0);
        });

        it('aggregates multiple relationship fields between the same object pair into one connector', () => {
            const nodes = [objectNode('account', 'Account', 'Account'), objectNode('user', 'User', 'User'), fieldNode('ownerId', 'OwnerId'), fieldNode('createdById', 'CreatedById'), fieldNode('lastModifiedById', 'LastModifiedById')];
            const edges = [
                hasFieldEdge('account', 'ownerId'),
                lookupEdge('ownerId', 'user', 'OwnerId'),
                hasFieldEdge('account', 'createdById'),
                lookupEdge('createdById', 'user', 'CreatedById'),
                hasFieldEdge('account', 'lastModifiedById'),
                lookupEdge('lastModifiedById', 'user', 'LastModifiedById')
            ];
            const view = buildObjectRelationshipView(nodes, edges, 'account');
            expect(view.outgoingRelationships).toHaveLength(1);
            const connector = view.outgoingRelationships[0];
            expect(connector.relationshipCount).toBe(3);
            expect(connector.fields.map((f) => f.fieldApiName).sort()).toEqual(['CreatedById', 'LastModifiedById', 'OwnerId']);
        });

        it('a polymorphic field produces one connector per referenced object, not a duplicate-detection bug', () => {
            const nodes = [objectNode('task', 'Task', 'Task'), objectNode('account', 'Account', 'Account'), objectNode('opportunity', 'Opportunity', 'Opportunity'), fieldNode('whatId', 'WhatId')];
            const edges = [hasFieldEdge('task', 'whatId'), lookupEdge('whatId', 'account', 'WhatId'), lookupEdge('whatId', 'opportunity', 'WhatId')];
            const view = buildObjectRelationshipView(nodes, edges, 'task');
            expect(view.outgoingRelationships).toHaveLength(2);
            const counterparts = view.outgoingRelationships.map((c) => c.counterpartObject.nodeKey).sort();
            expect(counterparts).toEqual(['account', 'opportunity']);
        });

        it('excludes a relationship between two non-center objects even when both are in the working set', () => {
            const nodes = [objectNode('account', 'Account', 'Account'), objectNode('contact', 'Contact', 'Contact'), objectNode('opportunity', 'Opportunity', 'Opportunity'), fieldNode('contactId', 'ContactId')];
            // Opportunity -> Contact, unrelated to the centered Account.
            const edges = [hasFieldEdge('opportunity', 'contactId'), lookupEdge('contactId', 'contact', 'ContactId')];
            const view = buildObjectRelationshipView(nodes, edges, 'account');
            expect(view.incomingRelationships).toHaveLength(0);
            expect(view.outgoingRelationships).toHaveLength(0);
        });

        it('excludes non-Object node types entirely from every lane (ApexClass leakage fix)', () => {
            const nodes = [objectNode('account', 'Account', 'Account'), { nodeKey: 'apexTrigger1', typeKey: 'SalesforceMetadata.ApexTrigger', label: 'AccountTrigger', secondaryKey: 'AccountTrigger' }, { nodeKey: 'apexClass1', typeKey: APEX_CLASS_TYPE_KEY, label: 'AccountHelper', secondaryKey: 'AccountHelper' }];
            const edges = [{ edgeKey: 'e1', typeKey: EXECUTES_ON, sourceNodeKey: 'apexTrigger1', targetNodeKey: 'account' }, { edgeKey: 'e2', typeKey: 'SalesforceMetadata.REFERENCES', sourceNodeKey: 'apexTrigger1', targetNodeKey: 'apexClass1' }];
            const view = buildObjectRelationshipView(nodes, edges, 'account');
            expect(view.incomingRelationships).toHaveLength(0);
            expect(view.outgoingRelationships).toHaveLength(0);
            expect(view.rootObject.nodeKey).toBe('account');
        });

        it('silently excludes a dangling reference edge whose field or endpoint object is missing from the working set', () => {
            const nodes = [objectNode('account', 'Account', 'Account'), fieldNode('ownerId', 'OwnerId')];
            // No HAS_FIELD edge at all — ownership can't be resolved, so this must be excluded, not throw.
            const edges = [lookupEdge('ownerId', 'user', 'OwnerId')];
            expect(() => buildObjectRelationshipView(nodes, edges, 'account')).not.toThrow();
            const view = buildObjectRelationshipView(nodes, edges, 'account');
            expect(view.outgoingRelationships).toHaveLength(0);
        });

        it('is deterministic: identical input produces identical, stably-sorted output across repeated calls', () => {
            const nodes = [objectNode('account', 'Account', 'Account'), objectNode('user', 'User', 'User'), objectNode('territory', 'Territory', 'Territory'), fieldNode('ownerId', 'OwnerId'), fieldNode('territoryId', 'TerritoryId')];
            const edges = [hasFieldEdge('account', 'ownerId'), lookupEdge('ownerId', 'user', 'OwnerId'), hasFieldEdge('account', 'territoryId'), lookupEdge('territoryId', 'territory', 'TerritoryId')];
            const first = buildObjectRelationshipView(nodes, edges, 'account');
            const second = buildObjectRelationshipView(nodes, edges, 'account');
            expect(first.outgoingRelationships.map((c) => c.counterpartObject.nodeKey)).toEqual(second.outgoingRelationships.map((c) => c.counterpartObject.nodeKey));
        });

        it('sorts each lane by relationship count descending, then counterpart label ascending', () => {
            const nodes = [
                objectNode('account', 'Account', 'Account'),
                objectNode('user', 'User', 'User'),
                objectNode('territory', 'Territory', 'Territory'),
                fieldNode('ownerId', 'OwnerId'),
                fieldNode('createdById', 'CreatedById'),
                fieldNode('territoryId', 'TerritoryId')
            ];
            const edges = [
                hasFieldEdge('account', 'ownerId'),
                lookupEdge('ownerId', 'user', 'OwnerId'),
                hasFieldEdge('account', 'createdById'),
                lookupEdge('createdById', 'user', 'CreatedById'),
                hasFieldEdge('account', 'territoryId'),
                lookupEdge('territoryId', 'territory', 'TerritoryId')
            ];
            const view = buildObjectRelationshipView(nodes, edges, 'account');
            // User has 2 relationship fields, Territory has 1 -> User first.
            expect(view.outgoingRelationships.map((c) => c.counterpartObject.nodeKey)).toEqual(['user', 'territory']);
        });
    });

    describe('system vs. business classification', () => {
        it('classifies OwnerId/CreatedById/LastModifiedById as system fields, exact match only', () => {
            expect(isSystemField('OwnerId')).toBe(true);
            expect(isSystemField('CreatedById')).toBe(true);
            expect(isSystemField('LastModifiedById')).toBe(true);
            expect(isSystemField('AccountId')).toBe(false);
            expect(isSystemField('MyCustomOwnerId__c')).toBe(false);
            expect(isSystemField(null)).toBe(false);
        });

        it('exposes the exact system field set for callers that need it', () => {
            expect([...SYSTEM_FIELD_API_NAMES].sort()).toEqual(['CreatedById', 'LastModifiedById', 'OwnerId']);
        });

        it('marks a connector system-classified only when every field in the group is a system field', () => {
            const nodes = [objectNode('account', 'Account', 'Account'), objectNode('user', 'User', 'User'), fieldNode('ownerId', 'OwnerId'), fieldNode('customUserLookup', 'CustomUserLookup__c')];
            const edges = [hasFieldEdge('account', 'ownerId'), lookupEdge('ownerId', 'user', 'OwnerId'), hasFieldEdge('account', 'customUserLookup'), lookupEdge('customUserLookup', 'user', 'CustomUserLookup__c')];
            const view = buildObjectRelationshipView(nodes, edges, 'account');
            expect(view.outgoingRelationships).toHaveLength(1);
            // One system field (OwnerId) + one business field sharing the same pair -> must default to visible (not system-only).
            expect(view.outgoingRelationships[0].isSystemRelationship).toBe(false);
        });

        /**
         * Regression for a real bug found validating against a live org: edge.viaFieldApiName is
         * actually populated from the edge's stored relationshipName (OI_GraphTraversal.cls's
         * extractViaFieldApiName), which for OwnerId/CreatedById/LastModifiedById is "Owner"/
         * "CreatedBy"/"LastModifiedBy" — NOT the field's real API name. Classification must be
         * derived from the field node's own secondaryKey, never from viaFieldApiName, or a
         * genuinely system field silently classifies as Business (the exact failure this
         * fixture reproduces if the source were wrong).
         */
        it('classifies by the field node\'s own API name (secondaryKey), never by the edge\'s viaFieldApiName — which is actually a relationship name, not a field API name', () => {
            const nodes = [
                objectNode('account', 'Account', 'Account'),
                objectNode('user', 'User', 'User'),
                { nodeKey: 'ownerIdField', typeKey: 'SalesforceMetadata.CustomField', label: 'Owner ID', secondaryKey: 'Account.OwnerId' }
            ];
            // viaFieldApiName deliberately set to the RELATIONSHIP name ("Owner"), exactly as OI_GraphTraversal.cls really populates it — not "OwnerId".
            const edges = [hasFieldEdge('account', 'ownerIdField'), lookupEdge('ownerIdField', 'user', 'Owner')];
            const view = buildObjectRelationshipView(nodes, edges, 'account');
            expect(view.outgoingRelationships).toHaveLength(1);
            expect(view.outgoingRelationships[0].isSystemRelationship).toBe(true);
            expect(view.outgoingRelationships[0].fields[0].fieldApiName).toBe('OwnerId');
        });

        it('marks a connector system-classified when every field in the group is a system field', () => {
            const nodes = [objectNode('account', 'Account', 'Account'), objectNode('user', 'User', 'User'), fieldNode('ownerId', 'OwnerId'), fieldNode('createdById', 'CreatedById')];
            const edges = [hasFieldEdge('account', 'ownerId'), lookupEdge('ownerId', 'user', 'OwnerId'), hasFieldEdge('account', 'createdById'), lookupEdge('createdById', 'user', 'CreatedById')];
            const view = buildObjectRelationshipView(nodes, edges, 'account');
            expect(view.outgoingRelationships[0].isSystemRelationship).toBe(true);
        });
    });

    describe('primaryRelationshipType', () => {
        it('resolves to MasterDetail if any field in the aggregated group is a master-detail relationship', () => {
            const nodes = [objectNode('opportunity', 'Opportunity', 'Opportunity'), objectNode('account', 'Account', 'Account'), fieldNode('accountId', 'AccountId')];
            const edges = [hasFieldEdge('opportunity', 'accountId'), lookupEdge('accountId', 'account', 'AccountId', MASTER_DETAIL_TO)];
            const view = buildObjectRelationshipView(nodes, edges, 'opportunity');
            expect(view.outgoingRelationships[0].primaryRelationshipType).toBe('MasterDetail');
        });

        it('resolves to Lookup when no field in the group is a master-detail relationship', () => {
            const nodes = [objectNode('account', 'Account', 'Account'), objectNode('user', 'User', 'User'), fieldNode('ownerId', 'OwnerId')];
            const edges = [hasFieldEdge('account', 'ownerId'), lookupEdge('ownerId', 'user', 'OwnerId', LOOKUP_TO)];
            const view = buildObjectRelationshipView(nodes, edges, 'account');
            expect(view.outgoingRelationships[0].primaryRelationshipType).toBe('Lookup');
        });
    });

    describe('isCustomApiName', () => {
        it('treats any "__c"-suffixed API name as Custom', () => {
            expect(isCustomApiName('MyObject__c')).toBe(true);
        });

        it('treats every other API name as Standard', () => {
            expect(isCustomApiName('Account')).toBe(false);
            expect(isCustomApiName(null)).toBe(false);
        });
    });

    describe('root object metadata', () => {
        it('derives Standard/Custom for the center card from its secondaryKey, no new fetch', () => {
            const nodes = [objectNode('customObj', 'My Object', 'My_Object__c')];
            const view = buildObjectRelationshipView(nodes, [], 'customObj');
            expect(view.rootObject.isCustom).toBe(true);
        });
    });

    describe('DEFAULT_VISIBLE_PER_LANE', () => {
        it('is a small, positive bound within the mandate\'s 4-8 range, and the module itself never truncates', () => {
            expect(DEFAULT_VISIBLE_PER_LANE).toBeGreaterThanOrEqual(4);
            expect(DEFAULT_VISIBLE_PER_LANE).toBeLessThanOrEqual(8);
        });
    });
});
