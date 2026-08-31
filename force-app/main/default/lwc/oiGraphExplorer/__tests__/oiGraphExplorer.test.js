import { createElement } from 'lwc';
import OiGraphExplorer from 'c/oiGraphExplorer';
import getGraphFragment from '@salesforce/apex/OI_GraphController.getGraphFragment';
import getNodeDetail from '@salesforce/apex/OI_GraphController.getNodeDetail';
import getRecordFragment from '@salesforce/apex/OI_RecordHierarchyController.getRecordFragment';
import searchApex from '@salesforce/apex/OI_SearchController.search';
import searchRecordsApex from '@salesforce/apex/OI_RecordSearchController.searchRecords';
import getPresentationRegistry from '@salesforce/apex/OI_SettingsController.getPresentationRegistry';
import { resetPresentationRegistryCacheForTests } from 'c/presentationRegistry';

jest.mock('@salesforce/apex/OI_GraphController.getGraphFragment', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_GraphController.getNodeDetail', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_RecordHierarchyController.getRecordFragment', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_SearchController.search', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_RecordSearchController.searchRecords', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_SettingsController.getPresentationRegistry', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function nodeSummaryDto(nodeKey, label) {
    return { nodeKey, typeKey: 'SalesforceMetadata.CustomObject', label, secondaryKey: label, state: 'Active' };
}

/**
 * Field mode's own two-step selection flow (object, then one of its fields — oiGraphExplorer.js's
 * handleFieldModeObjectSelect/handleFieldPicked), used throughout this suite's Field-mode
 * regression tests so each of them proves the SAME underlying radial-canvas/filter-panel
 * machinery Object mode used to exercise directly, now that Object mode has its own canvas.
 */
async function switchToFieldModeAndCenterOnField(element, { objectFragment, fieldCenterFragment }) {
    element.shadowRoot.querySelector('[data-id="analyze-mode-field"]').click();
    await flushPromises();

    getGraphFragment.mockResolvedValueOnce(objectFragment);
    element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: objectFragment.centerNodeKey } }));
    await flushPromises();

    getGraphFragment.mockResolvedValueOnce(fieldCenterFragment);
    const picker = element.shadowRoot.querySelector('[data-id="field-mode-field-picker"]');
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: fieldCenterFragment.centerNodeKey } }));
    await flushPromises();
}

