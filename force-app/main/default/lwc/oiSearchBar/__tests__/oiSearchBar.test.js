import { createElement } from 'lwc';
import OiSearchBar from 'c/oiSearchBar';
import search from '@salesforce/apex/OI_SearchController.search';

jest.mock('@salesforce/apex/OI_SearchController.search', () => ({ default: jest.fn() }), { virtual: true });

function wait(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

describe('c-oi-search-bar', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    beforeEach(() => {
        search.mockReset();
    });

    it('debounces input and calls OI_SearchController.search with the typed term', async () => {
        search.mockResolvedValue([{ nodeKey: 'n1', typeKey: 'T', label: 'Account', secondaryKey: 'Account', state: 'Active' }]);
        const element = createElement('c-oi-search-bar', { is: OiSearchBar });
        document.body.appendChild(element);

        const input = element.shadowRoot.querySelector('lightning-input');
        input.value = 'Acc';
        input.dispatchEvent(new CustomEvent('change'));

        await wait(400);

        expect(search).toHaveBeenCalledWith({ queryTerm: 'Acc' });
    });

    it("renders results and dispatches select with the clicked result's nodeKey, then clears the result list but keeps the selected label visible in the box", async () => {
        search.mockResolvedValue([{ nodeKey: 'n1', typeKey: 'SalesforceMetadata.CustomObject', label: 'Account', secondaryKey: 'Account', state: 'Active' }]);
        const element = createElement('c-oi-search-bar', { is: OiSearchBar });
        document.body.appendChild(element);
        const handler = jest.fn();
        element.addEventListener('select', handler);

        const input = element.shadowRoot.querySelector('lightning-input');
        input.value = 'Acc';
        input.dispatchEvent(new CustomEvent('change'));
        await wait(400);

        const resultButton = element.shadowRoot.querySelector('[data-id="search-result-item"]');
        expect(resultButton).not.toBeNull();
        resultButton.click();

        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail.nodeKey).toBe('n1');

        return Promise.resolve().then(() => {
            expect(element.shadowRoot.querySelector('[data-id="search-results"]')).toBeNull();
            expect(element.shadowRoot.querySelector('lightning-input').value).toBe('Account');
        });
    });

    it('pressing Enter with suggestions already showing selects the top one, standard combobox behavior', async () => {
        search.mockResolvedValue([
            { nodeKey: 'n1', typeKey: 'SalesforceMetadata.CustomObject', label: 'Account', secondaryKey: 'Account', state: 'Active' },
            { nodeKey: 'n2', typeKey: 'SalesforceMetadata.CustomObject', label: 'AccountShare', secondaryKey: 'AccountShare', state: 'Active' }
        ]);
        const element = createElement('c-oi-search-bar', { is: OiSearchBar });
        document.body.appendChild(element);
        const handler = jest.fn();
        element.addEventListener('select', handler);

        const input = element.shadowRoot.querySelector('lightning-input');
        input.value = 'Acc';
        input.dispatchEvent(new CustomEvent('change'));
        await wait(400);

        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }));

        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail.nodeKey).toBe('n1');
    });

    it('pressing Enter with no suggestions showing yet runs the search immediately, without waiting for the debounce', async () => {
        search.mockResolvedValue([{ nodeKey: 'n1', typeKey: 'T', label: 'Account', secondaryKey: 'Account', state: 'Active' }]);
        const element = createElement('c-oi-search-bar', { is: OiSearchBar });
        document.body.appendChild(element);

        const input = element.shadowRoot.querySelector('lightning-input');
        input.value = 'Acc';
        input.dispatchEvent(new CustomEvent('change'));

        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }));
        await Promise.resolve();
        await Promise.resolve();

        expect(search).toHaveBeenCalledWith({ queryTerm: 'Acc' });
    });

    it('never calls search for a blank query', async () => {
        const element = createElement('c-oi-search-bar', { is: OiSearchBar });
        document.body.appendChild(element);
        const input = element.shadowRoot.querySelector('lightning-input');
        input.value = '   ';
        input.dispatchEvent(new CustomEvent('change'));
        await wait(400);
        expect(search).not.toHaveBeenCalled();
    });

    it('typeKeyFilter scopes results client-side to the current Analyze mode (G3/G8)', async () => {
        search.mockResolvedValue([
            { nodeKey: 'n1', typeKey: 'SalesforceMetadata.CustomObject', label: 'Account', secondaryKey: 'Account', state: 'Active' },
            { nodeKey: 'n2', typeKey: 'SalesforceMetadata.CustomField', label: 'Account.OwnerId', secondaryKey: 'Account.OwnerId', state: 'Active' }
        ]);
        const element = createElement('c-oi-search-bar', { is: OiSearchBar });
        element.typeKeyFilter = 'SalesforceMetadata.CustomObject';
        document.body.appendChild(element);

        const input = element.shadowRoot.querySelector('lightning-input');
        input.value = 'Acc';
        input.dispatchEvent(new CustomEvent('change'));
        await wait(400);

        const results = element.shadowRoot.querySelectorAll('[data-id="search-result-item"]');
        expect(results).toHaveLength(1);
        expect(results[0].dataset.nodeKey).toBe('n1');
    });

    it('resolves a raw typeKey to the registry display label instead of showing it verbatim (G3)', async () => {
        search.mockResolvedValue([{ nodeKey: 'n1', typeKey: 'SalesforceMetadata.CustomObject', label: 'Account', secondaryKey: 'Account', state: 'Active' }]);
        const element = createElement('c-oi-search-bar', { is: OiSearchBar });
        element.registry = { nodeTypes: new Map([['SalesforceMetadata.CustomObject', { displayLabel: 'Object' }]]), edgeTypes: new Map() };
        document.body.appendChild(element);

        const input = element.shadowRoot.querySelector('lightning-input');
        input.value = 'Acc';
        input.dispatchEvent(new CustomEvent('change'));
        await wait(400);

        const typeSpan = element.shadowRoot.querySelector('.oi-search-bar-result-type');
        expect(typeSpan.textContent).toBe('Object');
    });

    it('the Search button triggers search immediately, without waiting for the debounce', async () => {
        search.mockResolvedValue([{ nodeKey: 'n1', typeKey: 'T', label: 'Account', secondaryKey: 'Account', state: 'Active' }]);
        const element = createElement('c-oi-search-bar', { is: OiSearchBar });
        document.body.appendChild(element);

        const input = element.shadowRoot.querySelector('lightning-input');
        input.value = 'Acc';
        input.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot.querySelector('[data-id="search-button"]').click();
        await Promise.resolve();
        await Promise.resolve();

        expect(search).toHaveBeenCalledWith({ queryTerm: 'Acc' });
    });

    it('shows a loading spinner while the search is in flight', async () => {
        let resolveSearch;
        search.mockReturnValue(new Promise((resolve) => { resolveSearch = resolve; }));
        const element = createElement('c-oi-search-bar', { is: OiSearchBar });
        document.body.appendChild(element);

        const input = element.shadowRoot.querySelector('lightning-input');
        input.value = 'Acc';
        input.dispatchEvent(new CustomEvent('change'));
        await wait(400);

        expect(element.shadowRoot.querySelector('[data-id="search-loading"]')).not.toBeNull();

        resolveSearch([]);
        await Promise.resolve();
        await Promise.resolve();
    });

    it('renders a sanitized error banner when the search call fails, instead of failing silently', async () => {
        search.mockRejectedValue({ body: { message: 'You don\'t have permission to view org graph data.' } });
        const element = createElement('c-oi-search-bar', { is: OiSearchBar });
        document.body.appendChild(element);

        const input = element.shadowRoot.querySelector('lightning-input');
        input.value = 'Acc';
        input.dispatchEvent(new CustomEvent('change'));
        await wait(400);

        const errorEl = element.shadowRoot.querySelector('[data-id="search-error"]');
        expect(errorEl).not.toBeNull();
        expect(errorEl.textContent).toContain('permission');
        expect(element.shadowRoot.querySelector('[data-id="search-results"]')).toBeNull();
    });
});
