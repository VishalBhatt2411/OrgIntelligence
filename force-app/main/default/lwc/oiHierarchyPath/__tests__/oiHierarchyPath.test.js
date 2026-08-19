import { createElement } from 'lwc';
import OiHierarchyPath from 'c/oiHierarchyPath';
import getPath from '@salesforce/apex/OI_HierarchyQueryController.getPath';

jest.mock('@salesforce/apex/OI_HierarchyQueryController.getPath', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function setAllProps(element, { definitionId = 'def1', objectApiName = 'Account', recordId = '001x3' } = {}) {
    element.definitionId = definitionId;
    element.objectApiName = objectApiName;
    element.recordId = recordId;
}

describe('c-oi-hierarchy-path', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    beforeEach(() => {
        getPath.mockReset();
    });

    it('renders a root-first trail plus a non-clickable current-record crumb derived from the last entry\'s own resolved childLabel', async () => {
        getPath.mockResolvedValue([
            { relationshipId: 'r1', parentRecordId: '001x1', parentObjectApiName: 'Account', parentLabel: 'Global Enterprise', childRecordId: '001x2', childObjectApiName: 'Account', childLabel: 'North America' },
            { relationshipId: 'r2', parentRecordId: '001x2', parentObjectApiName: 'Account', parentLabel: 'North America', childRecordId: '001x3', childObjectApiName: 'Account', childLabel: 'ABC Motors' }
        ]);
        const element = createElement('c-oi-hierarchy-path', { is: OiHierarchyPath });
        setAllProps(element);
        document.body.appendChild(element);
        await flushPromises();

        const crumbs = element.shadowRoot.querySelectorAll('[data-id="path-crumb"]');
        expect(crumbs).toHaveLength(2);
        expect(crumbs[0].textContent.trim()).toBe('Global Enterprise');
        expect(crumbs[1].textContent.trim()).toBe('North America');
        const current = element.shadowRoot.querySelector('[data-id="path-crumb-current"]');
        expect(current.textContent.trim()).toBe('ABC Motors');
    });

    it('does not call Apex until definitionId, objectApiName, and recordId are all set', async () => {
        const element = createElement('c-oi-hierarchy-path', { is: OiHierarchyPath });
        element.definitionId = 'def1';
        document.body.appendChild(element);
        await flushPromises();

        expect(getPath).not.toHaveBeenCalled();
    });

    it('re-fetches when recordId changes on the same instance (e.g. Record Page navigation)', async () => {
        getPath.mockResolvedValue([]);
        const element = createElement('c-oi-hierarchy-path', { is: OiHierarchyPath });
        setAllProps(element, { recordId: '001x3' });
        document.body.appendChild(element);
        await flushPromises();

        element.recordId = '001x9';
        await flushPromises();

        expect(getPath).toHaveBeenCalledTimes(2);
        expect(getPath).toHaveBeenLastCalledWith({ definitionId: 'def1', childObjectApiName: 'Account', childRecordId: '001x9' });
    });

    it('reports a root-level record honestly instead of fabricating a current-record label', async () => {
        getPath.mockResolvedValue([]);
        const element = createElement('c-oi-hierarchy-path', { is: OiHierarchyPath });
        setAllProps(element);
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="path-root-note"]')).not.toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="path-crumb-current"]')).toBeNull();
    });

    it('uses the supplied currentRecordLabel for a root-level record when the caller provides one', async () => {
        getPath.mockResolvedValue([]);
        const element = createElement('c-oi-hierarchy-path', { is: OiHierarchyPath });
        element.currentRecordLabel = 'Global Enterprise';
        setAllProps(element);
        document.body.appendChild(element);
        await flushPromises();

        const current = element.shadowRoot.querySelector('[data-id="path-crumb-current"]');
        expect(current.textContent.trim()).toBe('Global Enterprise');
    });

    it('dispatches recordselect with the clicked ancestor\'s objectApiName/recordId, never navigating on its own', async () => {
        getPath.mockResolvedValue([
            { relationshipId: 'r1', parentRecordId: '001x1', parentObjectApiName: 'Account', parentLabel: 'Global Enterprise', childRecordId: '001x3', childObjectApiName: 'Account', childLabel: 'ABC Motors' }
        ]);
        const element = createElement('c-oi-hierarchy-path', { is: OiHierarchyPath });
        setAllProps(element);
        const handler = jest.fn();
        element.addEventListener('recordselect', handler);
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="path-crumb"]').click();
        expect(handler).toHaveBeenCalledWith(expect.objectContaining({ detail: { objectApiName: 'Account', recordId: '001x1' } }));
    });

    it('broadcasts the current record\'s resolved label so a sibling component can reuse it without its own query', async () => {
        getPath.mockResolvedValue([
            { relationshipId: 'r1', parentRecordId: '001x1', parentObjectApiName: 'Account', parentLabel: 'Global Enterprise', childRecordId: '001x3', childObjectApiName: 'Account', childLabel: 'ABC Motors' }
        ]);
        const element = createElement('c-oi-hierarchy-path', { is: OiHierarchyPath });
        setAllProps(element);
        const handler = jest.fn();
        element.addEventListener('currentrecordlabel', handler);
        document.body.appendChild(element);
        await flushPromises();

        expect(handler).toHaveBeenCalledWith(expect.objectContaining({ detail: { label: 'ABC Motors' } }));
    });

    it('never broadcasts a label for a root-level record with nothing resolved to share', async () => {
        getPath.mockResolvedValue([]);
        const element = createElement('c-oi-hierarchy-path', { is: OiHierarchyPath });
        setAllProps(element);
        const handler = jest.fn();
        element.addEventListener('currentrecordlabel', handler);
        document.body.appendChild(element);
        await flushPromises();

        expect(handler).not.toHaveBeenCalled();
    });

    it('surfaces an Apex failure as a visible error', async () => {
        getPath.mockRejectedValue({ body: { message: 'Unknown hierarchy definition.' } });
        const element = createElement('c-oi-hierarchy-path', { is: OiHierarchyPath });
        setAllProps(element);
        document.body.appendChild(element);
        await flushPromises();

        const error = element.shadowRoot.querySelector('[data-id="path-error"]');
        expect(error.textContent).toBe('Unknown hierarchy definition.');
    });
});
