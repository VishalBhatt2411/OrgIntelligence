import { createElement } from 'lwc';
import OiHierarchySwitcher from 'c/oiHierarchySwitcher';
import getDefinitions from '@salesforce/apex/OI_HierarchyDefinitionController.getDefinitions';

jest.mock('@salesforce/apex/OI_HierarchyDefinitionController.getDefinitions', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const DEFINITIONS = [
    { definitionId: 'def1', name: 'Corporate Hierarchy', objectApiName: 'Account', status: 'Active' },
    { definitionId: 'def2', name: 'Territory Hierarchy', objectApiName: 'Account', status: 'Active' },
    { definitionId: 'def3', name: 'Retired Hierarchy', objectApiName: 'Account', status: 'Inactive' },
    { definitionId: 'def4', name: 'Contact Hierarchy', objectApiName: 'Contact', status: 'Active' }
];

describe('c-oi-hierarchy-switcher', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    beforeEach(() => {
        getDefinitions.mockReset();
    });

    it('narrows to only Active definitions scoped to the given objectApiName and auto-selects the first one', async () => {
        getDefinitions.mockResolvedValue(DEFINITIONS);
        const element = createElement('c-oi-hierarchy-switcher', { is: OiHierarchySwitcher });
        element.objectApiName = 'Account';
        const handler = jest.fn();
        element.addEventListener('definitionchange', handler);
        document.body.appendChild(element);
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('[data-id="switcher-combobox"]');
        expect(combobox.options).toHaveLength(2);
        expect(combobox.options.map((o) => o.value)).toEqual(['def1', 'def2']);
        expect(handler).toHaveBeenCalledWith(expect.objectContaining({ detail: { definitionId: 'def1' } }));
    });

    it('shows an honest empty state when no Active definition applies to the object, never a broken dropdown', async () => {
        getDefinitions.mockResolvedValue(DEFINITIONS);
        const element = createElement('c-oi-hierarchy-switcher', { is: OiHierarchySwitcher });
        element.objectApiName = 'Opportunity';
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="switcher-empty"]')).not.toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="switcher-combobox"]')).toBeNull();
    });

    it('re-derives the selection when objectApiName changes to a different object on the same instance', async () => {
        getDefinitions.mockResolvedValue(DEFINITIONS);
        const element = createElement('c-oi-hierarchy-switcher', { is: OiHierarchySwitcher });
        element.objectApiName = 'Account';
        document.body.appendChild(element);
        await flushPromises();

        const handler = jest.fn();
        element.addEventListener('definitionchange', handler);
        element.objectApiName = 'Contact';
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('[data-id="switcher-combobox"]');
        expect(combobox.options.map((o) => o.value)).toEqual(['def4']);
        expect(handler).toHaveBeenCalledWith(expect.objectContaining({ detail: { definitionId: 'def4' } }));
    });

    it('surfaces an Apex failure as a visible error, never a silently empty dropdown', async () => {
        getDefinitions.mockRejectedValue({ body: { message: 'Access denied.' } });
        const element = createElement('c-oi-hierarchy-switcher', { is: OiHierarchySwitcher });
        element.objectApiName = 'Account';
        document.body.appendChild(element);
        await flushPromises();

        const error = element.shadowRoot.querySelector('[data-id="switcher-error"]');
        expect(error).not.toBeNull();
        expect(error.textContent).toBe('Access denied.');
    });
});
