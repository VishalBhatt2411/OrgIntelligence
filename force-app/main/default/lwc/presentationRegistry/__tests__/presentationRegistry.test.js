import { loadPresentationRegistry, resolveNodeStyle, resolveEdgeStyle, resetPresentationRegistryCacheForTests } from 'c/presentationRegistry';
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
