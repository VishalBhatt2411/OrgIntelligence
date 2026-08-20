import { createElement } from 'lwc';
import OiIntelligenceDrilldown from 'c/oiIntelligenceDrilldown';
import getNodeConnections from '@salesforce/apex/OI_GraphController.getNodeConnections';
import getNavigationTarget from '@salesforce/apex/OI_GraphController.getNavigationTarget';
import { navigateToTarget } from 'c/metadataNavigation';

jest.mock('@salesforce/apex/OI_GraphController.getNodeConnections', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_GraphController.getNavigationTarget', () => ({ default: jest.fn() }), { virtual: true });
jest.mock(
    'c/metadataNavigation',
    () => ({
        navigateToTarget: jest.fn(() => ({ navigated: true, message: null })),
        isNavigable: jest.fn(() => true)
    }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function row(overrides) {
    return {
        nodeKey: 'field1',
        label: 'Owner ID',
        apiName: 'Account.OwnerId',
        typeKey: 'SalesforceMetadata.CustomField',
        typeLabel: 'Field',
        relationshipLabel: 'Has Field',
        roleLabel: 'Field Of',
        direction: 'outgoing',
        dataType: 'REFERENCE',
        referencedObject: 'User',
        isCustom: false,
        ...overrides
    };
}

function page(overrides) {
    return {
        rows: [row()],
        totalCount: 1,
        hasMore: false,
        nextCursor: null,
        isFiltered: false,
        unavailableReason: null,
        ...overrides
    };
}

describe('c-oi-intelligence-drilldown', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        getNodeConnections.mockReset();
        getNavigationTarget.mockReset();
        navigateToTarget.mockClear();
        jest.useRealTimers();
    });

    function createDrilldown(props) {
        const element = createElement('c-oi-intelligence-drilldown', { is: OiIntelligenceDrilldown });
        element.nodeKey = 'account';
        element.direction = 'outgoing';
        element.edgeTypeKey = 'SalesforceMetadata.HAS_FIELD';
        element.anchorLabel = 'Account';
        element.relationshipLabel = 'Has Field';
        Object.assign(element, props || {});
        document.body.appendChild(element);
        return element;
    }

    it('loads and renders the first page on connect, with an accurate header and result count', async () => {
        getNodeConnections.mockResolvedValue(page());
        const element = createDrilldown();
        await flushPromises();

        expect(getNodeConnections).toHaveBeenCalledWith({
            nodeKey: 'account',
            direction: 'outgoing',
            edgeTypeKey: 'SalesforceMetadata.HAS_FIELD',
            pageSize: 100,
            cursor: null,
            searchTerm: null
        });
        expect(element.shadowRoot.querySelector('[data-id="drilldown-title"]').textContent).toBe('Account');
        expect(element.shadowRoot.querySelector('[data-id="drilldown-count"]').textContent).toContain('1 result');
        expect(element.shadowRoot.querySelectorAll('[data-id="drilldown-row"]')).toHaveLength(1);
    });

    /** Every row must render as real, structured columns — never a raw dump — and must never leak the internal typeKey as a user-visible label. */
    it('renders a structured row with resolved labels and never a raw SalesforceMetadata.* typeKey', async () => {
        getNodeConnections.mockResolvedValue(page());
        const element = createDrilldown();
        await flushPromises();

        const tableText = element.shadowRoot.querySelector('[data-id="drilldown-table"]').textContent;
        expect(tableText).toContain('Owner ID');
        expect(tableText).toContain('Account.OwnerId');
        expect(tableText).toContain('Field Of');
        expect(tableText).not.toContain('SalesforceMetadata.');
    });

    it('shows a loading state while the first page is in flight', async () => {
        let resolvePromise;
        getNodeConnections.mockReturnValue(
            new Promise((resolve) => {
                resolvePromise = resolve;
            })
        );
        const element = createDrilldown();
        await Promise.resolve();

        expect(element.shadowRoot.querySelector('[data-id="drilldown-loading"]')).not.toBeNull();

        resolvePromise(page());
        await flushPromises();
        expect(element.shadowRoot.querySelector('[data-id="drilldown-loading"]')).toBeNull();
    });

    it('renders a sanitized error state when the fetch fails', async () => {
        getNodeConnections.mockRejectedValue({ body: { message: 'You do not have permission to view org graph data.' } });
        const element = createDrilldown();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="drilldown-error"]').textContent).toContain('permission');
    });

    it('renders an honest empty state distinct from an error, when there are genuinely no results', async () => {
        getNodeConnections.mockResolvedValue(page({ rows: [], totalCount: 0 }));
        const element = createDrilldown();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="drilldown-empty"]')).not.toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="drilldown-error"]')).toBeNull();
    });

    /** A category the current scan coverage cannot answer must say so plainly, never render as a bare empty table indistinguishable from "genuinely zero". */
    it('renders the unavailable reason instead of an empty table when the category is unsupported', async () => {
        getNodeConnections.mockResolvedValue(page({ rows: [], totalCount: 0, unavailableReason: 'Field-level grants are not scanned yet.' }));
        const element = createDrilldown();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="drilldown-unavailable"]').textContent).toBe('Field-level grants are not scanned yet.');
        expect(element.shadowRoot.querySelector('[data-id="drilldown-table"]')).toBeNull();
    });

    it('debounces search input and re-queries the server with the term, restarting pagination', async () => {
        /** Fake timers only wrap the debounce itself — flushPromises() below relies on a REAL setTimeout(0) to drain microtasks, which never fires under fake timers. Switching back immediately after advancing keeps the two from fighting each other. */
        getNodeConnections.mockResolvedValue(page());
        const element = createDrilldown();
        await flushPromises();
        getNodeConnections.mockClear();
        getNodeConnections.mockResolvedValue(page({ rows: [row({ label: 'Owner' })], totalCount: 1, isFiltered: true }));

        jest.useFakeTimers();
        const searchInput = element.shadowRoot.querySelector('[data-id="drilldown-search"]');
        searchInput.value = 'Owner';
        searchInput.dispatchEvent(new CustomEvent('change'));
        jest.advanceTimersByTime(300);
        jest.useRealTimers();
        await flushPromises();

        expect(getNodeConnections).toHaveBeenCalledWith(expect.objectContaining({ searchTerm: 'Owner', cursor: null }));
        expect(element.shadowRoot.querySelector('[data-id="drilldown-count"]').textContent).toContain('matching');
    });

    it('sorts loaded rows client-side by name ascending by default, then toggles to descending on a repeat click of the same column', async () => {
        getNodeConnections.mockResolvedValue(
            page({
                rows: [row({ nodeKey: 'b', label: 'Bravo' }), row({ nodeKey: 'a', label: 'Alpha' })],
                totalCount: 2
            })
        );
        const element = createDrilldown();
        await flushPromises();

        /** Default sort is ascending by name — the rows arrived Bravo-then-Alpha but must render Alpha-first with no click needed. */
        let rows = element.shadowRoot.querySelectorAll('[data-id="drilldown-row"]');
        expect(rows[0].textContent).toContain('Alpha');

        /** Clicking the already-active sort column toggles direction, not "sets" ascending again. */
        element.shadowRoot.querySelector('[data-id="sort-label"]').click();
        await flushPromises();
        rows = element.shadowRoot.querySelectorAll('[data-id="drilldown-row"]');
        expect(rows[0].textContent).toContain('Bravo');

        element.shadowRoot.querySelector('[data-id="sort-label"]').click();
        await flushPromises();
        rows = element.shadowRoot.querySelectorAll('[data-id="drilldown-row"]');
        expect(rows[0].textContent).toContain('Alpha');
    });

    it('loads the next page on "Load more" and appends without duplicating rows', async () => {
        getNodeConnections.mockResolvedValueOnce(page({ rows: [row({ nodeKey: 'a' })], totalCount: 2, hasMore: true, nextCursor: 'cursor-1' }));
        const element = createDrilldown();
        await flushPromises();
        expect(element.shadowRoot.querySelector('[data-id="drilldown-load-more"]')).not.toBeNull();

        getNodeConnections.mockResolvedValueOnce(page({ rows: [row({ nodeKey: 'b' })], totalCount: 2, hasMore: false, nextCursor: null }));
        element.shadowRoot.querySelector('[data-id="drilldown-load-more"]').click();
        await flushPromises();

        expect(getNodeConnections).toHaveBeenLastCalledWith(expect.objectContaining({ cursor: 'cursor-1' }));
        expect(element.shadowRoot.querySelectorAll('[data-id="drilldown-row"]')).toHaveLength(2);
        expect(element.shadowRoot.querySelector('[data-id="drilldown-load-more"]')).toBeNull();
    });

    it('resolves navigation and opens the target when "Open in Setup" is clicked', async () => {
        getNodeConnections.mockResolvedValue(page());
        getNavigationTarget.mockResolvedValue({ kind: 'setupPage', url: '/lightning/setup/ObjectManager/Account/FieldsAndRelationships/Owner/view' });
        const element = createDrilldown();
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="drilldown-open"]').click();
        await flushPromises();

        expect(getNavigationTarget).toHaveBeenCalledWith({ typeKey: 'SalesforceMetadata.CustomField', apiName: 'Account.OwnerId' });
        expect(navigateToTarget).toHaveBeenCalled();
    });

    /** An unsupported destination must say so rather than silently doing nothing — a dead click with no feedback reads as broken. */
    it('surfaces an honest message when a row cannot be opened directly', async () => {
        getNodeConnections.mockResolvedValue(page());
        getNavigationTarget.mockResolvedValue({ kind: 'unsupported', reason: 'This component cannot be opened directly.' });
        navigateToTarget.mockReturnValueOnce({ navigated: false, message: 'This component cannot be opened directly.' });
        const element = createDrilldown();
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="drilldown-open"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="drilldown-action-message"]').textContent).toBe('This component cannot be opened directly.');
    });

    it('dispatches nodeselect with the row\'s node key when "Show on graph" is clicked', async () => {
        getNodeConnections.mockResolvedValue(page());
        const element = createDrilldown();
        await flushPromises();
        const handler = jest.fn();
        element.addEventListener('nodeselect', handler);

        element.shadowRoot.querySelector('[data-id="drilldown-select"]').click();

        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail.nodeKey).toBe('field1');
    });

    it('dispatches close when the close button is clicked', async () => {
        getNodeConnections.mockResolvedValue(page());
        const element = createDrilldown();
        await flushPromises();
        const handler = jest.fn();
        element.addEventListener('close', handler);

        element.shadowRoot.querySelector('[data-id="drilldown-close"]').click();

        expect(handler).toHaveBeenCalledTimes(1);
    });

    it('dispatches close on Escape for keyboard users', async () => {
        getNodeConnections.mockResolvedValue(page());
        const element = createDrilldown();
        await flushPromises();
        const handler = jest.fn();
        element.addEventListener('close', handler);

        element.shadowRoot.querySelector('[data-id="drilldown"]').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));

        expect(handler).toHaveBeenCalledTimes(1);
    });
});
