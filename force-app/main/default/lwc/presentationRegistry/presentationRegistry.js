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
/** Neutral wording for an unregistered relationship — never the raw typeKey, which must not reach a user. */
const GENERIC_ROLE_LABEL = 'Related To';

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

/**
 * Identical fallback contract as resolveNodeStyle, for edges (GraphUI.md §21).
 *
 * Also resolves the relationship's SEMANTICS — the role each end plays and a one-line
 * description. These are what let a node card state why it is on screen ("Executes On Account")
 * and let the legend explain itself, without any component learning what a specific relationship
 * type is. An unregistered type degrades to generic wording rather than leaking its raw key.
 */
export function resolveEdgeStyle(registry, typeKey) {
    const descriptor = registry && registry.edgeTypes.get(typeKey);
    if (!descriptor) {
        return {
            lineStyle: GENERIC_EDGE_LINE_STYLE,
            displayLabel: null,
            isFieldMembership: false,
            sourceRoleLabel: GENERIC_ROLE_LABEL,
            targetRoleLabel: GENERIC_ROLE_LABEL,
            description: null
        };
    }
    return {
        lineStyle: descriptor.lineStyle || GENERIC_EDGE_LINE_STYLE,
        displayLabel: descriptor.displayLabel,
        isFieldMembership: !!descriptor.isFieldMembership,
        sourceRoleLabel: descriptor.sourceRoleLabel || GENERIC_ROLE_LABEL,
        targetRoleLabel: descriptor.targetRoleLabel || GENERIC_ROLE_LABEL,
        description: descriptor.description || null
    };
}

/**
 * The role a NEIGHBOUR plays relative to an anchor node, given the edge between them.
 *
 * Direction is the whole point and the easiest thing to get backwards: on an edge
 * anchor --> neighbour the neighbour is the TARGET and carries the target role; on
 * neighbour --> anchor it is the SOURCE. Inverting this would tell a user "Account executes on
 * this trigger", which is precisely the wrong way round, so the mapping lives in one place and is
 * unit-tested rather than re-derived per component.
 */
export function resolveNeighbourRole(registry, typeKey, anchorNodeKey, edge) {
    const style = resolveEdgeStyle(registry, typeKey);
    if (!edge) {
        return style.targetRoleLabel;
    }
    const anchorIsSource = edge.sourceNodeKey === anchorNodeKey;
    return anchorIsSource ? style.targetRoleLabel : style.sourceRoleLabel;
}

/** Every registered relationship type with its human label and explanation — the data the graph legend renders. */
export function listRelationshipLegend(registry) {
    if (!registry || !registry.edgeTypes) {
        return [];
    }
    return [...registry.edgeTypes.values()]
        .map((descriptor) => ({
            typeKey: descriptor.typeKey,
            displayLabel: descriptor.displayLabel || descriptor.typeKey,
            lineStyle: descriptor.lineStyle || GENERIC_EDGE_LINE_STYLE,
            description: descriptor.description || null
        }))
        .sort((a, b) => a.displayLabel.localeCompare(b.displayLabel));
}

/** Test-only seam — the module-level cache is deliberately session-lifetime (GraphUI.md §10), so tests must be able to reset it between cases. */
export function resetPresentationRegistryCacheForTests() {
    cachedRegistry = null;
}
