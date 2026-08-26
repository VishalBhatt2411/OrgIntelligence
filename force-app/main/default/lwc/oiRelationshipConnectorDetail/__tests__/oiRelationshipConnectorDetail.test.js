import { createElement } from 'lwc';
import OiRelationshipConnectorDetail from 'c/oiRelationshipConnectorDetail';
import getNavigationTarget from '@salesforce/apex/OI_GraphController.getNavigationTarget';
import { navigateToTarget } from 'c/metadataNavigation';

jest.mock('@salesforce/apex/OI_GraphController.getNavigationTarget', () => ({ default: jest.fn() }), { virtual: true });
jest.mock(
    'c/metadataNavigation',
    () => ({
        navigateToTarget: jest.fn(() => ({ navigated: true, message: null })),
        isNavigable: jest.fn(() => true),
        NAVIGATION_KIND_RECORD: 'record'
    }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function rootObject() {
    return { nodeKey: 'account', label: 'Account', secondaryKey: 'Account', iconName: 'standard:account', colorToken: 'neutral', isCustom: false };
}

function outgoingConnector() {
    return {
        connectorKey: 'outgoing::user',
        counterpartObject: { nodeKey: 'user', label: 'User', secondaryKey: 'User', iconName: 'standard:user', colorToken: 'neutral', isCustom: false },
        direction: 'outgoing',
        fields: [
            { fieldNodeKey: 'accountManagerId', fieldSecondaryKey: 'Account.AccountManagerId', fieldApiName: 'AccountManagerId', relationshipType: 'Lookup', isSystemRelationship: false },
            { fieldNodeKey: 'regionalDirectorId', fieldSecondaryKey: 'Account.RegionalDirectorId', fieldApiName: 'RegionalDirectorId', relationshipType: 'Lookup', isSystemRelationship: false }
        ],
        relationshipCount: 2,
        primaryRelationshipType: 'Lookup',
        isSystemRelationship: false
    };
}

function incomingConnector() {
    return {
        connectorKey: 'incoming::opportunity',
        counterpartObject: { nodeKey: 'opportunity', label: 'Opportunity', secondaryKey: 'Opportunity', iconName: 'standard:opportunity', colorToken: 'neutral', isCustom: false },
        direction: 'incoming',
        fields: [{ fieldNodeKey: 'accountId', fieldSecondaryKey: 'Opportunity.AccountId', fieldApiName: 'AccountId', relationshipType: 'MasterDetail', isSystemRelationship: false }],
        relationshipCount: 1,
        primaryRelationshipType: 'MasterDetail',
        isSystemRelationship: false
    };
}

function renderDetail(connector, { mode, rootObjectOverride } = {}) {
    const element = createElement('c-oi-relationship-connector-detail', { is: OiRelationshipConnectorDetail });
    element.connector = connector;
    element.rootObject = rootObjectOverride || rootObject();
    if (mode) {
        element.mode = mode;
    }
    document.body.appendChild(element);
    return element;
}

function recordRootObject() {
    return { nodeKey: 'Record::Account::001x1', label: 'Acme Corp', secondaryKey: 'Account', objectApiName: 'Account', recordId: '001x1', iconName: 'standard:record', colorToken: 'neutral', isCustom: false };
}

function recordOutgoingConnector() {
    return {
        connectorKey: 'outgoing::Record::User::005x1',
        counterpartObject: { nodeKey: 'Record::User::005x1', label: 'Jane Admin', secondaryKey: 'User', objectApiName: 'User', recordId: '005x1', iconName: 'standard:user', colorToken: 'neutral', isCustom: false },
        direction: 'outgoing',
        fields: [],
        relationshipCount: 1,
        primaryRelationshipType: 'Lookup',
        relationshipTypeLabel: 'Related Record',
        isSystemRelationship: false
    };
}

describe('c-oi-relationship-connector-detail', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        getNavigationTarget.mockReset();
        navigateToTarget.mockClear();
    });

    it('renders source object, relationship type, target object, and direction for an outgoing connector', () => {
        const element = renderDetail(outgoingConnector());
        expect(element.shadowRoot.querySelector('[data-id="open-source"]').textContent).toBe('Account');
        expect(element.shadowRoot.querySelector('[data-id="connector-detail-type"]').textContent).toBe('Lookup');
        expect(element.shadowRoot.querySelector('[data-id="open-target"]').textContent).toBe('User');
        expect(element.shadowRoot.querySelector('[data-id="connector-detail-direction"]').textContent).toBe('Account → User');
    });

    it('resolves source/target correctly for an incoming connector (counterpart is the source, center is the target)', () => {
        const element = renderDetail(incomingConnector());
        expect(element.shadowRoot.querySelector('[data-id="open-source"]').textContent).toBe('Opportunity');
        expect(element.shadowRoot.querySelector('[data-id="open-target"]').textContent).toBe('Account');
        expect(element.shadowRoot.querySelector('[data-id="connector-detail-type"]').textContent).toBe('Master-Detail');
    });

    it('lists every aggregated field with its own relationship type', () => {
        const element = renderDetail(outgoingConnector());
        const fieldList = element.shadowRoot.querySelector('[data-id="connector-detail-fields"]');
        expect(fieldList.textContent).toContain('AccountManagerId');
        expect(fieldList.textContent).toContain('RegionalDirectorId');
    });

    it('opens the target object via getNavigationTarget + metadataNavigation when "Open Target Object" is clicked', async () => {
        getNavigationTarget.mockResolvedValue({ kind: 'record', recordId: '001x1', objectApiName: 'Object' });
        const element = renderDetail(outgoingConnector());

        element.shadowRoot.querySelector('[data-id="open-target"]').click();
        await flushPromises();

        expect(getNavigationTarget).toHaveBeenCalledWith({ typeKey: 'SalesforceMetadata.CustomObject', apiName: 'User' });
        expect(navigateToTarget).toHaveBeenCalled();
    });

    it('opens an individual field via getNavigationTarget using its fully-qualified API name', async () => {
        getNavigationTarget.mockResolvedValue({ kind: 'setupPage', url: '/lightning/setup/x' });
        const element = renderDetail(outgoingConnector());

        const fieldButtons = element.shadowRoot.querySelectorAll('[data-id="connector-detail-fields"] button');
        fieldButtons[0].click();
        await flushPromises();

        expect(getNavigationTarget).toHaveBeenCalledWith({ typeKey: 'SalesforceMetadata.CustomField', apiName: 'Account.AccountManagerId' });
    });

    it('surfaces an honest message when navigation is unsupported, rather than a dead click', async () => {
        getNavigationTarget.mockResolvedValue({ kind: 'unsupported', reason: 'This component cannot be opened directly.' });
        navigateToTarget.mockReturnValueOnce({ navigated: false, message: 'This component cannot be opened directly.' });
        const element = renderDetail(outgoingConnector());

        element.shadowRoot.querySelector('[data-id="open-target"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="connector-detail-action-message"]').textContent).toContain('cannot be opened directly');
    });

    it('emits close when the close button is clicked', () => {
        const element = renderDetail(outgoingConnector());
        const handler = jest.fn();
        element.addEventListener('close', handler);

        element.shadowRoot.querySelector('[data-id="connector-detail-close"]').click();
        expect(handler).toHaveBeenCalledTimes(1);
    });

    it('emits close on Escape, the minimum keyboard-user affordance for any modal', () => {
        const element = renderDetail(outgoingConnector());
        const handler = jest.fn();
        element.addEventListener('close', handler);

        element.shadowRoot.querySelector('[data-id="connector-detail"]').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
        expect(handler).toHaveBeenCalledTimes(1);
    });

    it('renders the backdrop as a sibling behind the dialog, never as a child that can cover the modal content', () => {
        const element = renderDetail(outgoingConnector());
        const dialog = element.shadowRoot.querySelector('[data-id="connector-detail"]');
        const backdrop = element.shadowRoot.querySelector('[data-id="connector-detail-backdrop"]');

        expect(backdrop).not.toBeNull();
        expect(dialog.contains(backdrop)).toBe(false);
        expect(dialog.parentElement).toBe(backdrop.parentElement);
    });

    describe('Record mode (ADR-0024)', () => {
        it('labels Source/Target as Record rather than Object, and shows the fieldless relationship type plainly without appending "Relationship" again', () => {
            const element = renderDetail(recordOutgoingConnector(), { mode: 'Record', rootObjectOverride: recordRootObject() });

            const dtLabels = [...element.shadowRoot.querySelectorAll('.oi-rcd-detail-list dt')].map((el) => el.textContent);
            expect(dtLabels).toContain('Source Record');
            expect(dtLabels).toContain('Target Record');
            expect(element.shadowRoot.querySelector('[data-id="connector-detail-type"]').textContent).toBe('Related Record');
            expect(element.shadowRoot.querySelector('[data-id="connector-detail-subtitle"]').textContent).toBe('Related Record');
        });

        it('omits the Fields section entirely — a record connector has no fields[] to browse', () => {
            const element = renderDetail(recordOutgoingConnector(), { mode: 'Record', rootObjectOverride: recordRootObject() });
            expect(element.shadowRoot.querySelector('[data-id="connector-detail-fields"]')).toBeNull();
        });

        it('opens a record via a client-side standard__recordPage navigation target, never calling getNavigationTarget (records are live data, not metadata)', async () => {
            const element = renderDetail(recordOutgoingConnector(), { mode: 'Record', rootObjectOverride: recordRootObject() });

            element.shadowRoot.querySelector('[data-id="open-target"]').click();
            await flushPromises();

            expect(getNavigationTarget).not.toHaveBeenCalled();
            expect(navigateToTarget).toHaveBeenCalledWith(expect.anything(), { kind: 'record', recordId: '005x1', objectApiName: 'User' });
        });

        it('surfaces an honest message when the record could not be identified, rather than a dead click', async () => {
            const connector = recordOutgoingConnector();
            connector.counterpartObject.recordId = null;
            const element = renderDetail(connector, { mode: 'Record', rootObjectOverride: recordRootObject() });

            element.shadowRoot.querySelector('[data-id="open-target"]').click();
            await flushPromises();

            expect(navigateToTarget).not.toHaveBeenCalled();
            expect(element.shadowRoot.querySelector('[data-id="connector-detail-action-message"]').textContent).toContain('could not be identified');
        });
    });
});
