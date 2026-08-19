import { createElement } from 'lwc';
import OiHierarchyViewer from 'c/oiHierarchyViewer';

const mockNavigate = jest.fn();

// The shipped sfdx-lwc-jest stub for lightning/navigation is a bare no-op with nothing to
// assert against, so this test file supplies its own — the [Navigate] method it defines
// forwards to mockNavigate, since the LWC compiler freezes component/mixin prototypes, making
// any post-hoc jest.spyOn on either the mixin's own method or the component's own methods
// throw ("Cannot assign to read only property").
jest.mock('lightning/navigation', () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
        class extends Base {
            [Navigate](...args) {
                mockNavigate(...args);
            }
        };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin };
});

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-oi-hierarchy-viewer', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        mockNavigate.mockClear();
    });

    function createViewer() {
        const element = createElement('c-oi-hierarchy-viewer', { is: OiHierarchyViewer });
        element.recordId = '001x1';
        element.objectApiName = 'Account';
        document.body.appendChild(element);
        return element;
    }

    it('does not render Path/Tree until oiHierarchySwitcher reports a definitionId', async () => {
        const element = createViewer();
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-oi-hierarchy-path')).toBeNull();
        expect(element.shadowRoot.querySelector('c-oi-hierarchy-tree')).toBeNull();
    });

    it('wires the switcher\'s definitionId into both Path and Tree once resolved', async () => {
        const element = createViewer();
        await flushPromises();

        const switcher = element.shadowRoot.querySelector('c-oi-hierarchy-switcher');
        switcher.dispatchEvent(new CustomEvent('definitionchange', { detail: { definitionId: 'def1' } }));
        await flushPromises();

        const path = element.shadowRoot.querySelector('c-oi-hierarchy-path');
        const tree = element.shadowRoot.querySelector('c-oi-hierarchy-tree');
        expect(path.definitionId).toBe('def1');
        expect(path.recordId).toBe('001x1');
        expect(tree.definitionId).toBe('def1');
        expect(tree.rootRecordId).toBe('001x1');
    });

    it('forwards the Path\'s free currentrecordlabel broadcast into the Tree\'s rootLabel, without a second query', async () => {
        const element = createViewer();
        await flushPromises();
        element.shadowRoot.querySelector('c-oi-hierarchy-switcher').dispatchEvent(new CustomEvent('definitionchange', { detail: { definitionId: 'def1' } }));
        await flushPromises();

        element.shadowRoot.querySelector('c-oi-hierarchy-path').dispatchEvent(new CustomEvent('currentrecordlabel', { detail: { label: 'ABC Motors' } }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-oi-hierarchy-tree').rootLabel).toBe('ABC Motors');
    });

    it('navigates to the selected record when a recordselect bubbles up from the Path or Tree', async () => {
        const element = createViewer();
        await flushPromises();
        element.shadowRoot.querySelector('c-oi-hierarchy-switcher').dispatchEvent(new CustomEvent('definitionchange', { detail: { definitionId: 'def1' } }));
        await flushPromises();

        element.shadowRoot.querySelector('c-oi-hierarchy-path').dispatchEvent(new CustomEvent('recordselect', { detail: { objectApiName: 'Account', recordId: '001x9' } }));

        expect(mockNavigate).toHaveBeenCalledWith({
            type: 'standard__recordPage',
            attributes: { recordId: '001x9', objectApiName: 'Account', actionName: 'view' }
        });
    });

    it('never navigates when the selected record is already the one being viewed', async () => {
        const element = createViewer();
        await flushPromises();
        element.shadowRoot.querySelector('c-oi-hierarchy-switcher').dispatchEvent(new CustomEvent('definitionchange', { detail: { definitionId: 'def1' } }));
        await flushPromises();

        element.shadowRoot.querySelector('c-oi-hierarchy-path').dispatchEvent(new CustomEvent('recordselect', { detail: { objectApiName: 'Account', recordId: '001x1' } }));

        expect(mockNavigate).not.toHaveBeenCalled();
    });
});
