/**
 * Purpose: Object analyze mode's presentation transform (GraphUI.md §42, ADR-0023) — a plain,
 *          framework-free JS module, exactly like graphViewState.js/graphRelationshipFilter.js.
 *          Derives directional object-to-object relationships (incoming/outgoing/self) from
 *          the already-fetched, already-styled working set, for oiRelationshipCanvas to
 *          render. Never calls Apex, never touches the real GraphViewState, never mutates its
 *          inputs.
 * Responsibilities: Filter the working set down to Object-typed cards only (the fix for
 *                    ApexTrigger/Flow/PermissionSet/ApexClass leakage, GraphUI.md §42.1);
 *                    resolve each (Object)-HAS_FIELD->(Field)-LOOKUP_TO|MASTER_DETAIL_TO->
 *                    (Object) chain into a direct object-to-object relationship; classify each
 *                    as incoming/outgoing/self relative to the centered object; aggregate
 *                    multiple relationship fields between the same object pair into one
 *                    connector; classify System vs. Business by field API name.
 * Dependencies: None.
 * Limitations: Center-anchored only (GraphUI.md §42.2 step 4) — a relationship between two
 *              non-center objects that both happen to be in the working set is intentionally
 *              excluded, since this view answers "what does *this* object relate to," not
 *              "everything currently loaded." Operates only over the already-loaded working
 *              set, exactly like graphRelationshipFilter.js — going further than what's loaded
 *              is still the existing expand action's job. A relationship field or either of
 *              its endpoint objects missing from the current node set is silently excluded
 *              (the same "dangling reference" discipline graphRelationshipFilter.js already
 *              applies), never an error.
 */

export const OBJECT_TYPE_KEY = 'SalesforceMetadata.CustomObject';
export const FIELD_TYPE_KEY = 'SalesforceMetadata.CustomField';
const HAS_FIELD_EDGE_TYPE_KEY = 'SalesforceMetadata.HAS_FIELD';
const LOOKUP_TO_EDGE_TYPE_KEY = 'SalesforceMetadata.LOOKUP_TO';
const MASTER_DETAIL_TO_EDGE_TYPE_KEY = 'SalesforceMetadata.MASTER_DETAIL_TO';
const REFERENCE_EDGE_TYPE_KEYS = new Set([LOOKUP_TO_EDGE_TYPE_KEY, MASTER_DETAIL_TO_EDGE_TYPE_KEY]);

/**
 * The universal, platform-standard audit-field API names (present on effectively every
 * SObject) — not org-specific configuration, so this fixed list is the same category of
 * platform constant as an edge typeKey literal, never "inventing a business requirement."
 * Exact match only, deliberately not a suffix/fuzzy match: a custom field cannot legitimately
 * be named exactly "OwnerId" without being one.
 */
export const SYSTEM_FIELD_API_NAMES = new Set(['OwnerId', 'CreatedById', 'LastModifiedById']);

/** Initially-visible connectors per lane (GraphUI.md §42.2 step 6) — oiRelationshipCanvas owns the "show more" reveal as its own local UI state; this module always returns the full, sorted set. */
export const DEFAULT_VISIBLE_PER_LANE = 6;

export function isSystemField(fieldApiName) {
    return !!fieldApiName && SYSTEM_FIELD_API_NAMES.has(fieldApiName);
}

/** No Salesforce standard object's API name ends in "__c" — total and safe, no new fetch (OI_NodeSummary never carries the attributes blob this could otherwise come from). */
export function isCustomApiName(apiName) {
    return !!apiName && apiName.endsWith('__c');
}

/** "Account.OwnerId" -> "OwnerId" — the same deterministic fullyQualifiedName convention oiNodeDetailPanel.js already relies on for its own parentObjectApiName getter, applied to the other half of the same "Object.Field" string. Falls back to the raw value when no dot is present rather than guessing. */
function deriveFieldApiName(fieldSecondaryKey) {
    if (!fieldSecondaryKey) {
        return null;
    }
    const dotIndex = fieldSecondaryKey.indexOf('.');
    return dotIndex === -1 ? fieldSecondaryKey : fieldSecondaryKey.slice(dotIndex + 1);
}

