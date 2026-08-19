import { createElement } from 'lwc';
import OiHierarchyTree from 'c/oiHierarchyTree';
import getDescendants from '@salesforce/apex/OI_HierarchyQueryController.getDescendants';

jest.mock('@salesforce/apex/OI_HierarchyQueryController.getDescendants', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function setAllProps(element, { definitionId = 'def1', rootObjectApiName = 'Account', rootRecordId = '001x1' } = {}) {
    element.definitionId = definitionId;
    element.rootObjectApiName = rootObjectApiName;
    element.rootRecordId = rootRecordId;
}

describe('c-oi-hierarchy-tree', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    beforeEach(() => {
        getDescendants.mockReset();
    });

    it('builds a parent-to-children adjacency map from the flat relationship list and renders the root node', async () => {
        getDescendants.mockResolvedValue({
            descendants: [
                { relationshipId: 'r1', parentRecordId: '001x1', parentObjectApiName: 'Account', parentLabel: 'Global Enterprise', childRecordId: '001x2', childObjectApiName: 'Account', childLabel: 'North America' },
                { relationshipId: 'r2', parentRecordId: '001x1', parentObjectApiName: 'Account', parentLabel: 'Global Enterprise', childRecordId: '001x3', childObjectApiName: 'Account', childLabel: 'EMEA' }
            ],
            hasMore: false
        });
        const element = createElement('c-oi-hierarchy-tree', { is: OiHierarchyTree });
        element.rootLabel = 'Global Enterprise';
        setAllProps(element);
        document.body.appendChild(element);
        await flushPromises();

        const root = element.shadowRoot.querySelector('[data-id="tree-root"]');
        expect(root).not.toBeNull();
        expect(root.nodeLabel).toBe('Global Enterprise');
        expect(root.childrenByParentId.get('001x1')).toHaveLength(2);
    });

    it('does not call Apex until definitionId, rootObjectApiName, and rootRecordId are all set', async () => {
        const element = createElement('c-oi-hierarchy-tree', { is: OiHierarchyTree });
        element.definitionId = 'def1';
        document.body.appendChild(element);
        await flushPromises();

        expect(getDescendants).not.toHaveBeenCalled();
    });

    it('shows the hasMore note honestly instead of silently truncating', async () => {
        getDescendants.mockResolvedValue({ descendants: [], hasMore: true });
        const element = createElement('c-oi-hierarchy-tree', { is: OiHierarchyTree });
        setAllProps(element);
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="tree-has-more-note"]')).not.toBeNull();
    });

    it('re-emits recordselect bubbled up from the tree node as its own recordselect', async () => {
        getDescendants.mockResolvedValue({
            descendants: [{ relationshipId: 'r1', parentRecordId: '001x1', parentObjectApiName: 'Account', parentLabel: 'Global Enterprise', childRecordId: '001x2', childObjectApiName: 'Account', childLabel: 'North America' }],
            hasMore: false
        });
        const element = createElement('c-oi-hierarchy-tree', { is: OiHierarchyTree });
        setAllProps(element);
        const handler = jest.fn();
        element.addEventListener('recordselect', handler);
        document.body.appendChild(element);
        await flushPromises();

        const root = element.shadowRoot.querySelector('[data-id="tree-root"]');
        root.shadowRoot.querySelector('[data-id="tree-node-toggle"]').click();
        await flushPromises();
        root.shadowRoot.querySelector('c-oi-hierarchy-tree-node').shadowRoot.querySelector('[data-id="tree-node-label"]').click();

        expect(handler).toHaveBeenCalledWith(expect.objectContaining({ detail: { objectApiName: 'Account', recordId: '001x2' } }));
    });

    it('surfaces an Apex failure as a visible error', async () => {
        getDescendants.mockRejectedValue({ body: { message: 'Unknown hierarchy definition.' } });
        const element = createElement('c-oi-hierarchy-tree', { is: OiHierarchyTree });
        setAllProps(element);
        document.body.appendChild(element);
        await flushPromises();

        const error = element.shadowRoot.querySelector('[data-id="tree-error"]');
        expect(error.textContent).toBe('Unknown hierarchy definition.');
    });
});
