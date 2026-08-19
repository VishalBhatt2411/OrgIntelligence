/**
 * Purpose: Fetch-once-per-session, client-cached Presentation Type Registry (GraphUI.md
 *          §20/§21/§34) — resolves a typeKey to icon/color/line-style, never a hardcoded
 *          per-type branch anywhere in this UI. See graphViewState.js's own header comment
 *          on the `oiSharedUtils/` nesting adaptation — the same applies here.
 * Responsibilities: Call OI_SettingsController.getPresentationRegistry exactly once per
 *                    tab session (module-level cache); resolve typeKey -> style, falling
 *                    back to a fixed generic default for any unregistered typeKey — never
 *                    an error, never a broken render (the explicit, required mandate this
 *                    module exists to satisfy).
 */
import getPresentationRegistry from '@salesforce/apex/OI_SettingsController.getPresentationRegistry';

const GENERIC_NODE_ICON = 'standard:custom';
const GENERIC_NODE_COLOR = 'neutral';
const GENERIC_EDGE_LINE_STYLE = 'solid';

let cachedRegistry = null;

export async function loadPresentationRegistry() {
    if (cachedRegistry) {
        return cachedRegistry;
    }
    const result = await getPresentationRegistry();
    const nodeTypes = new Map();
    for (const descriptor of result.nodeTypes || []) {
        nodeTypes.set(descriptor.typeKey, descriptor);
    }
    const edgeTypes = new Map();
    for (const descriptor of result.edgeTypes || []) {
        edgeTypes.set(descriptor.typeKey, descriptor);
    }
    cachedRegistry = { nodeTypes, edgeTypes };
    return cachedRegistry;
}

/** Unregistered typeKey resolves to a fixed generic default — never an error (GraphUI.md §20). */
export function resolveNodeStyle(registry, typeKey) {
    const descriptor = registry && registry.nodeTypes.get(typeKey);
    if (!descriptor) {
        return { iconName: GENERIC_NODE_ICON, colorToken: GENERIC_NODE_COLOR, displayLabel: null, showFieldList: false };
    }
    return {
        iconName: descriptor.iconName || GENERIC_NODE_ICON,
        colorToken: descriptor.colorToken || GENERIC_NODE_COLOR,
        displayLabel: descriptor.displayLabel,
        showFieldList: !!descriptor.showFieldList
    };
}

/** Identical fallback contract as resolveNodeStyle, for edges (GraphUI.md §21). */
export function resolveEdgeStyle(registry, typeKey) {
    const descriptor = registry && registry.edgeTypes.get(typeKey);
    if (!descriptor) {
        return { lineStyle: GENERIC_EDGE_LINE_STYLE, displayLabel: null, isFieldMembership: false };
    }
    return {
        lineStyle: descriptor.lineStyle || GENERIC_EDGE_LINE_STYLE,
        displayLabel: descriptor.displayLabel,
        isFieldMembership: !!descriptor.isFieldMembership
    };
}

/** Test-only seam — the module-level cache is deliberately session-lifetime (GraphUI.md §10), so tests must be able to reset it between cases. */
export function resetPresentationRegistryCacheForTests() {
    cachedRegistry = null;
}