/**
 * Builds the Object-relationship view-model for the currently centered object.
 *
 * @param {Array} nodes - the container's already-styled working set (allCanvasNodes)
 * @param {Array} edges - the container's already-styled working set (allCanvasEdges)
 * @param {string} centerNodeKey - the currently analyzed object's nodeKey
 * @returns {{rootObject: object|null, incomingRelationships: Array, outgoingRelationships: Array, selfRelationships: Array, counts: object}}
 */
export function buildObjectRelationshipView(nodes, edges, centerNodeKey) {
    const allNodes = nodes || [];
    const allEdges = edges || [];
    const nodeByKey = new Map(allNodes.map((node) => [node.nodeKey, node]));
    const objectNodesByKey = new Map(allNodes.filter((node) => node.typeKey === OBJECT_TYPE_KEY).map((node) => [node.nodeKey, node]));

    const ownerByFieldKey = buildOwnershipIndex(allEdges, objectNodesByKey);
    const connectorGroups = extractConnectorGroups(allEdges, ownerByFieldKey, objectNodesByKey, centerNodeKey, nodeByKey);

    const incoming = [];
    const outgoing = [];
    const self = [];
    for (const group of connectorGroups.values()) {
        const connector = buildConnector(group, objectNodesByKey);
        if (!connector) {
            continue;
        }
        if (connector.direction === 'self') {
            self.push(connector);
        } else if (connector.direction === 'outgoing') {
            outgoing.push(connector);
        } else {
            incoming.push(connector);
        }
    }

    const rootNode = nodeByKey.get(centerNodeKey) || null;

    return {
        rootObject: rootNode ? buildObjectRef(rootNode) : null,
        incomingRelationships: sortConnectors(incoming),
        outgoingRelationships: sortConnectors(outgoing),
        selfRelationships: sortConnectors(self),
        counts: {
            incomingTotal: incoming.length,
            outgoingTotal: outgoing.length,
            selfTotal: self.length
        }
    };
}

/** fieldKey -> ownerObjectKey, from every HAS_FIELD edge whose source is a currently-visible Object card. Built fresh here, unconditional — not reused from oiGraphCanvas's registry-gated field-absorption map, which answers a different, narrower rendering question for a different canvas (GraphUI.md §42.2 step 2). */
function buildOwnershipIndex(edges, objectNodesByKey) {
    const ownerByFieldKey = new Map();
    for (const edge of edges) {
        if (edge.typeKey === HAS_FIELD_EDGE_TYPE_KEY && objectNodesByKey.has(edge.sourceNodeKey)) {
            ownerByFieldKey.set(edge.targetNodeKey, edge.sourceNodeKey);
        }
    }
    return ownerByFieldKey;
}

/**
 * Groups every LOOKUP_TO/MASTER_DETAIL_TO edge by its (ownerObjectKey, referencedObjectKey)
 * pair, keeping only relationships that touch the centered object (owner, referenced, or
 * both — GraphUI.md §42.2 step 4). A polymorphic field (e.g. WhatId referencing multiple
 * object types) correctly produces one group per referenced object, since each reference
 * target is its own edge with its own targetNodeKey — expected, not a duplicate.
 */
