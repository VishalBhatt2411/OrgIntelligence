import {
    loadPresentationRegistry,
    resolveNodeStyle,
    resolveEdgeStyle,
    resolveNeighbourRole,
    listRelationshipLegend,
    resetPresentationRegistryCacheForTests
} from 'c/presentationRegistry';
import getPresentationRegistry from '@salesforce/apex/OI_SettingsController.getPresentationRegistry';

jest.mock('@salesforce/apex/OI_SettingsController.getPresentationRegistry', () => ({ default: jest.fn() }), { virtual: true });

describe('presentationRegistry', () => {
    beforeEach(() => {
        resetPresentationRegistryCacheForTests();
        getPresentationRegistry.mockReset();
    });

    it('fetches once and caches for the session — a second call does not re-invoke Apex', async () => {
        getPresentationRegistry.mockResolvedValue({
            nodeTypes: [{ typeKey: 'SalesforceMetadata.Flow', displayLabel: 'Flow', iconName: 'standard:flow', colorToken: 'blue' }],
            edgeTypes: [{ typeKey: 'SalesforceMetadata.CALLS', displayLabel: 'Calls', lineStyle: 'dashed' }]
        });

        const first = await loadPresentationRegistry();
        const second = await loadPresentationRegistry();

        expect(getPresentationRegistry).toHaveBeenCalledTimes(1);
        expect(first).toBe(second);
    });

    it('resolves a registered typeKey to its configured icon/color', async () => {
        getPresentationRegistry.mockResolvedValue({
            nodeTypes: [{ typeKey: 'SalesforceMetadata.Flow', displayLabel: 'Flow', iconName: 'standard:flow', colorToken: 'blue' }],
            edgeTypes: []
        });
        const registry = await loadPresentationRegistry();

        const style = resolveNodeStyle(registry, 'SalesforceMetadata.Flow');
        expect(style.iconName).toBe('standard:flow');
        expect(style.colorToken).toBe('blue');
    });

    it('resolves showFieldList from the registry — the Schema-Builder-card-vs-pill rendering decision, driven by data, never a hardcoded typeKey check in the Canvas', async () => {
        getPresentationRegistry.mockResolvedValue({
            nodeTypes: [
                { typeKey: 'SalesforceMetadata.CustomObject', displayLabel: 'Object', iconName: 'standard:record', colorToken: 'brand', showFieldList: true },
                { typeKey: 'SalesforceMetadata.CustomField', displayLabel: 'Field', iconName: 'standard:textbox', colorToken: 'success', showFieldList: false }
            ],
            edgeTypes: []
        });
        const registry = await loadPresentationRegistry();

        expect(resolveNodeStyle(registry, 'SalesforceMetadata.CustomObject').showFieldList).toBe(true);
        expect(resolveNodeStyle(registry, 'SalesforceMetadata.CustomField').showFieldList).toBe(false);
        expect(resolveNodeStyle(registry, 'SalesforceMetadata.NeverSeenBefore').showFieldList).toBe(false);
    });

    describe('resolveNeighbourRole (this sprint\'s "why is this node here?" requirement)', () => {
        async function buildLookupRegistry() {
            getPresentationRegistry.mockResolvedValue({
                nodeTypes: [],
                edgeTypes: [
                    { typeKey: 'SalesforceMetadata.LOOKUP_TO', displayLabel: 'Lookup', lineStyle: 'solid', sourceRoleLabel: 'References', targetRoleLabel: 'Referenced By' }
                ]
            });
            return loadPresentationRegistry();
        }

        it('gives the neighbour its TARGET role when the anchor is the edge\'s source', async () => {
            const registry = await buildLookupRegistry();
            const edge = { sourceNodeKey: 'opportunity', targetNodeKey: 'account' };

            const role = resolveNeighbourRole(registry, 'SalesforceMetadata.LOOKUP_TO', 'opportunity', edge);

            expect(role).toBe('Referenced By');
        });

        it('gives the neighbour its SOURCE role when the anchor is the edge\'s target — the inverted case a backwards implementation would get wrong', async () => {
            const registry = await buildLookupRegistry();
            const edge = { sourceNodeKey: 'opportunity', targetNodeKey: 'account' };

            const role = resolveNeighbourRole(registry, 'SalesforceMetadata.LOOKUP_TO', 'account', edge);

            expect(role).toBe('References');
        });

        it('falls back to generic, non-technical wording for an unregistered relationship type, never the raw typeKey', async () => {
            const registry = await buildLookupRegistry();
            const edge = { sourceNodeKey: 'a', targetNodeKey: 'b' };

            const role = resolveNeighbourRole(registry, 'SalesforceMetadata.NeverSeenBefore', 'a', edge);

            expect(role).toBe('Related To');
        });
    });

    describe('listRelationshipLegend (the graph\'s relationship legend)', () => {
        it('lists every registered relationship type with its human label and teaching description, never a raw typeKey', async () => {
            getPresentationRegistry.mockResolvedValue({
                nodeTypes: [],
                edgeTypes: [
                    { typeKey: 'SalesforceMetadata.LOOKUP_TO', displayLabel: 'Lookup', lineStyle: 'solid', description: 'A lookup relationship — an optional reference from one record to another.' },
                    { typeKey: 'SalesforceMetadata.EXECUTES_ON', displayLabel: 'Executes On', lineStyle: 'solid', description: 'Automation that runs when records of this object change.' }
                ]
            });
            const registry = await loadPresentationRegistry();

            const legend = listRelationshipLegend(registry);

            expect(legend).toHaveLength(2);
            const displayLabels = legend.map((entry) => entry.displayLabel);
            expect(displayLabels).toEqual(expect.arrayContaining(['Lookup', 'Executes On']));
            /** typeKey is retained internally (e.g. for a caller keying a map) but displayLabel — the only field a legend template would actually render — must never itself be the raw internal identifier. */
            for (const label of displayLabels) {
                expect(label).not.toContain('SalesforceMetadata.');
            }
            expect(legend.find((entry) => entry.displayLabel === 'Lookup').description).toContain('optional reference');
        });

        it('returns an empty legend rather than throwing when the registry has not loaded yet', () => {
            expect(listRelationshipLegend(null)).toEqual([]);
        });
    });

    it('a never-registered typeKey resolves to the generic default, never an error — the required unknown-type mandate (GraphUI.md §20)', async () => {
        getPresentationRegistry.mockResolvedValue({ nodeTypes: [], edgeTypes: [] });
        const registry = await loadPresentationRegistry();

        const nodeStyle = resolveNodeStyle(registry, 'SalesforceMetadata.NeverSeenBefore');
        expect(nodeStyle.iconName).toBe('standard:custom');
        expect(nodeStyle.colorToken).toBe('neutral');

        const edgeStyle = resolveEdgeStyle(registry, 'SalesforceMetadata.NeverSeenBefore');
        expect(edgeStyle.lineStyle).toBe('solid');
        expect(edgeStyle.isFieldMembership).toBe(false);
    });

    it('resolves isFieldMembership from the registry — the Canvas\'s data-driven signal to absorb a field into its owning object\'s card instead of rendering a separate relationship line', async () => {
        getPresentationRegistry.mockResolvedValue({
            nodeTypes: [],
            edgeTypes: [
                { typeKey: 'SalesforceMetadata.HAS_FIELD', displayLabel: 'Has Field', lineStyle: 'solid', isFieldMembership: true },
                { typeKey: 'SalesforceMetadata.LOOKUP_TO', displayLabel: 'Lookup To', lineStyle: 'dashed', isFieldMembership: false }
            ]
        });
        const registry = await loadPresentationRegistry();

        expect(resolveEdgeStyle(registry, 'SalesforceMetadata.HAS_FIELD').isFieldMembership).toBe(true);
        expect(resolveEdgeStyle(registry, 'SalesforceMetadata.LOOKUP_TO').isFieldMembership).toBe(false);
    });

    it('resolveNodeStyle/resolveEdgeStyle tolerate a null registry (registry not yet loaded) without throwing', () => {
        expect(() => resolveNodeStyle(null, 'anything')).not.toThrow();
        expect(() => resolveEdgeStyle(null, 'anything')).not.toThrow();
    });
});
