import { createElement } from 'lwc';
import OiNodeDetailPanel from 'c/oiNodeDetailPanel';
import getNodeDetail from '@salesforce/apex/OI_GraphController.getNodeDetail';
import getFieldSummaries from '@salesforce/apex/OI_GraphController.getFieldSummaries';
import getRecordFragment from '@salesforce/apex/OI_RecordHierarchyController.getRecordFragment';
import getImpact from '@salesforce/apex/OI_DependencyController.getImpact';

jest.mock('@salesforce/apex/OI_GraphController.getNodeDetail', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_GraphController.getFieldSummaries', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_RecordHierarchyController.getRecordFragment', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_DependencyController.getImpact', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function objectDetail(overrides) {
    return {
        nodeKey: 'account',
        typeKey: 'SalesforceMetadata.CustomObject',
        label: 'Account',
        secondaryKey: 'Account',
        attributes: { custom: false },
        outgoingRelationshipCounts: { 'SalesforceMetadata.HAS_FIELD': 2 },
        incomingRelationshipCounts: {},
        directConnectionCount: 2,
        ...overrides
    };
}

describe('c-oi-node-detail-panel', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        getNodeDetail.mockReset();
        getFieldSummaries.mockReset();
        getRecordFragment.mockReset();
        getImpact.mockReset();
    });

    it('shows the placeholder state when no node is selected', () => {
        const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
        document.body.appendChild(element);
        return Promise.resolve().then(() => {
            expect(element.shadowRoot.querySelector('[data-id="detail-placeholder"]')).not.toBeNull();
        });
    });

    it('re-fetches detail whenever nodeKey changes and renders the result generically', async () => {
        getNodeDetail.mockResolvedValue({
            nodeKey: 'n1',
            typeKey: 'SalesforceMetadata.CustomObject',
            label: 'Account',
            secondaryKey: 'Account',
            attributes: { custom: false, sharingModel: 'ReadWrite' }
        });
        const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
        document.body.appendChild(element);

        element.nodeKey = 'n1';
        await flushPromises();

        expect(getNodeDetail).toHaveBeenCalledWith({ nodeKey: 'n1' });
        const content = element.shadowRoot.querySelector('[data-id="detail-content"]');
        expect(content).not.toBeNull();
        expect(content.textContent).toContain('Account');
    });

    it('a Record Analysis node key (ADR-0021) resolves via getRecordFragment instead of the metadata getNodeDetail, and renders a structured Record Overview (object + Record Id, never a metadata "API Name" row)', async () => {
        getRecordFragment.mockResolvedValue({
            centerNodeKey: 'Record::Account::001x1',
            nodes: [{ nodeKey: 'Record::Account::001x1', typeKey: 'SalesforceRecord.Account', label: 'Acme Corp', secondaryKey: 'Account 001x1', state: 'Active' }],
            edges: [],
            hasMore: false
        });
        const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
        document.body.appendChild(element);

        element.nodeKey = 'Record::Account::001x1';
        await flushPromises();

        expect(getRecordFragment).toHaveBeenCalledWith({ objectApiName: 'Account', recordId: '001x1' });
        expect(getNodeDetail).not.toHaveBeenCalled();
        const content = element.shadowRoot.querySelector('[data-id="detail-content"]');
        expect(content).not.toBeNull();
        expect(content.textContent).toContain('Acme Corp');
        expect(content.textContent).toContain('Account');
        expect(content.textContent).toContain('001x1');
        expect(content.textContent).not.toContain('API Name');
    });

    it('derives a real Record Hierarchy section — parent lookups and child records grouped by object — directly from the SAME fragment\'s own edges, never a second query or fabricated data', async () => {
        getRecordFragment.mockResolvedValue({
            centerNodeKey: 'Record::Account::001x1',
            nodes: [
                { nodeKey: 'Record::Account::001x1', typeKey: 'SalesforceRecord.Account', label: 'Acme Corp', secondaryKey: 'Account 001x1', state: 'Active' },
                { nodeKey: 'Record::User::005x1', typeKey: 'SalesforceRecord.User', label: 'Jane Admin', secondaryKey: 'User 005x1', state: 'Active' },
                { nodeKey: 'Record::Contact::003x1', typeKey: 'SalesforceRecord.Contact', label: 'John Doe', secondaryKey: 'Contact 003x1', state: 'Active' },
                { nodeKey: 'Record::Contact::003x2', typeKey: 'SalesforceRecord.Contact', label: 'Jane Roe', secondaryKey: 'Contact 003x2', state: 'Active' },
                { nodeKey: 'Record::Opportunity::006x1', typeKey: 'SalesforceRecord.Opportunity', label: 'Big Deal', secondaryKey: 'Opportunity 006x1', state: 'Active' }
            ],
            edges: [
                { edgeKey: 'e1', typeKey: 'SalesforceRecord.LOOKUP_TO', sourceNodeKey: 'Record::Account::001x1', targetNodeKey: 'Record::User::005x1' },
                { edgeKey: 'e2', typeKey: 'SalesforceRecord.CHILD_OF', sourceNodeKey: 'Record::Account::001x1', targetNodeKey: 'Record::Contact::003x1' },
                { edgeKey: 'e3', typeKey: 'SalesforceRecord.CHILD_OF', sourceNodeKey: 'Record::Account::001x1', targetNodeKey: 'Record::Contact::003x2' },
                { edgeKey: 'e4', typeKey: 'SalesforceRecord.CHILD_OF', sourceNodeKey: 'Record::Account::001x1', targetNodeKey: 'Record::Opportunity::006x1' }
            ],
            hasMore: true
        });
        const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
        document.body.appendChild(element);

        element.nodeKey = 'Record::Account::001x1';
        await flushPromises();

        const hierarchy = element.shadowRoot.querySelector('[data-id="record-hierarchy"]');
        expect(hierarchy).not.toBeNull();
        expect(hierarchy.textContent).toContain('User');
        expect(hierarchy.textContent).toContain('Jane Admin');
        expect(hierarchy.textContent).toContain('Contact');
        expect(hierarchy.textContent).toContain('Opportunity');
        // Two Contact children collapse into one grouped row with count 2 — not two flat rows.
        const contactRow = Array.from(hierarchy.querySelectorAll('tr')).find((tr) => tr.textContent.includes('Contact') && !tr.textContent.includes('Jane') && !tr.textContent.includes('John'));
        expect(contactRow.textContent).toContain('2');
        expect(element.shadowRoot.querySelector('[data-id="record-has-more-note"]')).not.toBeNull();
    });

    it('does not render a Hierarchy section for a record with no parent lookups or children (an isolated/root record)', async () => {
        getRecordFragment.mockResolvedValue({
            centerNodeKey: 'Record::Account::001x1',
            nodes: [{ nodeKey: 'Record::Account::001x1', typeKey: 'SalesforceRecord.Account', label: 'Acme Corp', secondaryKey: 'Account 001x1', state: 'Active' }],
            edges: [],
            hasMore: false
        });
        const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
        document.body.appendChild(element);

        element.nodeKey = 'Record::Account::001x1';
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="record-hierarchy"]')).toBeNull();
    });

    it('a Record Analysis node no longer present in its own fragment renders an honest error, not a crash', async () => {
        getRecordFragment.mockResolvedValue({ centerNodeKey: null, nodes: [], edges: [], hasMore: false });
        const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
        document.body.appendChild(element);

        element.nodeKey = 'Record::Account::001x1';
        await flushPromises();

        const errorEl = element.shadowRoot.querySelector('[data-id="detail-error"]');
        expect(errorEl).not.toBeNull();
        expect(errorEl.textContent).toContain('No record found');
    });

    it('renders curated Object fields — Namespace, Custom/Standard — and the honest structural-connections summary, never claiming Apex/Flow/Trigger impact (G6/G7)', async () => {
        getNodeDetail.mockResolvedValue({
            nodeKey: 'acct',
            typeKey: 'SalesforceMetadata.CustomObject',
            label: 'Account',
            secondaryKey: 'Account',
            attributes: { custom: false, namespace: null, label: 'Account', pluralLabel: 'Accounts' },
            outgoingRelationshipCounts: { 'SalesforceMetadata.HAS_FIELD': 5 },
            incomingRelationshipCounts: { 'SalesforceMetadata.LOOKUP_TO': 2 },
            directConnectionCount: 7
        });
        const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
        element.registry = {
            nodeTypes: new Map([['SalesforceMetadata.CustomObject', { displayLabel: 'Object' }]]),
            edgeTypes: new Map([
                ['SalesforceMetadata.HAS_FIELD', { displayLabel: 'Has Field' }],
                ['SalesforceMetadata.LOOKUP_TO', { displayLabel: 'Lookup To' }]
            ])
        };
        document.body.appendChild(element);

        element.nodeKey = 'acct';
        await flushPromises();

        const content = element.shadowRoot.querySelector('[data-id="detail-content"]');
        expect(content.textContent).toContain('Object');
        expect(content.textContent).toContain('Standard');
        expect(content.textContent).toContain('None (org-native)');

        const structural = element.shadowRoot.querySelector('[data-id="structural-connections"]');
        expect(structural).not.toBeNull();
        expect(structural.textContent).toContain('7 directly connected');
        expect(structural.textContent).toContain('Has Field');
        expect(structural.textContent).toContain('Lookup To');
        expect(structural.textContent).not.toContain('Impact Analysis');
        expect(structural.textContent).toContain('Apex');
        expect(structural.textContent).toContain('not yet available');

        const otherAttributes = element.shadowRoot.querySelector('[data-id="other-attributes"]');
        expect(otherAttributes.textContent).toContain('pluralLabel');
        expect(otherAttributes.textContent).not.toContain('custom');
    });

    it('renders curated Field fields — Data Type, Parent Object, Relationship Type derived from real outgoing edges — never guessed from attributes (G6)', async () => {
        getNodeDetail.mockResolvedValue({
            nodeKey: 'ownerIdField',
            typeKey: 'SalesforceMetadata.CustomField',
            label: 'Owner ID',
            secondaryKey: 'Account.OwnerId',
            attributes: { type: 'REFERENCE', referenceTo: ['User'], relationshipName: 'Owner', custom: false },
            outgoingRelationshipCounts: { 'SalesforceMetadata.LOOKUP_TO': 1 },
            incomingRelationshipCounts: { 'SalesforceMetadata.HAS_FIELD': 1 },
            directConnectionCount: 2
        });
        const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
        element.registry = {
            nodeTypes: new Map(),
            edgeTypes: new Map([['SalesforceMetadata.LOOKUP_TO', { displayLabel: 'Lookup To' }]])
        };
        document.body.appendChild(element);

        element.nodeKey = 'ownerIdField';
        await flushPromises();

        const content = element.shadowRoot.querySelector('[data-id="detail-content"]');
        expect(content.textContent).toContain('REFERENCE');
        expect(content.textContent).toContain('Account');
        expect(content.textContent).toContain('Lookup To');
        expect(content.textContent).toContain('User');
        expect(content.textContent).toContain('Owner');
    });

    it('renders a sanitized error state when the Apex call fails', async () => {
        getNodeDetail.mockRejectedValue({ body: { message: 'You don\'t have permission to view org graph data.' } });
        const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
        document.body.appendChild(element);

        element.nodeKey = 'n1';
        await flushPromises();

        const errorEl = element.shadowRoot.querySelector('[data-id="detail-error"]');
        expect(errorEl).not.toBeNull();
        expect(errorEl.textContent).toContain('permission');
    });

    describe('Fields section (Show All / Standard / Custom field browser)', () => {
        function fieldSummary(overrides) {
            return { nodeKey: 'f0', label: 'Field', apiName: 'Account.Field', dataType: 'STRING', isCustom: false, isRequired: false, referenceTo: null, ...overrides };
        }

        it('shows the free field count from relationship counts and a "Show Fields" trigger, without calling getFieldSummaries until asked', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);

            element.nodeKey = 'account';
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="fields-section"]').textContent).toContain('Fields (2)');
            expect(element.shadowRoot.querySelector('[data-id="show-fields-button"]')).not.toBeNull();
            expect(getFieldSummaries).not.toHaveBeenCalled();
        });

        it('does not render a Fields section at all for a non-Object node', async () => {
            getNodeDetail.mockResolvedValue({ nodeKey: 'f1', typeKey: 'SalesforceMetadata.CustomField', label: 'Some Field', secondaryKey: 'Account.Some_Field__c', attributes: {} });
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);

            element.nodeKey = 'f1';
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="fields-section"]')).toBeNull();
        });

        it('clicking "Show Fields" loads the full list and renders label/API name/type/Custom-or-Standard badge for each', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getFieldSummaries.mockResolvedValue([
                fieldSummary({ nodeKey: 'f1', label: 'Account Name', apiName: 'Account.Name', dataType: 'STRING', isCustom: false }),
                fieldSummary({ nodeKey: 'f2', label: 'Favorite Color', apiName: 'Account.Favorite_Color__c', dataType: 'PICKLIST', isCustom: true })
            ]);
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            element.shadowRoot.querySelector('[data-id="show-fields-button"]').click();
            await flushPromises();

            expect(getFieldSummaries).toHaveBeenCalledWith({ objectNodeKey: 'account' });
            const rows = element.shadowRoot.querySelectorAll('[data-id="field-row"]');
            expect(rows).toHaveLength(2);
            expect(element.shadowRoot.querySelector('[data-id="fields-table"]').textContent).toContain('Favorite Color');
            expect(element.shadowRoot.querySelector('[data-id="fields-table"]').textContent).toContain('PICKLIST');
            const badges = element.shadowRoot.querySelectorAll('[data-id="field-badge"]');
            const badgeLabels = Array.from(badges).map((b) => b.textContent);
            expect(badgeLabels).toContain('Custom');
            expect(badgeLabels).toContain('Standard');
        });

        it('clicking "Hide Fields" collapses the section without discarding the already-loaded list, and Show Fields reopens it instantly with no new Apex call', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getFieldSummaries.mockResolvedValue([fieldSummary({ nodeKey: 'f1', label: 'Account Name', apiName: 'Account.Name', dataType: 'STRING', isCustom: false })]);
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            element.shadowRoot.querySelector('[data-id="show-fields-button"]').click();
            await flushPromises();
            expect(element.shadowRoot.querySelector('[data-id="fields-table"]')).not.toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="hide-fields-button"]')).not.toBeNull();

            element.shadowRoot.querySelector('[data-id="hide-fields-button"]').click();
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="fields-table"]')).toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="hide-fields-button"]')).toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="show-fields-button"]')).not.toBeNull();

            element.shadowRoot.querySelector('[data-id="show-fields-button"]').click();
            await flushPromises();

            expect(getFieldSummaries).toHaveBeenCalledTimes(1);
            expect(element.shadowRoot.querySelector('[data-id="fields-table"]')).not.toBeNull();
        });

        it('the Standard/Custom filter buttons narrow the already-loaded list without calling getFieldSummaries again', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getFieldSummaries.mockResolvedValue([
                fieldSummary({ nodeKey: 'f1', label: 'Account Name', isCustom: false }),
                fieldSummary({ nodeKey: 'f2', label: 'Favorite Color', isCustom: true })
            ]);
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();
            element.shadowRoot.querySelector('[data-id="show-fields-button"]').click();
            await flushPromises();

            const customButton = Array.from(element.shadowRoot.querySelectorAll('[data-id="field-filter-button"]')).find((b) => b.dataset.filter === 'Custom');
            customButton.click();
            await flushPromises();

            expect(getFieldSummaries).toHaveBeenCalledTimes(1);
            const rows = element.shadowRoot.querySelectorAll('[data-id="field-row"]');
            expect(rows).toHaveLength(1);
            expect(rows[0].textContent).toContain('Favorite Color');
        });

        it('the search box filters by label or API name, client-side', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getFieldSummaries.mockResolvedValue([
                fieldSummary({ nodeKey: 'f1', label: 'Account Name', apiName: 'Account.Name' }),
                fieldSummary({ nodeKey: 'f2', label: 'Billing City', apiName: 'Account.BillingCity' })
            ]);
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();
            element.shadowRoot.querySelector('[data-id="show-fields-button"]').click();
            await flushPromises();

            const searchInput = element.shadowRoot.querySelector('[data-id="field-search-input"]');
            searchInput.value = 'billing';
            searchInput.dispatchEvent(new CustomEvent('input'));
            await flushPromises();

            const rows = element.shadowRoot.querySelectorAll('[data-id="field-row"]');
            expect(rows).toHaveLength(1);
            expect(rows[0].textContent).toContain('Billing City');
        });

        it('clicking a field row dispatches select with that field\'s nodeKey', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getFieldSummaries.mockResolvedValue([fieldSummary({ nodeKey: 'f1', label: 'Account Name' })]);
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();
            element.shadowRoot.querySelector('[data-id="show-fields-button"]').click();
            await flushPromises();

            const handler = jest.fn();
            element.addEventListener('select', handler);
            element.shadowRoot.querySelector('[data-id="field-row"]').click();
            await flushPromises();

            expect(handler).toHaveBeenCalledTimes(1);
            expect(handler.mock.calls[0][0].detail.nodeKey).toBe('f1');
        });

        it('selecting a new node resets the field browser back to its unloaded, unfiltered state', async () => {
            getNodeDetail.mockResolvedValueOnce(objectDetail()).mockResolvedValueOnce(objectDetail({ nodeKey: 'contact', label: 'Contact', secondaryKey: 'Contact' }));
            getFieldSummaries.mockResolvedValue([fieldSummary({ nodeKey: 'f1', label: 'Account Name' })]);
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();
            element.shadowRoot.querySelector('[data-id="show-fields-button"]').click();
            await flushPromises();
            expect(element.shadowRoot.querySelector('[data-id="fields-table"]')).not.toBeNull();

            element.nodeKey = 'contact';
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="fields-table"]')).toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="show-fields-button"]')).not.toBeNull();
        });

        it('renders a sanitized error when getFieldSummaries fails', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getFieldSummaries.mockRejectedValue({ body: { message: 'You don\'t have permission to view org graph data.' } });
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            element.shadowRoot.querySelector('[data-id="show-fields-button"]').click();
            await flushPromises();

            const fieldsError = element.shadowRoot.querySelector('[data-id="fields-error"]');
            expect(fieldsError).not.toBeNull();
            expect(fieldsError.textContent).toContain('permission');
        });

        it('an object with zero scanned fields shows an honest empty state, never a "Show Fields" button with nothing behind it', async () => {
            getNodeDetail.mockResolvedValue(objectDetail({ outgoingRelationshipCounts: {} }));
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="show-fields-button"]')).toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="fields-section"]').textContent).toContain('no scanned fields');
        });
    });

    describe('Impact Analysis (forward/reverse, "Highlight on Graph")', () => {
        function impactResult(overrides) {
            return {
                rootNodeKey: 'acct',
                direction: 'forward',
                depth: 3,
                subgraph: { centerNodeKey: 'acct', nodes: [{ nodeKey: 'acct', typeKey: 'SalesforceMetadata.CustomObject', label: 'Account', secondaryKey: 'Account', state: 'Active' }], edges: [], frontier: [], hasMore: false, nextCursor: null },
                affectedComponents: [{ nodeKey: 'util', typeKey: 'SalesforceMetadata.ApexClass', label: 'Utils', hopDistance: 1, isInCycle: false }],
                truncated: false,
                coverageCaveat: 'Impact Analysis currently covers Apex class-to-class references only.',
                ...overrides
            };
        }

        it('shows both Impact Analysis actions for a non-Apex node too — the feature is generic, never gated to a hardcoded node type', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="impact-forward-button"]')).not.toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="impact-reverse-button"]')).not.toBeNull();
            expect(getImpact).not.toHaveBeenCalled();
        });

        it('clicking "What does this depend on?" calls getImpact with direction forward and renders the coverage caveat plus affected components', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getImpact.mockResolvedValue(impactResult());
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            element.shadowRoot.querySelector('[data-id="impact-forward-button"]').click();
            await flushPromises();

            expect(getImpact).toHaveBeenCalledWith({ nodeKey: 'account', direction: 'forward', depth: null });
            expect(element.shadowRoot.querySelector('[data-id="impact-coverage-caveat"]').textContent).toContain('Impact Analysis currently covers');
            const rows = element.shadowRoot.querySelectorAll('[data-id="impact-row"]');
            expect(rows).toHaveLength(1);
            expect(rows[0].textContent).toContain('Utils');
        });

        /**
         * DE-14: an impact result can now legitimately mix metadata kinds (Apex classes,
         * triggers, Flows, permission sets — DE-8/DE-9/DE-11), whose consequences differ in
         * kind: an Apex class means code may break, a permission set means someone loses
         * ACCESS. The panel must lead with that composition and must never print a raw internal
         * typeKey at the user.
         */
        it('summarizes a mixed-metadata-type impact result by type and renders registry labels, never raw typeKeys (DE-14)', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getImpact.mockResolvedValue(
                impactResult({
                    affectedComponents: [
                        { nodeKey: 'u1', typeKey: 'SalesforceMetadata.ApexClass', label: 'Utils', hopDistance: 1, isInCycle: false },
                        { nodeKey: 'u2', typeKey: 'SalesforceMetadata.ApexClass', label: 'Helper', hopDistance: 1, isInCycle: false },
                        { nodeKey: 't1', typeKey: 'SalesforceMetadata.ApexTrigger', label: 'AccountTrigger', hopDistance: 1, isInCycle: false },
                        { nodeKey: 'p1', typeKey: 'SalesforceMetadata.PermissionSet', label: 'Sales_Access', hopDistance: 2, isInCycle: false }
                    ]
                })
            );
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            element.registry = {
                nodeTypes: new Map([
                    ['SalesforceMetadata.ApexClass', { displayLabel: 'Apex Class' }],
                    ['SalesforceMetadata.ApexTrigger', { displayLabel: 'Apex Trigger' }],
                    ['SalesforceMetadata.PermissionSet', { displayLabel: 'Permission Set' }]
                ]),
                edgeTypes: new Map()
            };
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            element.shadowRoot.querySelector('[data-id="impact-forward-button"]').click();
            await flushPromises();

            const breakdown = element.shadowRoot.querySelector('[data-id="impact-type-breakdown"]');
            expect(breakdown).not.toBeNull();
            expect(breakdown.textContent).toContain('2 Apex Classes');
            expect(breakdown.textContent).toContain('1 Apex Trigger');
            expect(breakdown.textContent).toContain('1 Permission Set');

            const tableText = element.shadowRoot.querySelector('[data-id="impact-table"]').textContent;
            expect(tableText).toContain('Permission Set');
            expect(tableText).not.toContain('SalesforceMetadata.');
        });

        /** With only one type present the breakdown would merely restate the table's uniform Type column — suppressed rather than shown as a single redundant chip. */
        it('suppresses the type breakdown when every affected component is the same metadata type', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getImpact.mockResolvedValue(impactResult());
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            element.shadowRoot.querySelector('[data-id="impact-forward-button"]').click();
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="impact-type-breakdown"]')).toBeNull();
            expect(element.shadowRoot.querySelectorAll('[data-id="impact-row"]')).toHaveLength(1);
        });

        it('clicking "What depends on this?" calls getImpact with direction reverse', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getImpact.mockResolvedValue(impactResult({ direction: 'reverse' }));
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            element.shadowRoot.querySelector('[data-id="impact-reverse-button"]').click();
            await flushPromises();

            expect(getImpact).toHaveBeenCalledWith({ nodeKey: 'account', direction: 'reverse', depth: null });
        });

        it('a component flagged isInCycle renders a Cycle badge', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getImpact.mockResolvedValue(
                impactResult({ affectedComponents: [{ nodeKey: 'a', typeKey: 'SalesforceMetadata.ApexClass', label: 'A', hopDistance: 1, isInCycle: true }] })
            );
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            element.shadowRoot.querySelector('[data-id="impact-forward-button"]').click();
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="impact-cycle-badge"]')).not.toBeNull();
        });

        it('an empty affectedComponents list renders an honest empty state, not a blank table', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getImpact.mockResolvedValue(impactResult({ affectedComponents: [] }));
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            element.shadowRoot.querySelector('[data-id="impact-forward-button"]').click();
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="impact-empty"]')).not.toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="impact-table"]')).toBeNull();
        });

        it('renders a sanitized error when getImpact fails', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getImpact.mockRejectedValue({ body: { message: 'You don\'t have permission to view org graph data.' } });
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            element.shadowRoot.querySelector('[data-id="impact-forward-button"]').click();
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="impact-error"]').textContent).toContain('permission');
        });

        it('clicking "Highlight on Graph" dispatches highlightimpact with the root nodeKey and the fetched subgraph, unchanged', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            const result = impactResult();
            getImpact.mockResolvedValue(result);
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();
            element.shadowRoot.querySelector('[data-id="impact-forward-button"]').click();
            await flushPromises();

            const handler = jest.fn();
            element.addEventListener('highlightimpact', handler);
            element.shadowRoot.querySelector('[data-id="impact-highlight-button"]').click();

            expect(handler).toHaveBeenCalledTimes(1);
            expect(handler.mock.calls[0][0].detail.nodeKey).toBe('acct');
            expect(handler.mock.calls[0][0].detail.fragment).toBe(result.subgraph);
        });

        it('clicking an affected-component row dispatches select with that component\'s nodeKey, exactly like a field row', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getImpact.mockResolvedValue(impactResult());
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();
            element.shadowRoot.querySelector('[data-id="impact-forward-button"]').click();
            await flushPromises();

            const handler = jest.fn();
            element.addEventListener('select', handler);
            element.shadowRoot.querySelector('[data-id="impact-row"]').click();

            expect(handler).toHaveBeenCalledTimes(1);
            expect(handler.mock.calls[0][0].detail.nodeKey).toBe('util');
        });

        it('selecting a new node resets the Impact Analysis section back to its unloaded state', async () => {
            getNodeDetail.mockResolvedValueOnce(objectDetail()).mockResolvedValueOnce(objectDetail({ nodeKey: 'contact', label: 'Contact', secondaryKey: 'Contact' }));
            getImpact.mockResolvedValue(impactResult());
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();
            element.shadowRoot.querySelector('[data-id="impact-forward-button"]').click();
            await flushPromises();
            expect(element.shadowRoot.querySelector('[data-id="impact-coverage-caveat"]')).not.toBeNull();

            element.nodeKey = 'contact';
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="impact-coverage-caveat"]')).toBeNull();
        });
    });
});