function extractConnectorGroups(edges, ownerByFieldKey, objectNodesByKey, centerNodeKey, nodeByKey) {
    const groups = new Map();
    for (const edge of edges) {
        if (!REFERENCE_EDGE_TYPE_KEYS.has(edge.typeKey)) {
            continue;
        }
        const ownerKey = ownerByFieldKey.get(edge.sourceNodeKey);
        const referencedKey = edge.targetNodeKey;
        if (!ownerKey || !objectNodesByKey.has(ownerKey) || !objectNodesByKey.has(referencedKey)) {
            continue;
        }
        if (ownerKey !== centerNodeKey && referencedKey !== centerNodeKey) {
            continue;
        }
        const groupKey = ownerKey + '::' + referencedKey;
        if (!groups.has(groupKey)) {
            groups.set(groupKey, {
                ownerKey,
                referencedKey,
                fields: [],
                direction: ownerKey === referencedKey ? 'self' : ownerKey === centerNodeKey ? 'outgoing' : 'incoming'
            });
        }
        const fieldNode = nodeByKey.get(edge.sourceNodeKey);
        const fieldSecondaryKey = fieldNode ? fieldNode.secondaryKey : null;
        groups.get(groupKey).fields.push({
            fieldNodeKey: edge.sourceNodeKey,
            /** The field's own fully-qualified API name (e.g. "Account.OwnerId", per OI_FieldScanner.cls's fullyQualifiedName convention) — carried so oiRelationshipConnectorDetail can resolve navigation via OI_GraphController.getNavigationTarget without a second lookup back into the working set. */
            fieldSecondaryKey,
            /**
             * The field's own API name (e.g. "OwnerId"), derived from the field NODE's own
             * secondaryKey — deliberately NOT edge.viaFieldApiName. Confirmed against a real org
             * (ADR-0023 implementation validation): despite its name and doc comment,
             * viaFieldApiName is populated from the edge's stored `relationshipName` attribute
             * (OI_GraphTraversal.cls's extractViaFieldApiName), which for a standard lookup is
             * the RELATIONSHIP name, not the field API name — "CreatedBy"/"Owner", never
             * "CreatedById"/"OwnerId". Using it directly would both display the wrong string
             * (mandate item 5 wants a real field API name, e.g. "AccountId · Lookup") and,
             * critically, silently break System-relationship classification (§42.3), since
             * SYSTEM_FIELD_API_NAMES is the real field-API-name vocabulary. Deriving from the
             * field node's own secondaryKey needs no new fetch — OI_NodeSummary always carries it.
             */
            fieldApiName: deriveFieldApiName(fieldSecondaryKey),
            relationshipType: edge.typeKey === MASTER_DETAIL_TO_EDGE_TYPE_KEY ? 'MasterDetail' : 'Lookup',
            isSystemRelationship: isSystemField(deriveFieldApiName(fieldSecondaryKey))
        });
    }
    return groups;
}

/**
 * One aggregated connector per (owner, referenced) pair (GraphUI.md §42.2 step 5).
 * primaryRelationshipType is Master-Detail if any field in the group is one; connector-level
 * isSystemRelationship is true only if EVERY field in the group is system-classified, so a
 * connector never looks hidden-by-default merely because one of several fields sharing it
 * happens to be a system field.
 */
function buildConnector(group, objectNodesByKey) {
    const direction = group.direction;
    const counterpartKey = direction === 'outgoing' ? group.referencedKey : group.ownerKey;
    const counterpartNode = objectNodesByKey.get(counterpartKey);
    if (!counterpartNode) {
        return null;
    }

    const fields = group.fields.slice().sort((a, b) => (a.fieldApiName || '').localeCompare(b.fieldApiName || ''));
    const hasMasterDetail = fields.some((field) => field.relationshipType === 'MasterDetail');
    const isSystemRelationship = fields.length > 0 && fields.every((field) => field.isSystemRelationship);

    return {
        connectorKey: direction + '::' + counterpartNode.nodeKey,
        counterpartObject: buildObjectRef(counterpartNode),
        direction,
        fields,
        relationshipCount: fields.length,
        primaryRelationshipType: hasMasterDetail ? 'MasterDetail' : 'Lookup',
        isSystemRelationship
    };
}

function buildObjectRef(node) {
    return {
        nodeKey: node.nodeKey,
        label: node.label,
        secondaryKey: node.secondaryKey,
        iconName: node.iconName,
        colorToken: node.colorToken,
        isCustom: isCustomApiName(node.secondaryKey)
    };
}

function sortConnectors(connectors) {
    return connectors.slice().sort((a, b) => {
        if (b.relationshipCount !== a.relationshipCount) {
            return b.relationshipCount - a.relationshipCount;
        }
        return (a.counterpartObject.label || '').localeCompare(b.counterpartObject.label || '');
    });
}