describe('c-oi-graph-explorer', () => {
    beforeEach(() => {
        getGraphFragment.mockReset();
        getNodeDetail.mockReset();
        getRecordFragment.mockReset();
        searchApex.mockReset();
        searchRecordsApex.mockReset();
        getPresentationRegistry.mockReset();
        getPresentationRegistry.mockResolvedValue({ nodeTypes: [], edgeTypes: [] });
        getNodeDetail.mockResolvedValue({ nodeKey: 'root', typeKey: 'SalesforceMetadata.CustomObject', label: 'Root', secondaryKey: 'Root', attributes: {} });
        resetPresentationRegistryCacheForTests();
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('shows the placeholder until a node is selected — no fetch happens on initial render (GraphUI.md §14)', async () => {
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="explorer-placeholder"]')).not.toBeNull();
        expect(getGraphFragment).not.toHaveBeenCalled();
    });

    it('switching Analyze mode tabs clears the previous tab\'s loaded graph instead of leaving it rendered underneath the new tab (audit #01 — a tab switch is a fresh view, GraphUI.md §11)', async () => {
        getGraphFragment.mockResolvedValueOnce({ centerNodeKey: 'root', nodes: [nodeSummaryDto('root', 'Root')], edges: [], frontier: ['root'], hasMore: false, nextCursor: null });
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'root' } }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-oi-relationship-canvas')).not.toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="explorer-placeholder"]')).toBeNull();

        element.shadowRoot.querySelector('[data-id="analyze-mode-field"]').click();
        await flushPromises();

        // The stale Object-mode center must not leak into Field mode's own (empty) view — the
        // shell must show its placeholder again, not the previous tab's nodes/edges under a
        // different canvas.
        expect(element.shadowRoot.querySelector('c-oi-relationship-canvas')).toBeNull();
        expect(element.shadowRoot.querySelector('c-oi-graph-canvas')).toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="explorer-placeholder"]')).not.toBeNull();
    });

    describe('Object analyze mode — GraphUI.md §42, ADR-0023', () => {
        it('a search selection in the default Object Analyze mode issues a 2-hop getGraphFragment call and renders the Object Relationship canvas, never the radial canvas', async () => {
            getGraphFragment.mockResolvedValue({ centerNodeKey: 'root', nodes: [nodeSummaryDto('root', 'Root')], edges: [], frontier: ['root'], hasMore: false, nextCursor: null });
            const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
            document.body.appendChild(element);
            await flushPromises();

            const searchBar = element.shadowRoot.querySelector('c-oi-search-bar');
            searchBar.dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'root' } }));
            await flushPromises();

            expect(getGraphFragment).toHaveBeenCalledWith({ nodeKey: 'root', hopDepth: 2, pageCursor: null, knownChecksums: {} });
            expect(element.shadowRoot.querySelector('c-oi-relationship-canvas')).not.toBeNull();
            expect(element.shadowRoot.querySelector('c-oi-graph-canvas')).toBeNull();
            expect(element.shadowRoot.querySelector('c-oi-filter-panel')).toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="explorer-placeholder"]')).toBeNull();
        });

        it('passes the full, unfiltered working set to the Object Relationship canvas — the container does no Object-only/field-pruning itself; that filtering is the new canvas\'s own job (objectRelationshipView.js), not oiGraphExplorer\'s', async () => {
            getGraphFragment.mockResolvedValueOnce({
                centerNodeKey: 'root',
                nodes: [
                    nodeSummaryDto('root', 'Root'),
                    { nodeKey: 'plainField', typeKey: 'SalesforceMetadata.CustomField', label: 'Description__c', secondaryKey: 'Root.Description__c', state: 'Active' },
                    { nodeKey: 'apexClass1', typeKey: 'SalesforceMetadata.ApexClass', label: 'RootHelper', secondaryKey: 'RootHelper', state: 'Active' }
                ],
                edges: [
                    { edgeKey: 'e1', typeKey: 'SalesforceMetadata.HAS_FIELD', sourceNodeKey: 'root', targetNodeKey: 'plainField' },
                    { edgeKey: 'e2', typeKey: 'SalesforceMetadata.EXECUTES_ON', sourceNodeKey: 'apexClass1', targetNodeKey: 'root' }
                ],
                frontier: ['root'],
                hasMore: false,
                nextCursor: null
            });
            const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
            document.body.appendChild(element);
            await flushPromises();

            element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'root' } }));
            await flushPromises();

            const canvas = element.shadowRoot.querySelector('c-oi-relationship-canvas');
            expect(canvas.nodes.map((n) => n.nodeKey).sort()).toEqual(['apexClass1', 'plainField', 'root']);
            expect(canvas.edges.map((e) => e.edgeKey).sort()).toEqual(['e1', 'e2']);
        });

        it('computes and passes objectRelationshipSummary (Self/Referenced/Referencing Object counts) to the Intelligence Panel, derived from the same working set the canvas uses — no new fetch', async () => {
            getGraphFragment.mockResolvedValueOnce({
                centerNodeKey: 'account',
                nodes: [
                    nodeSummaryDto('account', 'Account'),
                    nodeSummaryDto('opportunity', 'Opportunity'),
                    nodeSummaryDto('user', 'User'),
                    { nodeKey: 'accountId', typeKey: 'SalesforceMetadata.CustomField', label: 'AccountId', secondaryKey: 'Opportunity.AccountId', state: 'Active' },
                    { nodeKey: 'ownerId', typeKey: 'SalesforceMetadata.CustomField', label: 'OwnerId', secondaryKey: 'Account.OwnerId', state: 'Active' },
                    { nodeKey: 'parentId', typeKey: 'SalesforceMetadata.CustomField', label: 'ParentId', secondaryKey: 'Account.ParentId', state: 'Active' }
                ],
                edges: [
                    { edgeKey: 'e1', typeKey: 'SalesforceMetadata.HAS_FIELD', sourceNodeKey: 'opportunity', targetNodeKey: 'accountId' },
                    { edgeKey: 'e2', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'accountId', targetNodeKey: 'account' },
                    { edgeKey: 'e3', typeKey: 'SalesforceMetadata.HAS_FIELD', sourceNodeKey: 'account', targetNodeKey: 'ownerId' },
                    { edgeKey: 'e4', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'ownerId', targetNodeKey: 'user' },
                    { edgeKey: 'e5', typeKey: 'SalesforceMetadata.HAS_FIELD', sourceNodeKey: 'account', targetNodeKey: 'parentId' },
                    { edgeKey: 'e6', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'parentId', targetNodeKey: 'account' }
                ],
                frontier: ['account'],
                hasMore: false,
                nextCursor: null
            });
            const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
            document.body.appendChild(element);
            await flushPromises();

            element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'account' } }));
            await flushPromises();

            const panel = element.shadowRoot.querySelector('c-oi-node-detail-panel');
            expect(panel.objectRelationshipSummary).toEqual({ selfRelationships: 1, referencedObjects: 1, referencingObjects: 1 });
        });

        it('"Explore From Here" re-centers the graph on the neighbor object exactly like a fresh search selection, using Object mode\'s own 2-hop depth', async () => {
            getGraphFragment.mockResolvedValueOnce({ centerNodeKey: 'root', nodes: [nodeSummaryDto('root', 'Root')], edges: [], frontier: ['root'], hasMore: false, nextCursor: null });
            const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
            document.body.appendChild(element);
            await flushPromises();

            element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'root' } }));
            await flushPromises();

            getGraphFragment.mockResolvedValueOnce({ centerNodeKey: 'neighbor', nodes: [nodeSummaryDto('neighbor', 'Neighbor')], edges: [], frontier: ['neighbor'], hasMore: false, nextCursor: null });
            element.shadowRoot.querySelector('c-oi-relationship-canvas').dispatchEvent(new CustomEvent('explorefromhere', { detail: { nodeKey: 'neighbor' } }));
            await flushPromises();

            expect(getGraphFragment).toHaveBeenLastCalledWith({ nodeKey: 'neighbor', hopDepth: 2, pageCursor: null, knownChecksums: {} });
            expect(element.shadowRoot.querySelector('c-oi-relationship-canvas').centerNodeKey).toBe('neighbor');
        });

        it('an edgeclick from the Object Relationship canvas opens oiRelationshipConnectorDetail with the connector descriptor, and closing it clears the state', async () => {
            getGraphFragment.mockResolvedValueOnce({ centerNodeKey: 'root', nodes: [nodeSummaryDto('root', 'Root')], edges: [], frontier: ['root'], hasMore: false, nextCursor: null });
            const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
            document.body.appendChild(element);
            await flushPromises();

            element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'root' } }));
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-oi-relationship-connector-detail')).toBeNull();

            const connector = { connectorKey: 'outgoing::neighbor', direction: 'outgoing', counterpartObject: { nodeKey: 'neighbor', label: 'Neighbor' }, fields: [], relationshipCount: 1, primaryRelationshipType: 'Lookup', isSystemRelationship: false };
            const rootObject = { nodeKey: 'root', label: 'Root' };
            element.shadowRoot.querySelector('c-oi-relationship-canvas').dispatchEvent(new CustomEvent('edgeclick', { detail: { connector, rootObject } }));
            await flushPromises();

            const detail = element.shadowRoot.querySelector('c-oi-relationship-connector-detail');
            expect(detail).not.toBeNull();
            expect(detail.connector.connectorKey).toBe('outgoing::neighbor');

            detail.dispatchEvent(new CustomEvent('close'));
            await flushPromises();
            expect(element.shadowRoot.querySelector('c-oi-relationship-connector-detail')).toBeNull();
        });

        it('a highlightimpact event from the detail panel still merges into the shared view-state in Object mode (the reference-counting unification, GraphUI.md §7, is mode-agnostic) even though the merged node is not itself an object-to-object relationship', async () => {
            getGraphFragment.mockResolvedValueOnce({ centerNodeKey: 'root', nodes: [nodeSummaryDto('root', 'Root')], edges: [], frontier: ['root'], hasMore: false, nextCursor: null });
            const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
            document.body.appendChild(element);
            await flushPromises();

            element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'root' } }));
            await flushPromises();

            const detailPanel = element.shadowRoot.querySelector('c-oi-node-detail-panel');
            detailPanel.dispatchEvent(
                new CustomEvent('highlightimpact', {
                    detail: {
                        nodeKey: 'root',
                        fragment: {
                            nodes: [{ nodeKey: 'impactedClass', typeKey: 'SalesforceMetadata.ApexClass', label: 'ImpactedClass', secondaryKey: 'ImpactedClass', state: 'Active' }],
                            edges: [{ edgeKey: 'impactEdge1', typeKey: 'SalesforceMetadata.REFERENCES', sourceNodeKey: 'root', targetNodeKey: 'impactedClass' }],
                            hasMore: false,
                            nextCursor: null
                        }
                    }
                })
            );
            await flushPromises();

            const canvas = element.shadowRoot.querySelector('c-oi-relationship-canvas');
            expect(canvas.nodes.map((n) => n.nodeKey)).toContain('impactedClass');
            expect(canvas.edges.map((e) => e.edgeKey)).toContain('impactEdge1');
        });
    });

    it('switching to Field Analyze mode issues a 1-hop getGraphFragment call on the next search selection — enough to reach both the parent object and any referenced object', async () => {
        getGraphFragment.mockResolvedValue({ centerNodeKey: 'root', nodes: [nodeSummaryDto('root', 'Root')], edges: [], frontier: ['root'], hasMore: false, nextCursor: null });
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="analyze-mode-field"]').click();
        await flushPromises();

        element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'root' } }));
        await flushPromises();

        expect(getGraphFragment).toHaveBeenCalledWith({ nodeKey: 'root', hopDepth: 1, pageCursor: null, knownChecksums: {} });
    });

    it('Record mode requires picking the object first (zero-hop resolve), then searches actual records of that object and centers on the picked one', async () => {
        getGraphFragment.mockResolvedValueOnce({ centerNodeKey: 'acct', nodes: [nodeSummaryDto('acct', 'Account')], edges: [], frontier: ['acct'], hasMore: false, nextCursor: null });
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="analyze-mode-record"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="analyze-mode-record"]').getAttribute('aria-selected')).toBe('true');
        expect(element.shadowRoot.querySelector('c-oi-search-bar')).not.toBeNull();

        element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'acct' } }));
        await flushPromises();

        expect(getGraphFragment).toHaveBeenCalledWith({ nodeKey: 'acct', hopDepth: 0, pageCursor: null, knownChecksums: {} });
        expect(element.shadowRoot.querySelector('[data-id="record-mode-object-banner"]').textContent).toContain('Account');
        expect(element.shadowRoot.querySelector('c-oi-record-picker').objectApiName).toBe('Account');

        getRecordFragment.mockResolvedValueOnce({
            centerNodeKey: 'Record::Account::001x1',
            nodes: [{ nodeKey: 'Record::Account::001x1', typeKey: 'SalesforceRecord.Account', label: 'Acme Corp', secondaryKey: 'Account 001x1', state: 'Active' }],
            edges: [],
            hasMore: false
        });
        element.shadowRoot.querySelector('c-oi-record-picker').dispatchEvent(new CustomEvent('select', { detail: { recordId: '001x1' } }));
        await flushPromises();

        expect(getRecordFragment).toHaveBeenCalledWith({ objectApiName: 'Account', recordId: '001x1' });
        // Record mode shares the Object-mode lane canvas (ADR-0024), not the generic radial canvas.
        expect(element.shadowRoot.querySelector('c-oi-graph-canvas')).toBeNull();
        const canvas = element.shadowRoot.querySelector('c-oi-relationship-canvas');
        expect(canvas).not.toBeNull();
        expect(canvas.mode).toBe('Record');
    });

    it('"Change object" in Record mode returns to the object search step', async () => {
        getGraphFragment.mockResolvedValueOnce({ centerNodeKey: 'acct', nodes: [nodeSummaryDto('acct', 'Account')], edges: [], frontier: ['acct'], hasMore: false, nextCursor: null });
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="analyze-mode-record"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'acct' } }));
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="record-mode-change-object"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-oi-search-bar')).not.toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="record-mode-object-banner"]')).toBeNull();
    });

    it('"Explore From Here" on a related record card calls getRecordFragment (via selectAndCenterRecord), not getGraphFragment, based on the nodeKey format alone — Record mode has no expand/collapse of its own, only re-centering (ADR-0024)', async () => {
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="analyze-mode-record"]').click();
        await flushPromises();
        getGraphFragment.mockResolvedValueOnce({ centerNodeKey: 'acct', nodes: [nodeSummaryDto('acct', 'Account')], edges: [], frontier: ['acct'], hasMore: false, nextCursor: null });
        element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'acct' } }));
        await flushPromises();

        getRecordFragment.mockResolvedValueOnce({
            centerNodeKey: 'Record::Account::001x1',
            nodes: [
                { nodeKey: 'Record::Account::001x1', typeKey: 'SalesforceRecord.Account', label: 'Acme Corp', secondaryKey: 'Account', state: 'Active' },
                { nodeKey: 'Record::Contact::003x1', typeKey: 'SalesforceRecord.Contact', label: 'Jane Doe', secondaryKey: 'Contact', state: 'Active' }
            ],
            edges: [{ edgeKey: 'e1', typeKey: 'SalesforceRecord.CHILD_OF', sourceNodeKey: 'Record::Account::001x1', targetNodeKey: 'Record::Contact::003x1' }],
            hasMore: false
        });
        element.shadowRoot.querySelector('c-oi-record-picker').dispatchEvent(new CustomEvent('select', { detail: { recordId: '001x1' } }));
        await flushPromises();

        getRecordFragment.mockResolvedValueOnce({
            centerNodeKey: 'Record::Contact::003x1',
            nodes: [{ nodeKey: 'Record::Contact::003x1', typeKey: 'SalesforceRecord.Contact', label: 'Jane Doe', secondaryKey: 'Contact', state: 'Active' }],
            edges: [],
            hasMore: false
        });
        element.shadowRoot.querySelector('c-oi-relationship-canvas').dispatchEvent(new CustomEvent('explorefromhere', { detail: { nodeKey: 'Record::Contact::003x1' } }));
        await flushPromises();

        expect(getRecordFragment).toHaveBeenLastCalledWith({ objectApiName: 'Contact', recordId: '003x1' });
        expect(getGraphFragment).not.toHaveBeenCalledWith(expect.objectContaining({ nodeKey: 'Record::Contact::003x1' }));
    });

    it('Field mode requires picking the object first, then lists only that object\'s own fields to choose from', async () => {
        getGraphFragment.mockResolvedValueOnce({
            centerNodeKey: 'acct',
            nodes: [
                nodeSummaryDto('acct', 'Account'),
                { nodeKey: 'acct.name', typeKey: 'SalesforceMetadata.CustomField', label: 'Account Name', secondaryKey: 'Name', state: 'Active' },
                { nodeKey: 'contact.name', typeKey: 'SalesforceMetadata.CustomField', label: 'Contact Name', secondaryKey: 'Contact.Name', state: 'Active' }
            ],
            edges: [{ edgeKey: 'e1', typeKey: 'SalesforceMetadata.HAS_FIELD', sourceNodeKey: 'acct', targetNodeKey: 'acct.name' }],
            frontier: ['acct'],
            hasMore: false,
            nextCursor: null
        });
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="analyze-mode-field"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-oi-search-bar')).not.toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="field-mode-field-picker"]')).toBeNull();

        element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'acct' } }));
        await flushPromises();

        expect(getGraphFragment).toHaveBeenCalledWith({ nodeKey: 'acct', hopDepth: 1, pageCursor: null, knownChecksums: {} });
        expect(element.shadowRoot.querySelector('c-oi-search-bar')).toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="field-mode-object-banner"]').textContent).toContain('Account');

        const picker = element.shadowRoot.querySelector('[data-id="field-mode-field-picker"]');
        expect(picker.options).toHaveLength(1);
        expect(picker.options[0].value).toBe('acct.name');

        getGraphFragment.mockResolvedValueOnce({ centerNodeKey: 'acct.name', nodes: [nodeSummaryDto('acct.name', 'Account Name')], edges: [], frontier: ['acct.name'], hasMore: false, nextCursor: null });
        picker.dispatchEvent(new CustomEvent('change', { detail: { value: 'acct.name' } }));
        await flushPromises();

        expect(getGraphFragment).toHaveBeenLastCalledWith({ nodeKey: 'acct.name', hopDepth: 1, pageCursor: null, knownChecksums: {} });
        expect(element.shadowRoot.querySelector('c-oi-graph-canvas')).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-oi-relationship-canvas')).toBeNull();
    });

    it('"Change object" in Field mode returns to the object search step', async () => {
        getGraphFragment.mockResolvedValueOnce({ centerNodeKey: 'acct', nodes: [nodeSummaryDto('acct', 'Account')], edges: [], frontier: ['acct'], hasMore: false, nextCursor: null });
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="analyze-mode-field"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'acct' } }));
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="field-mode-change-object"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-oi-search-bar')).not.toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="field-mode-object-banner"]')).toBeNull();
    });

    describe('Field mode regression — the radial canvas + filter panel machinery Object mode no longer exercises directly', () => {
        function fieldModeObjectFragment() {
            return { centerNodeKey: 'acct', nodes: [nodeSummaryDto('acct', 'Account'), { nodeKey: 'acct.name', typeKey: 'SalesforceMetadata.CustomField', label: 'Name', secondaryKey: 'Name', state: 'Active' }], edges: [{ edgeKey: 'e1', typeKey: 'SalesforceMetadata.HAS_FIELD', sourceNodeKey: 'acct', targetNodeKey: 'acct.name' }], frontier: ['acct'], hasMore: false, nextCursor: null };
        }

        it('an expand event issues a one-hop getGraphFragment call and grows the rendered canvas node set', async () => {
            const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
            document.body.appendChild(element);
            await flushPromises();

            await switchToFieldModeAndCenterOnField(element, {
                objectFragment: fieldModeObjectFragment(),
                fieldCenterFragment: { centerNodeKey: 'acct.name', nodes: [nodeSummaryDto('acct.name', 'Account Name')], edges: [], frontier: ['acct.name'], hasMore: false, nextCursor: null }
            });

            getGraphFragment.mockResolvedValueOnce({
                centerNodeKey: 'acct.name',
                nodes: [nodeSummaryDto('child1', 'Child1')],
                edges: [{ edgeKey: 'e2', typeKey: 'SalesforceMetadata.HAS_FIELD', sourceNodeKey: 'acct.name', targetNodeKey: 'child1' }],
                frontier: ['child1'],
                hasMore: false,
                nextCursor: null
            });
            const canvas = element.shadowRoot.querySelector('c-oi-graph-canvas');
            canvas.dispatchEvent(new CustomEvent('expand', { detail: { nodeKey: 'acct.name' } }));
            await flushPromises();

            expect(getGraphFragment).toHaveBeenLastCalledWith({ nodeKey: 'acct.name', hopDepth: 1, pageCursor: null, knownChecksums: {} });
            const canvasAfter = element.shadowRoot.querySelector('c-oi-graph-canvas');
            expect(canvasAfter.nodes).toHaveLength(2);
        });

        it('passes registry-resolved display labels to the filter panel once edges are visible (Backlog UI-4)', async () => {
            getPresentationRegistry.mockResolvedValue({
                nodeTypes: [],
                edgeTypes: [{ typeKey: 'SalesforceMetadata.LOOKUP_TO', displayLabel: 'Lookup To', lineStyle: 'dashed' }]
            });
            const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
            document.body.appendChild(element);
            await flushPromises();

            await switchToFieldModeAndCenterOnField(element, {
                objectFragment: fieldModeObjectFragment(),
                fieldCenterFragment: { centerNodeKey: 'acct.name', nodes: [nodeSummaryDto('acct.name', 'Account Name')], edges: [], frontier: ['acct.name'], hasMore: false, nextCursor: null }
            });

            getGraphFragment.mockResolvedValueOnce({
                centerNodeKey: 'acct.name',
                nodes: [nodeSummaryDto('child1', 'Child1')],
                edges: [{ edgeKey: 'e2', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'acct.name', targetNodeKey: 'child1' }],
                frontier: ['child1'],
                hasMore: false,
                nextCursor: null
            });
            element.shadowRoot.querySelector('c-oi-graph-canvas').dispatchEvent(new CustomEvent('expand', { detail: { nodeKey: 'acct.name' } }));
            await flushPromises();

            const filterPanel = element.shadowRoot.querySelector('c-oi-filter-panel');
            expect(filterPanel).not.toBeNull();
            expect(filterPanel.edgeTypeOptions).toHaveLength(1);
            expect(filterPanel.edgeTypeOptions[0].displayLabel).toBe('Lookup To');
            expect(filterPanel.edgeTypeOptions[0].isChecked).toBe(true);
        });

        it('unchecking an edge type in the filter panel hides that edge (and any node reachable only through it) from the canvas, and rechecking it restores both', async () => {
            getPresentationRegistry.mockResolvedValue({
                nodeTypes: [],
                edgeTypes: [{ typeKey: 'SalesforceMetadata.LOOKUP_TO', displayLabel: 'Lookup To', lineStyle: 'dashed' }]
            });
            const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
            document.body.appendChild(element);
            await flushPromises();

            await switchToFieldModeAndCenterOnField(element, {
                objectFragment: fieldModeObjectFragment(),
                fieldCenterFragment: { centerNodeKey: 'acct.name', nodes: [nodeSummaryDto('acct.name', 'Account Name')], edges: [], frontier: ['acct.name'], hasMore: false, nextCursor: null }
            });

            getGraphFragment.mockResolvedValueOnce({
                centerNodeKey: 'acct.name',
                nodes: [nodeSummaryDto('child1', 'Child1')],
                edges: [{ edgeKey: 'e2', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'acct.name', targetNodeKey: 'child1' }],
                frontier: ['child1'],
                hasMore: false,
                nextCursor: null
            });
            element.shadowRoot.querySelector('c-oi-graph-canvas').dispatchEvent(new CustomEvent('expand', { detail: { nodeKey: 'acct.name' } }));
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-oi-graph-canvas').edges).toHaveLength(1);
            expect(element.shadowRoot.querySelector('c-oi-graph-canvas').nodes).toHaveLength(2);

            const filterPanel = element.shadowRoot.querySelector('c-oi-filter-panel');
            filterPanel.dispatchEvent(new CustomEvent('edgetypetoggle', { detail: { typeKey: 'SalesforceMetadata.LOOKUP_TO' } }));
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-oi-graph-canvas').edges).toHaveLength(0);
            expect(element.shadowRoot.querySelector('c-oi-graph-canvas').nodes).toHaveLength(1);
            expect(element.shadowRoot.querySelector('c-oi-filter-panel').edgeTypeOptions[0].isChecked).toBe(false);

            element.shadowRoot.querySelector('c-oi-filter-panel').dispatchEvent(new CustomEvent('edgetypetoggle', { detail: { typeKey: 'SalesforceMetadata.LOOKUP_TO' } }));
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-oi-graph-canvas').edges).toHaveLength(1);
            expect(element.shadowRoot.querySelector('c-oi-graph-canvas').nodes).toHaveLength(2);
            expect(element.shadowRoot.querySelector('c-oi-filter-panel').edgeTypeOptions[0].isChecked).toBe(true);
        });

        it('a "Parent Objects" direction selection (outgoing only) hides a node reachable only via an incoming edge from the center', async () => {
            getPresentationRegistry.mockResolvedValue({
                nodeTypes: [],
                edgeTypes: [{ typeKey: 'SalesforceMetadata.LOOKUP_TO', displayLabel: 'Lookup To', lineStyle: 'dashed' }]
            });
            const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
            document.body.appendChild(element);
            await flushPromises();

            await switchToFieldModeAndCenterOnField(element, {
                objectFragment: fieldModeObjectFragment(),
                fieldCenterFragment: {
                    centerNodeKey: 'contact.name',
                    nodes: [nodeSummaryDto('contact.name', 'Contact Name'), nodeSummaryDto('account', 'Account'), nodeSummaryDto('opportunity', 'Opportunity')],
                    edges: [
                        { edgeKey: 'e1', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'contact.name', targetNodeKey: 'account' },
                        { edgeKey: 'e2', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'opportunity', targetNodeKey: 'contact.name' }
                    ],
                    frontier: [],
                    hasMore: false,
                    nextCursor: null
                }
            });

            expect(element.shadowRoot.querySelector('c-oi-graph-canvas').nodes).toHaveLength(3);

            const filterPanel = element.shadowRoot.querySelector('c-oi-filter-panel');
            filterPanel.dispatchEvent(new CustomEvent('directiontoggle', { detail: { showParents: true, showChildren: false } }));
            await flushPromises();

            const canvasNodeKeys = element.shadowRoot.querySelector('c-oi-graph-canvas').nodes.map((n) => n.nodeKey).sort();
            expect(canvasNodeKeys).toEqual(['account', 'contact.name']);
        });

        it('unchecking both direction checkboxes at once is a no-op — it never leaves the canvas with nothing but the center node', async () => {
            getPresentationRegistry.mockResolvedValue({
                nodeTypes: [],
                edgeTypes: [{ typeKey: 'SalesforceMetadata.LOOKUP_TO', displayLabel: 'Lookup To', lineStyle: 'dashed' }]
            });
            const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
            document.body.appendChild(element);
            await flushPromises();

            await switchToFieldModeAndCenterOnField(element, {
                objectFragment: fieldModeObjectFragment(),
                fieldCenterFragment: {
                    centerNodeKey: 'contact.name',
                    nodes: [nodeSummaryDto('contact.name', 'Contact Name'), nodeSummaryDto('account', 'Account')],
                    edges: [{ edgeKey: 'e1', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'contact.name', targetNodeKey: 'account' }],
                    frontier: [],
                    hasMore: false,
                    nextCursor: null
                }
            });

            element.shadowRoot.querySelector('c-oi-filter-panel').dispatchEvent(new CustomEvent('directiontoggle', { detail: { showParents: false, showChildren: false } }));
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-oi-graph-canvas').nodes).toHaveLength(2);
            expect(element.shadowRoot.querySelector('c-oi-filter-panel').direction).toBe('both');
        });

        it('checking "Direct relationships only" hides a grandparent that is only reachable two hops out', async () => {
            getPresentationRegistry.mockResolvedValue({
                nodeTypes: [],
                edgeTypes: [{ typeKey: 'SalesforceMetadata.LOOKUP_TO', displayLabel: 'Lookup To', lineStyle: 'dashed' }]
            });
            const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
            document.body.appendChild(element);
            await flushPromises();

            await switchToFieldModeAndCenterOnField(element, {
                objectFragment: fieldModeObjectFragment(),
                fieldCenterFragment: {
                    centerNodeKey: 'contact.name',
                    nodes: [nodeSummaryDto('contact.name', 'Contact Name'), nodeSummaryDto('account', 'Account'), nodeSummaryDto('parentAccount', 'Parent Account')],
                    edges: [
                        { edgeKey: 'e1', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'contact.name', targetNodeKey: 'account' },
                        { edgeKey: 'e2', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'account', targetNodeKey: 'parentAccount' }
                    ],
                    frontier: [],
                    hasMore: false,
                    nextCursor: null
                }
            });

            expect(element.shadowRoot.querySelector('c-oi-graph-canvas').nodes).toHaveLength(3);

            element.shadowRoot.querySelector('c-oi-filter-panel').dispatchEvent(new CustomEvent('depthtoggle', { detail: { restrictToDirectOnly: true } }));
            await flushPromises();

            const canvasNodeKeys = element.shadowRoot.querySelector('c-oi-graph-canvas').nodes.map((n) => n.nodeKey).sort();
            expect(canvasNodeKeys).toEqual(['account', 'contact.name']);
        });

        it('selecting a new center resets the relationship filter back to its unrestricted default', async () => {
            getPresentationRegistry.mockResolvedValue({
                nodeTypes: [],
                edgeTypes: [{ typeKey: 'SalesforceMetadata.LOOKUP_TO', displayLabel: 'Lookup To', lineStyle: 'dashed' }]
            });
            const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
            document.body.appendChild(element);
            await flushPromises();

            await switchToFieldModeAndCenterOnField(element, {
                objectFragment: fieldModeObjectFragment(),
                fieldCenterFragment: {
                    centerNodeKey: 'contact.name',
                    nodes: [nodeSummaryDto('contact.name', 'Contact Name'), nodeSummaryDto('account', 'Account')],
                    edges: [{ edgeKey: 'e1', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'contact.name', targetNodeKey: 'account' }],
                    frontier: [],
                    hasMore: false,
                    nextCursor: null
                }
            });

            element.shadowRoot.querySelector('c-oi-filter-panel').dispatchEvent(new CustomEvent('edgetypetoggle', { detail: { typeKey: 'SalesforceMetadata.LOOKUP_TO' } }));
            await flushPromises();
            expect(element.shadowRoot.querySelector('c-oi-filter-panel').edgeTypeOptions[0].isChecked).toBe(false);

            // Picking a different field from the still-visible field picker (no need to re-search the object) is itself a fresh center — the same selectAndCenter path a new search selection would take.
            getGraphFragment.mockResolvedValueOnce({
                centerNodeKey: 'newRoot',
                nodes: [nodeSummaryDto('newRoot', 'New Root'), nodeSummaryDto('newChild', 'New Child')],
                edges: [{ edgeKey: 'e2', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'newRoot', targetNodeKey: 'newChild' }],
                frontier: [],
                hasMore: false,
                nextCursor: null
            });
            element.shadowRoot.querySelector('[data-id="field-mode-field-picker"]').dispatchEvent(new CustomEvent('change', { detail: { value: 'newRoot' } }));
            await flushPromises();

            // The same typeKey the prior view had hidden must come back checked (visible) on the new center — a fresh center is a fresh filter, not a carried-over one.
            expect(element.shadowRoot.querySelector('c-oi-filter-panel').edgeTypeOptions[0].isChecked).toBe(true);
            expect(element.shadowRoot.querySelector('c-oi-graph-canvas').nodes).toHaveLength(2);
        });
    });

    describe('Object mode search hierarchy (VisualDesignSpecification.md §3.1/§3.2 — analyzed-state composition)', () => {
        it('collapses the full search bar into a compact "Object: <label>" banner once an object is analyzed, and restores the search bar via "Change object"', async () => {
            getGraphFragment.mockResolvedValueOnce({ centerNodeKey: 'root', nodes: [nodeSummaryDto('root', 'Root')], edges: [], frontier: ['root'], hasMore: false, nextCursor: null });
            const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
            document.body.appendChild(element);
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-oi-search-bar')).not.toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="object-mode-banner"]')).toBeNull();

            element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'root' } }));
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-oi-search-bar')).toBeNull();
            const banner = element.shadowRoot.querySelector('[data-id="object-mode-banner"]');
            expect(banner).not.toBeNull();
            expect(banner.textContent).toContain('Root');

            element.shadowRoot.querySelector('[data-id="object-mode-change-object"]').click();
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-oi-search-bar')).not.toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="object-mode-banner"]')).toBeNull();
        });

        it('re-collapses the search bar back to the compact banner once a new object is selected from it', async () => {
            getGraphFragment.mockResolvedValueOnce({ centerNodeKey: 'root', nodes: [nodeSummaryDto('root', 'Root')], edges: [], frontier: ['root'], hasMore: false, nextCursor: null });
            const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
            document.body.appendChild(element);
            await flushPromises();

            element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'root' } }));
            await flushPromises();
            element.shadowRoot.querySelector('[data-id="object-mode-change-object"]').click();
            await flushPromises();

            getGraphFragment.mockResolvedValueOnce({ centerNodeKey: 'other', nodes: [nodeSummaryDto('other', 'Other')], edges: [], frontier: ['other'], hasMore: false, nextCursor: null });
            element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'other' } }));
            await flushPromises();

            expect(element.shadowRoot.querySelector('c-oi-search-bar')).toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="object-mode-banner"]').textContent).toContain('Other');
        });
    });

    it('renders a sanitized error banner when getGraphFragment fails, without throwing', async () => {
        getGraphFragment.mockRejectedValue({ body: { message: 'You don\'t have permission to view org graph data.' } });
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'root' } }));
        await flushPromises();

        const errorEl = element.shadowRoot.querySelector('[data-id="explorer-error"]');
        expect(errorEl).not.toBeNull();
        expect(errorEl.textContent).toContain('permission');
    });
});
