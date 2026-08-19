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

    it('a search selection in the default Object Analyze mode issues a 2-hop getGraphFragment call — enough to reach both referenced and referencing objects in one fetch', async () => {
        getGraphFragment.mockResolvedValue({ centerNodeKey: 'root', nodes: [nodeSummaryDto('root', 'Root')], edges: [], frontier: ['root'], hasMore: false, nextCursor: null });
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        const searchBar = element.shadowRoot.querySelector('c-oi-search-bar');
        searchBar.dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'root' } }));
        await flushPromises();

        expect(getGraphFragment).toHaveBeenCalledWith({ nodeKey: 'root', hopDepth: 2, pageCursor: null, knownChecksums: {} });
        expect(element.shadowRoot.querySelector('c-oi-graph-canvas')).not.toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="explorer-placeholder"]')).toBeNull();
    });

    it('Object mode\'s default view hides a plain field (no relationship of its own) but keeps a field that creates a relationship, plus the object it connects to — the declutter fix for the "whole web" complaint', async () => {
        getGraphFragment.mockResolvedValueOnce({
            centerNodeKey: 'root',
            nodes: [
                nodeSummaryDto('root', 'Root'),
                { nodeKey: 'plainField', typeKey: 'SalesforceMetadata.CustomField', label: 'Description__c', secondaryKey: 'Root.Description__c', state: 'Active' },
                { nodeKey: 'connectorField', typeKey: 'SalesforceMetadata.CustomField', label: 'OwnerId', secondaryKey: 'Root.OwnerId', state: 'Active' },
                nodeSummaryDto('related', 'User')
            ],
            edges: [
                { edgeKey: 'e1', typeKey: 'SalesforceMetadata.HAS_FIELD', sourceNodeKey: 'root', targetNodeKey: 'plainField' },
                { edgeKey: 'e2', typeKey: 'SalesforceMetadata.HAS_FIELD', sourceNodeKey: 'root', targetNodeKey: 'connectorField' },
                { edgeKey: 'e3', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'connectorField', targetNodeKey: 'related' }
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

        const canvas = element.shadowRoot.querySelector('c-oi-graph-canvas');
        expect(canvas.nodes.map((n) => n.nodeKey).sort()).toEqual(['connectorField', 'related', 'root']);
        expect(canvas.edges.map((e) => e.edgeKey).sort()).toEqual(['e2', 'e3']);
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
        expect(element.shadowRoot.querySelector('c-oi-graph-canvas')).not.toBeNull();
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

    it('an expand on a record node calls getRecordFragment, not getGraphFragment, based on the nodeKey format alone', async () => {
        getRecordFragment.mockResolvedValueOnce({
            centerNodeKey: 'Record::Account::001x1',
            nodes: [{ nodeKey: 'Record::Account::001x1', typeKey: 'SalesforceRecord.Account', label: 'Acme Corp', secondaryKey: 'Account 001x1', state: 'Active' }],
            edges: [],
            hasMore: false
        });
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="analyze-mode-record"]').click();
        await flushPromises();
        getGraphFragment.mockResolvedValueOnce({ centerNodeKey: 'acct', nodes: [nodeSummaryDto('acct', 'Account')], edges: [], frontier: ['acct'], hasMore: false, nextCursor: null });
        element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'acct' } }));
        await flushPromises();
        element.shadowRoot.querySelector('c-oi-record-picker').dispatchEvent(new CustomEvent('select', { detail: { recordId: '001x1' } }));
        await flushPromises();

        getRecordFragment.mockResolvedValueOnce({
            centerNodeKey: 'Record::Account::001x1',
            nodes: [
                { nodeKey: 'Record::Account::001x1', typeKey: 'SalesforceRecord.Account', label: 'Acme Corp', secondaryKey: 'Account 001x1', state: 'Active' },
                { nodeKey: 'Record::Contact::003x1', typeKey: 'SalesforceRecord.Contact', label: 'Jane Doe', secondaryKey: 'Contact 003x1', state: 'Active' }
            ],
            edges: [{ edgeKey: 'e1', typeKey: 'SalesforceRecord.CHILD_OF', sourceNodeKey: 'Record::Account::001x1', targetNodeKey: 'Record::Contact::003x1' }],
            hasMore: false
        });
        element.shadowRoot.querySelector('c-oi-graph-canvas').dispatchEvent(new CustomEvent('expand', { detail: { nodeKey: 'Record::Account::001x1' } }));
        await flushPromises();

        expect(getRecordFragment).toHaveBeenLastCalledWith({ objectApiName: 'Account', recordId: '001x1' });
        expect(getGraphFragment).not.toHaveBeenCalledWith(expect.objectContaining({ nodeKey: 'Record::Account::001x1' }));
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

    it('an expand event issues a one-hop getGraphFragment call and grows the rendered canvas node set', async () => {
        getGraphFragment.mockResolvedValueOnce({ centerNodeKey: 'root', nodes: [nodeSummaryDto('root', 'Root')], edges: [], frontier: ['root'], hasMore: false, nextCursor: null });
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'root' } }));
        await flushPromises();

        getGraphFragment.mockResolvedValueOnce({
            centerNodeKey: 'root',
            nodes: [nodeSummaryDto('child1', 'Child1')],
            edges: [{ edgeKey: 'e1', typeKey: 'SalesforceMetadata.HAS_FIELD', sourceNodeKey: 'root', targetNodeKey: 'child1' }],
            frontier: ['child1'],
            hasMore: false,
            nextCursor: null
        });
        const canvas = element.shadowRoot.querySelector('c-oi-graph-canvas');
        canvas.dispatchEvent(new CustomEvent('expand', { detail: { nodeKey: 'root' } }));
        await flushPromises();

        expect(getGraphFragment).toHaveBeenLastCalledWith({ nodeKey: 'root', hopDepth: 1, pageCursor: null, knownChecksums: {} });
        const canvasAfter = element.shadowRoot.querySelector('c-oi-graph-canvas');
        expect(canvasAfter.nodes).toHaveLength(2);
    });

    it('a highlightimpact event from the detail panel merges the impact subgraph into the canvas exactly like an ordinary expand, via the same applyExpand path (GraphUI.md §7\'s reference-counting unification)', async () => {
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
                        nodes: [nodeSummaryDto('impactedClass', 'ImpactedClass')],
                        edges: [{ edgeKey: 'impactEdge1', typeKey: 'SalesforceMetadata.REFERENCES', sourceNodeKey: 'root', targetNodeKey: 'impactedClass' }],
                        hasMore: false,
                        nextCursor: null
                    }
                }
            })
        );
        await flushPromises();

        const canvas = element.shadowRoot.querySelector('c-oi-graph-canvas');
        expect(canvas.nodes.map((n) => n.nodeKey)).toContain('impactedClass');
        expect(canvas.edges.map((e) => e.edgeKey)).toContain('impactEdge1');
    });

    it('passes registry-resolved display labels to the filter panel once edges are visible (Backlog UI-4)', async () => {
        getPresentationRegistry.mockResolvedValue({
            nodeTypes: [],
            edgeTypes: [{ typeKey: 'SalesforceMetadata.LOOKUP_TO', displayLabel: 'Lookup To', lineStyle: 'dashed' }]
        });
        getGraphFragment.mockResolvedValueOnce({ centerNodeKey: 'root', nodes: [nodeSummaryDto('root', 'Root')], edges: [], frontier: ['root'], hasMore: false, nextCursor: null });
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'root' } }));
        await flushPromises();

        getGraphFragment.mockResolvedValueOnce({
            centerNodeKey: 'root',
            nodes: [nodeSummaryDto('child1', 'Child1')],
            edges: [{ edgeKey: 'e1', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'root', targetNodeKey: 'child1' }],
            frontier: ['child1'],
            hasMore: false,
            nextCursor: null
        });
        element.shadowRoot.querySelector('c-oi-graph-canvas').dispatchEvent(new CustomEvent('expand', { detail: { nodeKey: 'root' } }));
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
        getGraphFragment.mockResolvedValueOnce({ centerNodeKey: 'root', nodes: [nodeSummaryDto('root', 'Root')], edges: [], frontier: ['root'], hasMore: false, nextCursor: null });
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'root' } }));
        await flushPromises();

        getGraphFragment.mockResolvedValueOnce({
            centerNodeKey: 'root',
            nodes: [nodeSummaryDto('child1', 'Child1')],
            edges: [{ edgeKey: 'e1', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'root', targetNodeKey: 'child1' }],
            frontier: ['child1'],
            hasMore: false,
            nextCursor: null
        });
        element.shadowRoot.querySelector('c-oi-graph-canvas').dispatchEvent(new CustomEvent('expand', { detail: { nodeKey: 'root' } }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-oi-graph-canvas').edges).toHaveLength(1);
        expect(element.shadowRoot.querySelector('c-oi-graph-canvas').nodes).toHaveLength(2);

        const filterPanel = element.shadowRoot.querySelector('c-oi-filter-panel');
        filterPanel.dispatchEvent(new CustomEvent('edgetypetoggle', { detail: { typeKey: 'SalesforceMetadata.LOOKUP_TO' } }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-oi-graph-canvas').edges).toHaveLength(0);
        expect(element.shadowRoot.querySelector('c-oi-graph-canvas').nodes).toHaveLength(1, 'child1 is reachable only via the now-excluded edge type, so it must disappear along with the edge, not just the line.');
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
        getGraphFragment.mockResolvedValueOnce({
            centerNodeKey: 'contact',
            nodes: [nodeSummaryDto('contact', 'Contact'), nodeSummaryDto('account', 'Account'), nodeSummaryDto('opportunity', 'Opportunity')],
            edges: [
                { edgeKey: 'e1', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'contact', targetNodeKey: 'account' },
                { edgeKey: 'e2', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'opportunity', targetNodeKey: 'contact' }
            ],
            frontier: [],
            hasMore: false,
            nextCursor: null
        });
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'contact' } }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-oi-graph-canvas').nodes).toHaveLength(3);

        const filterPanel = element.shadowRoot.querySelector('c-oi-filter-panel');
        filterPanel.dispatchEvent(new CustomEvent('directiontoggle', { detail: { showParents: true, showChildren: false } }));
        await flushPromises();

        const canvasNodeKeys = element.shadowRoot.querySelector('c-oi-graph-canvas').nodes.map((n) => n.nodeKey).sort();
        expect(canvasNodeKeys).toEqual(['account', 'contact']);
    });

    it('unchecking both direction checkboxes at once is a no-op — it never leaves the canvas with nothing but the center node', async () => {
        getPresentationRegistry.mockResolvedValue({
            nodeTypes: [],
            edgeTypes: [{ typeKey: 'SalesforceMetadata.LOOKUP_TO', displayLabel: 'Lookup To', lineStyle: 'dashed' }]
        });
        getGraphFragment.mockResolvedValueOnce({
            centerNodeKey: 'contact',
            nodes: [nodeSummaryDto('contact', 'Contact'), nodeSummaryDto('account', 'Account')],
            edges: [{ edgeKey: 'e1', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'contact', targetNodeKey: 'account' }],
            frontier: [],
            hasMore: false,
            nextCursor: null
        });
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'contact' } }));
        await flushPromises();

        element.shadowRoot.querySelector('c-oi-filter-panel').dispatchEvent(new CustomEvent('directiontoggle', { detail: { showParents: false, showChildren: false } }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-oi-graph-canvas').nodes).toHaveLength(2, 'both directions unchecked at once must be ignored, not applied.');
        expect(element.shadowRoot.querySelector('c-oi-filter-panel').direction).toBe('both');
    });

    it('checking "Direct relationships only" hides a grandparent that is only reachable two hops out', async () => {
        getPresentationRegistry.mockResolvedValue({
            nodeTypes: [],
            edgeTypes: [{ typeKey: 'SalesforceMetadata.LOOKUP_TO', displayLabel: 'Lookup To', lineStyle: 'dashed' }]
        });
        getGraphFragment.mockResolvedValueOnce({
            centerNodeKey: 'contact',
            nodes: [nodeSummaryDto('contact', 'Contact'), nodeSummaryDto('account', 'Account'), nodeSummaryDto('parentAccount', 'Parent Account')],
            edges: [
                { edgeKey: 'e1', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'contact', targetNodeKey: 'account' },
                { edgeKey: 'e2', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'account', targetNodeKey: 'parentAccount' }
            ],
            frontier: [],
            hasMore: false,
            nextCursor: null
        });
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'contact' } }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-oi-graph-canvas').nodes).toHaveLength(3);

        element.shadowRoot.querySelector('c-oi-filter-panel').dispatchEvent(new CustomEvent('depthtoggle', { detail: { restrictToDirectOnly: true } }));
        await flushPromises();

        const canvasNodeKeys = element.shadowRoot.querySelector('c-oi-graph-canvas').nodes.map((n) => n.nodeKey).sort();
        expect(canvasNodeKeys).toEqual(['account', 'contact']);
    });

    it('selecting a new center resets the relationship filter back to its unrestricted default', async () => {
        getPresentationRegistry.mockResolvedValue({
            nodeTypes: [],
            edgeTypes: [{ typeKey: 'SalesforceMetadata.LOOKUP_TO', displayLabel: 'Lookup To', lineStyle: 'dashed' }]
        });
        getGraphFragment.mockResolvedValueOnce({
            centerNodeKey: 'contact',
            nodes: [nodeSummaryDto('contact', 'Contact'), nodeSummaryDto('account', 'Account')],
            edges: [{ edgeKey: 'e1', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'contact', targetNodeKey: 'account' }],
            frontier: [],
            hasMore: false,
            nextCursor: null
        });
        const element = createElement('c-oi-graph-explorer', { is: OiGraphExplorer });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'contact' } }));
        await flushPromises();

        element.shadowRoot.querySelector('c-oi-filter-panel').dispatchEvent(new CustomEvent('edgetypetoggle', { detail: { typeKey: 'SalesforceMetadata.LOOKUP_TO' } }));
        await flushPromises();
        expect(element.shadowRoot.querySelector('c-oi-filter-panel').edgeTypeOptions[0].isChecked).toBe(false);

        getGraphFragment.mockResolvedValueOnce({
            centerNodeKey: 'newRoot',
            nodes: [nodeSummaryDto('newRoot', 'New Root'), nodeSummaryDto('newChild', 'New Child')],
            edges: [{ edgeKey: 'e2', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'newRoot', targetNodeKey: 'newChild' }],
            frontier: [],
            hasMore: false,
            nextCursor: null
        });
        element.shadowRoot.querySelector('c-oi-search-bar').dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'newRoot' } }));
        await flushPromises();

        // The same typeKey the prior view had hidden must come back checked (visible) on the new center — a fresh center is a fresh filter, not a carried-over one.
        expect(element.shadowRoot.querySelector('c-oi-filter-panel').edgeTypeOptions[0].isChecked).toBe(true);
        expect(element.shadowRoot.querySelector('c-oi-graph-canvas').nodes).toHaveLength(2);
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
