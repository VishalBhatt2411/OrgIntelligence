import { createElement } from 'lwc';
import OiNodeDetailPanel from 'c/oiNodeDetailPanel';
import getNodeDetail from '@salesforce/apex/OI_GraphController.getNodeDetail';
import getFieldSummaries from '@salesforce/apex/OI_GraphController.getFieldSummaries';
import getRecordFragment from '@salesforce/apex/OI_RecordHierarchyController.getRecordFragment';
import getImpact from '@salesforce/apex/OI_DependencyController.getImpact';
import getNodeIntelligence from '@salesforce/apex/OI_GraphController.getNodeIntelligence';

jest.mock('@salesforce/apex/OI_GraphController.getNodeDetail', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_GraphController.getFieldSummaries', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_RecordHierarchyController.getRecordFragment', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_DependencyController.getImpact', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_GraphController.getNodeIntelligence', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

/**
 * Fields/Automation/Code/Security/Impact all start collapsed by default (DEFAULT_COLLAPSED_SECTIONS
 * in oiNodeDetailPanel.js) — this clicks the given section's header toggle (data-section="fields" /
 * "Automation" / "Code" / "Security" / "impact") and waits for the resulting re-render, so tests that
 * only care about a section's expanded content don't have to repeat the click/flush pair inline.
 */
async function expandSection(element, section) {
    element.shadowRoot.querySelector(`[data-section="${section}"]`).click();
    await flushPromises();
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
    beforeEach(() => {
        /** Intelligence loads automatically on selection, so every test needs it stubbed or the panel logs an unhandled rejection. Defaults to an empty-but-valid payload; tests that assert on sections override it. */
        getNodeIntelligence.mockResolvedValue({
            nodeKey: 'n1',
            categories: [],
            lastScannedAt: null,
            hasCoverageLimitations: false
        });
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        getNodeDetail.mockReset();
        getFieldSummaries.mockReset();
        getRecordFragment.mockReset();
        getImpact.mockReset();
        getNodeIntelligence.mockReset();
    });

    describe('Intelligence sections (Automation / Code / Security) and scan provenance', () => {
        function intelligence(overrides) {
            return {
                nodeKey: 'account',
                categories: [
                    {
                        category: 'Automation',
                        items: [{ nodeKey: 'trg1', label: 'AccountTrigger', typeKey: 'SalesforceMetadata.ApexTrigger', typeLabel: 'Apex Trigger', direction: 'incoming' }],
                        truncated: false,
                        coverageNote: 'Detected: the object each Apex trigger fires on.'
                    },
                    {
                        category: 'Code',
                        items: [],
                        truncated: false,
                        coverageNote: 'Detected: Apex references matched by name. Not detected: dynamic Apex.'
                    },
                    {
                        category: 'Security',
                        items: [{ nodeKey: 'ps1', label: 'Sales_Access', typeKey: 'SalesforceMetadata.PermissionSet', typeLabel: 'Permission Set', direction: 'incoming' }],
                        truncated: false,
                        coverageNote: 'Detected: object-level grants. Not detected: field-level grants.'
                    }
                ],
                lastScannedAt: '2026-08-19T12:22:11.000Z',
                hasCoverageLimitations: false,
                ...overrides
            };
        }

        it('renders Automation, Code and Security sections with real named components and their direction', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getNodeIntelligence.mockResolvedValue(intelligence());
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();
            await expandSection(element, 'Automation');
            await expandSection(element, 'Security');

            const sections = element.shadowRoot.querySelectorAll('[data-id="intelligence-section"]');
            expect(sections).toHaveLength(3);
            expect(sections[0].textContent).toContain('Automation');
            expect(sections[0].textContent).toContain('AccountTrigger');
            expect(sections[0].textContent).toContain('Apex Trigger');
            /** 'incoming' is internal vocabulary; the user must see what it MEANS. */
            expect(sections[0].textContent).toContain('uses this');
            expect(sections[2].textContent).toContain('Sales_Access');
        });

        /** An empty section must still render, with its coverage note available — otherwise a user cannot tell "no triggers exist" from "triggers are not detected". The note itself is collapsed by default (item 15) so it never dominates the panel; opening "Coverage details" reveals it. */
        it('renders an empty section with an honest, differentiated empty state (true zero, since this fixture is recently scanned with no coverage limitations) and an on-demand coverage note', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getNodeIntelligence.mockResolvedValue(intelligence());
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();
            await expandSection(element, 'Code');

            const codeSection = element.shadowRoot.querySelector('[data-category="Code"]');
            expect(codeSection).not.toBeNull();
            expect(codeSection.querySelector('[data-id="intelligence-empty"]').textContent).toContain('No code detected for this component.');
            expect(codeSection.querySelector('[data-id="intelligence-coverage"]')).toBeNull();

            codeSection.querySelector('[data-id="coverage-details-toggle"]').click();
            await flushPromises();
            expect(codeSection.querySelector('[data-id="intelligence-coverage"]').textContent).toContain('Not detected: dynamic Apex');
        });

        it('truncates a long namespaced Permission Set name to a single line with the full name available via title, instead of word-breaking across three lines (audit #11)', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getNodeIntelligence.mockResolvedValue(intelligence({
                categories: [
                    { category: 'Automation', items: [], truncated: false, coverageNote: 'n/a' },
                    { category: 'Code', items: [], truncated: false, coverageNote: 'n/a' },
                    {
                        category: 'Security',
                        items: [{ nodeKey: 'ps1', label: 'MuleSoftSeamlessLoginC2CPermSet', typeKey: 'SalesforceMetadata.PermissionSet', typeLabel: 'Permission Set', direction: 'incoming' }],
                        truncated: false,
                        coverageNote: 'n/a'
                    }
                ]
            }));
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();
            await expandSection(element, 'Security');

            const securitySection = element.shadowRoot.querySelector('[data-category="Security"]');
            const row = securitySection.querySelector('[data-id="intelligence-row"]');
            const labelCell = row.querySelector('td');
            expect(labelCell.getAttribute('title')).toBe('MuleSoftSeamlessLoginC2CPermSet');
            expect(labelCell.textContent).toBe('MuleSoftSeamlessLoginC2CPermSet');
        });

        it('never exposes a raw SalesforceMetadata.* typeKey as a user-facing label', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getNodeIntelligence.mockResolvedValue(intelligence());
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();
            await expandSection(element, 'Automation');
            await expandSection(element, 'Code');
            await expandSection(element, 'Security');

            const sectionText = [...element.shadowRoot.querySelectorAll('[data-id="intelligence-section"]')].map((s) => s.textContent).join(' ');
            expect(sectionText).not.toContain('SalesforceMetadata.');
        });

        it('shows when the intelligence was last scanned, since every number here comes from the persisted scan graph', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getNodeIntelligence.mockResolvedValue(intelligence());
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            const freshness = element.shadowRoot.querySelector('[data-id="scan-freshness"]');
            expect(freshness).not.toBeNull();
            expect(freshness.textContent).toContain('last scanned');
            expect(element.shadowRoot.querySelector('[data-id="coverage-limitations"]')).toBeNull();
        });

        /** Never-scanned must be stated explicitly — omitting the line would read as freshness. */
        it('states explicitly when the org has never been scanned rather than implying fresh data', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getNodeIntelligence.mockResolvedValue(intelligence({ lastScannedAt: null }));
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="scan-freshness"]').textContent).toContain('Never scanned');
        });

        it('warns when the last scan left dependency coverage incomplete', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getNodeIntelligence.mockResolvedValue(intelligence({ hasCoverageLimitations: true }));
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="coverage-limitations"]').textContent).toContain('not fully scanned');
        });

        it('surfaces a truncation notice rather than silently showing a partial list', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            const payload = intelligence();
            payload.categories[0].truncated = true;
            getNodeIntelligence.mockResolvedValue(payload);
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();
            await expandSection(element, 'Automation');

            expect(element.shadowRoot.querySelector('[data-id="intelligence-truncated"]')).not.toBeNull();
        });

        describe('empty-state differentiation (GraphUI.md §42, item 22) — never one undifferentiated "nothing found"', () => {
            it('an empty section on a never-scanned node reads as Unscanned, not a zero result', async () => {
                getNodeDetail.mockResolvedValue(objectDetail());
                const payload = intelligence({ lastScannedAt: null });
                payload.categories[1].items = [];
                getNodeIntelligence.mockResolvedValue(payload);
                const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
                document.body.appendChild(element);
                element.nodeKey = 'account';
                await flushPromises();
                await expandSection(element, 'Code');

                const codeSection = element.shadowRoot.querySelector('[data-category="Code"]');
                const empty = codeSection.querySelector('[data-id="intelligence-empty"]');
                expect(empty.textContent).toContain('has not been scanned yet');
                expect(empty.className).toContain('oi-node-detail-panel-empty-state-unscanned');
            });

            it('an empty section whose scan is older than 30 days reads as Stale, not a fresh zero result', async () => {
                getNodeDetail.mockResolvedValue(objectDetail());
                const payload = intelligence({ lastScannedAt: '2026-06-01T00:00:00.000Z' });
                payload.categories[1].items = [];
                getNodeIntelligence.mockResolvedValue(payload);
                const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
                document.body.appendChild(element);
                element.nodeKey = 'account';
                await flushPromises();
                await expandSection(element, 'Code');

                const codeSection = element.shadowRoot.querySelector('[data-category="Code"]');
                const empty = codeSection.querySelector('[data-id="intelligence-empty"]');
                expect(empty.textContent).toContain('older scan');
                expect(empty.className).toContain('oi-node-detail-panel-empty-state-stale');
            });

            it('an empty section on a recently-scanned node with no coverage limitations reads as a plain true zero', async () => {
                getNodeDetail.mockResolvedValue(objectDetail());
                getNodeIntelligence.mockResolvedValue(intelligence());
                const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
                document.body.appendChild(element);
                element.nodeKey = 'account';
                await flushPromises();
                await expandSection(element, 'Code');

                const codeSection = element.shadowRoot.querySelector('[data-category="Code"]');
                const empty = codeSection.querySelector('[data-id="intelligence-empty"]');
                expect(empty.className).toContain('oi-node-detail-panel-empty-state-zero');
                expect(empty.textContent).not.toContain('scanned yet');
                expect(empty.textContent).not.toContain('older scan');
            });

            it('an empty section flagged with coverage limitations reads as possibly incomplete, even on a fresh scan', async () => {
                getNodeDetail.mockResolvedValue(objectDetail());
                getNodeIntelligence.mockResolvedValue(intelligence({ hasCoverageLimitations: true }));
                const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
                document.body.appendChild(element);
                element.nodeKey = 'account';
                await flushPromises();
                await expandSection(element, 'Code');

                const codeSection = element.shadowRoot.querySelector('[data-category="Code"]');
                const empty = codeSection.querySelector('[data-id="intelligence-empty"]');
                expect(empty.className).toContain('oi-node-detail-panel-empty-state-incomplete');
                expect(empty.textContent).toContain('may be incomplete');
            });
        });

        it('collapses and re-expands an intelligence section on header click, without discarding its already-loaded data', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getNodeIntelligence.mockResolvedValue(intelligence());
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            const automationSection = element.shadowRoot.querySelector('[data-category="Automation"]');
            expect(automationSection.textContent).not.toContain('AccountTrigger');
            const toggle = automationSection.querySelector('[data-id="intelligence-section-toggle"]');
            expect(toggle.getAttribute('aria-expanded')).toBe('false');

            toggle.click();
            await flushPromises();
            expect(automationSection.textContent).toContain('AccountTrigger');
            expect(toggle.getAttribute('aria-expanded')).toBe('true');

            toggle.click();
            await flushPromises();
            expect(automationSection.textContent).not.toContain('AccountTrigger');
            expect(toggle.getAttribute('aria-expanded')).toBe('false');
        });

        it('selecting a related component dispatches select so the user can navigate to it', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getNodeIntelligence.mockResolvedValue(intelligence());
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();
            await expandSection(element, 'Automation');
            const handler = jest.fn();
            element.addEventListener('select', handler);

            element.shadowRoot.querySelector('[data-id="intelligence-row"]').click();

            expect(handler).toHaveBeenCalledTimes(1);
            expect(handler.mock.calls[0][0].detail.nodeKey).toBe('trg1');
        });

        it('renders a sanitized error when intelligence fails, without breaking the rest of the panel', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getNodeIntelligence.mockRejectedValue({ body: { message: 'You do not have permission to view org graph data.' } });
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="intelligence-error"]').textContent).toContain('permission');
            /** The rest of the panel must survive an intelligence failure — a failed section is not a failed panel. */
            expect(element.shadowRoot.querySelector('[data-id="detail-content"]')).not.toBeNull();
        });
    });

    describe('Technical Details (raw attributes moved out of the default experience)', () => {
        /** The exact raw keys that used to be dumped at users unprompted — the concrete thing this change moves out of the default view. */
        function detailWithRawAttributes() {
            return objectDetail({
                attributes: { custom: false, keyPrefix: '001', queryable: true, feedEnabled: false }
            });
        }

        it('collapses raw technical attributes by default so they no longer dominate the panel', async () => {
            getNodeDetail.mockResolvedValue(detailWithRawAttributes());
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="technical-details"]')).not.toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="technical-details-table"]')).toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="technical-details-toggle"]').textContent).toContain('Show technical details');
            /** The raw keys must not be visible anywhere in the panel until asked for. */
            expect(element.shadowRoot.textContent).not.toContain('keyPrefix');
        });

        /** The data must still be reachable — this was a presentation fix, never a deletion. */
        it('reveals the raw attributes on demand without losing any of them', async () => {
            getNodeDetail.mockResolvedValue(detailWithRawAttributes());
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            element.shadowRoot.querySelector('[data-id="technical-details-toggle"]').click();
            await flushPromises();

            const table = element.shadowRoot.querySelector('[data-id="technical-details-table"]');
            expect(table).not.toBeNull();
            expect(table.textContent).toContain('keyPrefix');
            expect(table.textContent).toContain('queryable');
            expect(element.shadowRoot.querySelector('[data-id="technical-details-toggle"]').textContent).toContain('Hide technical details');
        });
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

    it('renders curated Object fields — Namespace, Custom/Standard — and keeps the structural-connections summary scoped to schema relationships only (G6/G7)', async () => {
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
        expect(content.textContent).toContain('—');

        /**
         * Object mode gets the curated relationship breakdown (GraphUI.md §42, item 14): HAS_FIELD
         * is schema-membership information, not an object-to-object relationship, so it must never
         * appear here — it already powers the Fields section's own count instead. Only genuine
         * Lookup/Master-Detail metrics show, labeled plainly (Incoming Lookups/Incoming Master-
         * Detail/Outgoing Lookups/Outgoing Master-Detail), each a real count from the same
         * getNodeDetail response, never fabricated.
         */
        const structural = element.shadowRoot.querySelector('[data-id="structural-connections"]');
        expect(structural).not.toBeNull();
        expect(structural.textContent).not.toContain('Has Field');
        expect(structural.textContent).not.toContain('Impact Analysis');
        expect(structural.textContent).toContain('Incoming Lookups');
        const incomingLookupsCount = structural.querySelector('[data-row-key="in-lookup"]');
        expect(incomingLookupsCount.textContent).toBe('2');
        expect(structural.textContent).toContain('Outgoing Master-Detail');

        /** Raw attributes now live behind Technical Details, collapsed by default — the data is preserved, only its prominence changed. */
        const technicalDetails = element.shadowRoot.querySelector('[data-id="technical-details"]');
        expect(technicalDetails).not.toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="technical-details-table"]')).toBeNull();

        element.shadowRoot.querySelector('[data-id="technical-details-toggle"]').click();
        await flushPromises();

        const revealed = element.shadowRoot.querySelector('[data-id="technical-details-table"]');
        expect(revealed.textContent).toContain('pluralLabel');
        expect(revealed.textContent).not.toContain('custom');
    });

    it('renders Self Relationships/Referenced Objects/Referencing Objects only when objectRelationshipSummary is supplied (Object mode, from oiGraphExplorer), as plain non-drilldown counts', async () => {
        getNodeDetail.mockResolvedValue(objectDetail());
        const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
        element.objectRelationshipSummary = { selfRelationships: 1, referencedObjects: 5, referencingObjects: 71 };
        document.body.appendChild(element);
        element.nodeKey = 'account';
        await flushPromises();

        const structural = element.shadowRoot.querySelector('[data-id="structural-connections"]');
        expect(structural.textContent).toContain('Self Relationships');
        expect(structural.textContent).toContain('Referenced Objects');
        expect(structural.textContent).toContain('Referencing Objects');
        expect(structural.textContent).toContain('71');
        expect(structural.querySelectorAll('[data-id="curated-relationship-count"]').length).toBe(3);
    });

    it('omits Self Relationships/Referenced Objects/Referencing Objects rows (rather than fabricating zeros) when objectRelationshipSummary has not been supplied yet', async () => {
        getNodeDetail.mockResolvedValue(objectDetail());
        const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
        document.body.appendChild(element);
        element.nodeKey = 'account';
        await flushPromises();

        const structural = element.shadowRoot.querySelector('[data-id="structural-connections"]');
        expect(structural.textContent).not.toContain('Self Relationships');
        expect(structural.textContent).not.toContain('Referenced Objects');
        expect(structural.textContent).not.toContain('Referencing Objects');
    });

    it('collapses and re-expands the Relationships section on header click', async () => {
        getNodeDetail.mockResolvedValue(objectDetail({ directConnectionCount: 7, outgoingRelationshipCounts: { 'SalesforceMetadata.HAS_FIELD': 5 }, incomingRelationshipCounts: { 'SalesforceMetadata.LOOKUP_TO': 2 } }));
        const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
        document.body.appendChild(element);
        element.nodeKey = 'account';
        await flushPromises();

        const structural = element.shadowRoot.querySelector('[data-id="structural-connections"]');
        expect(structural.textContent).toContain('Incoming Lookups');
        const toggle = structural.querySelector('[data-id="relationships-section-toggle"]');
        expect(toggle.getAttribute('aria-expanded')).toBe('true');

        toggle.click();
        await flushPromises();
        expect(structural.textContent).not.toContain('Incoming Lookups');
        expect(structural.querySelector('[data-id="curated-relationship-count-button"]')).toBeNull();

        toggle.click();
        await flushPromises();
        expect(structural.textContent).toContain('Incoming Lookups');
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
            await expandSection(element, 'fields');

            const fieldsSection = element.shadowRoot.querySelector('[data-id="fields-section"]');
            expect(fieldsSection.textContent).toContain('Fields');
            expect(fieldsSection.querySelector('[data-id="fields-section-toggle"] .oi-node-detail-panel-section-count').textContent).toBe('2');
            expect(element.shadowRoot.querySelector('[data-id="show-fields-button"]')).not.toBeNull();
            expect(getFieldSummaries).not.toHaveBeenCalled();
        });

        it('collapsing the Fields section header hides the Show Fields trigger, and re-expanding restores it', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            const toggle = element.shadowRoot.querySelector('[data-id="fields-section-toggle"]');
            expect(toggle.getAttribute('aria-expanded')).toBe('false');
            expect(element.shadowRoot.querySelector('[data-id="show-fields-button"]')).toBeNull();

            toggle.click();
            await flushPromises();
            expect(toggle.getAttribute('aria-expanded')).toBe('true');
            expect(element.shadowRoot.querySelector('[data-id="show-fields-button"]')).not.toBeNull();

            toggle.click();
            await flushPromises();
            expect(toggle.getAttribute('aria-expanded')).toBe('false');
            expect(element.shadowRoot.querySelector('[data-id="show-fields-button"]')).toBeNull();
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
            await expandSection(element, 'fields');

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
            await expandSection(element, 'fields');

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
            await expandSection(element, 'fields');
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
            await expandSection(element, 'fields');
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
            await expandSection(element, 'fields');
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
            await expandSection(element, 'fields');
            element.shadowRoot.querySelector('[data-id="show-fields-button"]').click();
            await flushPromises();
            expect(element.shadowRoot.querySelector('[data-id="fields-table"]')).not.toBeNull();

            element.nodeKey = 'contact';
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="fields-table"]')).toBeNull();
            await expandSection(element, 'fields');
            expect(element.shadowRoot.querySelector('[data-id="show-fields-button"]')).not.toBeNull();
        });

        it('renders a sanitized error when getFieldSummaries fails', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            getFieldSummaries.mockRejectedValue({ body: { message: 'You don\'t have permission to view org graph data.' } });
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();
            await expandSection(element, 'fields');

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
            await expandSection(element, 'fields');

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

        it('collapsing the Impact section header hides its actions, and re-expanding restores them', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();

            const toggle = element.shadowRoot.querySelector('[data-id="impact-section-toggle"]');
            expect(toggle.getAttribute('aria-expanded')).toBe('false');
            expect(element.shadowRoot.querySelector('[data-id="impact-forward-button"]')).toBeNull();

            toggle.click();
            await flushPromises();
            expect(toggle.getAttribute('aria-expanded')).toBe('true');
            expect(element.shadowRoot.querySelector('[data-id="impact-forward-button"]')).not.toBeNull();

            toggle.click();
            await flushPromises();
            expect(toggle.getAttribute('aria-expanded')).toBe('false');
            expect(element.shadowRoot.querySelector('[data-id="impact-forward-button"]')).toBeNull();
        });

        it('shows both Impact Analysis actions for a non-Apex node too — the feature is generic, never gated to a hardcoded node type', async () => {
            getNodeDetail.mockResolvedValue(objectDetail());
            const element = createElement('c-oi-node-detail-panel', { is: OiNodeDetailPanel });
            document.body.appendChild(element);
            element.nodeKey = 'account';
            await flushPromises();
            await expandSection(element, 'impact');

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
            await expandSection(element, 'impact');

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
            await expandSection(element, 'impact');

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
            await expandSection(element, 'impact');

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
            await expandSection(element, 'impact');

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
            await expandSection(element, 'impact');

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
            await expandSection(element, 'impact');

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
            await expandSection(element, 'impact');

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
            await expandSection(element, 'impact');
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
            await expandSection(element, 'impact');
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
            await expandSection(element, 'impact');
            element.shadowRoot.querySelector('[data-id="impact-forward-button"]').click();
            await flushPromises();
            expect(element.shadowRoot.querySelector('[data-id="impact-coverage-caveat"]')).not.toBeNull();

            element.nodeKey = 'contact';
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-id="impact-coverage-caveat"]')).toBeNull();
        });
    });
});
