import { createElement } from 'lwc';
import OiHierarchyTreeNode from 'c/oiHierarchyTreeNode';

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function buildChildrenMap() {
    const map = new Map();
    map.set('root1', [
        { recordId: 'child1', objectApiName: 'Account', label: 'North America' },
        { recordId: 'child2', objectApiName: 'Account', label: 'EMEA' }
    ]);
    map.set('child1', [{ recordId: 'grandchild1', objectApiName: 'Account', label: 'USA' }]);
    return map;
}

describe('c-oi-hierarchy-tree-node', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders no toggle and no children list for a leaf node', () => {
        const element = createElement('c-oi-hierarchy-tree-node', { is: OiHierarchyTreeNode });
        element.nodeRecordId = 'grandchild1';
        element.nodeObjectApiName = 'Account';
        element.nodeLabel = 'USA';
        element.childrenByParentId = buildChildrenMap();
        document.body.appendChild(element);

        expect(element.shadowRoot.querySelector('[data-id="tree-node-toggle"]')).toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="tree-node-children"]')).toBeNull();
    });

    it('starts collapsed and reveals children only after the toggle is clicked', async () => {
        const element = createElement('c-oi-hierarchy-tree-node', { is: OiHierarchyTreeNode });
        element.nodeRecordId = 'root1';
        element.nodeObjectApiName = 'Account';
        element.nodeLabel = 'Global Enterprise';
        element.childrenByParentId = buildChildrenMap();
        document.body.appendChild(element);

        expect(element.shadowRoot.querySelector('[data-id="tree-node-children"]')).toBeNull();

        element.shadowRoot.querySelector('[data-id="tree-node-toggle"]').click();
        await flushPromises();

        const childrenList = element.shadowRoot.querySelector('[data-id="tree-node-children"]');
        expect(childrenList).not.toBeNull();
        const childNodes = element.shadowRoot.querySelectorAll('c-oi-hierarchy-tree-node');
        expect(childNodes).toHaveLength(2);
    });

    it('renders the root\'s own label as plain, non-clickable text — never a self-navigating link', () => {
        const element = createElement('c-oi-hierarchy-tree-node', { is: OiHierarchyTreeNode });
        element.nodeRecordId = 'root1';
        element.nodeObjectApiName = 'Account';
        element.nodeLabel = 'Global Enterprise';
        element.childrenByParentId = buildChildrenMap();
        element.isRoot = true;
        document.body.appendChild(element);

        expect(element.shadowRoot.querySelector('[data-id="tree-node-label"]')).toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="tree-node-label-current"]').textContent).toBe('Global Enterprise');
    });

    it('dispatches recordselect when a non-root label is clicked', () => {
        const element = createElement('c-oi-hierarchy-tree-node', { is: OiHierarchyTreeNode });
        element.nodeRecordId = 'child1';
        element.nodeObjectApiName = 'Account';
        element.nodeLabel = 'North America';
        element.childrenByParentId = buildChildrenMap();
        const handler = jest.fn();
        element.addEventListener('recordselect', handler);
        document.body.appendChild(element);

        element.shadowRoot.querySelector('[data-id="tree-node-label"]').click();

        expect(handler).toHaveBeenCalledWith(expect.objectContaining({ detail: { objectApiName: 'Account', recordId: 'child1' } }));
    });

    it('relays a grandchild\'s recordselect upward through the intermediate node unchanged', async () => {
        const element = createElement('c-oi-hierarchy-tree-node', { is: OiHierarchyTreeNode });
        element.nodeRecordId = 'root1';
        element.nodeObjectApiName = 'Account';
        element.nodeLabel = 'Global Enterprise';
        element.childrenByParentId = buildChildrenMap();
        element.isRoot = true;
        const handler = jest.fn();
        element.addEventListener('recordselect', handler);
        document.body.appendChild(element);

        element.shadowRoot.querySelector('[data-id="tree-node-toggle"]').click();
        await flushPromises();

        const firstChildNode = element.shadowRoot.querySelector('c-oi-hierarchy-tree-node');
        firstChildNode.shadowRoot.querySelector('[data-id="tree-node-toggle"]').click();
        await flushPromises();

        const grandchildLabel = firstChildNode.shadowRoot.querySelector('c-oi-hierarchy-tree-node').shadowRoot.querySelector('[data-id="tree-node-label"]');
        grandchildLabel.click();

        expect(handler).toHaveBeenCalledWith(expect.objectContaining({ detail: { objectApiName: 'Account', recordId: 'grandchild1' } }));
    });
});
