/**
 * Purpose: Record analyze mode's presentation transform (ADR-0024) — the Record-mode sibling of
 *          c/objectRelationshipView, producing the exact same {rootObject, incomingRelationships,
 *          outgoingRelationships, selfRelationships, counts} shape from the already-fetched
 *          Record Analysis working set (ADR-0021's OI_RecordHierarchyService fragments) so
 *          oiRelationshipCanvas can render Record mode through the identical lane/org-chart
 *          layout Object mode already uses. Never calls Apex, never mutates its inputs.
 * Responsibilities: Classify every LOOKUP_TO/CHILD_OF record edge touching the centered record
 *                    as incoming/outgoing relative to it; treat a counterpart record of the SAME
 *                    object type as the center as a self relationship (the record-mode analog of
 *                    Object mode's "this object references itself" — records are individually
 *                    keyed by Id, so two distinct records of one object is what "self" means
 *                    here, not the same node referencing itself); group multiple edges to the
 *                    same counterpart record into one connector.
 * Dependencies: c/recordNodeKey (parses a record nodeKey into {objectApiName, recordId}, the
 *               same parser oiGraphExplorer.js already uses for expand/re-center dispatch).
 * Limitations: OI_RecordHierarchyService's fragment carries no originating field API name for a
 *              record edge (unlike Object mode's HAS_FIELD-derived field detail) — so a record
 *              connector has no fields[] breakdown and no System/Business field classification.
 *              Every record relationship is labeled a plain "Related Record"; oiRelationshipCanvas
 *              hides its Business/System/All toggle entirely in Record mode rather than offer a
 *              filter it cannot actually apply. A future enhancement to OI_RecordHierarchyService
 *              carrying the originating field's API name would unlock both without any change to
 *              this module's own output shape.
 */
import { parseRecordNodeKey } from 'c/recordNodeKey';

const PARENT_EDGE_TYPE_KEY = 'SalesforceRecord.LOOKUP_TO';
const CHILD_EDGE_TYPE_KEY = 'SalesforceRecord.CHILD_OF';
const RECORD_EDGE_TYPE_KEYS = new Set([PARENT_EDGE_TYPE_KEY, CHILD_EDGE_TYPE_KEY]);

/**
 * Builds the Record-relationship view-model for the currently centered record.
 *
 * @param {Array} nodes - the container's already-fetched Record Analysis working set
 * @param {Array} edges - the container's already-fetched Record Analysis working set
 * @param {string} centerNodeKey - the currently analyzed record's nodeKey
 * @returns {{rootObject: object|null, incomingRelationships: Array, outgoingRelationships: Array, selfRelationships: Array, counts: object}}
 */
export function buildRecordRelationshipView(nodes, edges, centerNodeKey) {
    const allNodes = nodes || [];
    const allEdges = edges || [];
    const nodeByKey = new Map(allNodes.map((node) => [node.nodeKey, node]));
    const centerNode = nodeByKey.get(centerNodeKey) || null;

    const groups = extractConnectorGroups(allEdges, centerNodeKey, nodeByKey);

    const incoming = [];
    const outgoing = [];
    const self = [];
    for (const group of groups.values()) {
        const connector = buildConnector(group, centerNodeKey, nodeByKey);
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

    return {
        rootObject: centerNode ? buildRecordRef(centerNode) : null,
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

/**
 * Groups every LOOKUP_TO/CHILD_OF edge touching the centered record by its (referencer,
 * referenced) pair. CHILD_OF is stored center->child (OI_RecordHierarchyService.cls's
 * addChildRelationships) but means "the target is a child of, i.e. references, the source" —
 * the inverse of LOOKUP_TO's own source/target roles (source references target). Resolving to a
 * uniform (referencer, referenced) pair up front means direction classification below never has
 * to branch on typeKey again.
 */
function extractConnectorGroups(edges, centerNodeKey, nodeByKey) {
    const groups = new Map();
    for (const edge of edges) {
        if (!RECORD_EDGE_TYPE_KEYS.has(edge.typeKey)) {
            continue;
        }
        const referencerKey = edge.typeKey === PARENT_EDGE_TYPE_KEY ? edge.sourceNodeKey : edge.targetNodeKey;
        const referencedKey = edge.typeKey === PARENT_EDGE_TYPE_KEY ? edge.targetNodeKey : edge.sourceNodeKey;
        if (referencerKey !== centerNodeKey && referencedKey !== centerNodeKey) {
            continue;
        }
        if (!nodeByKey.has(referencerKey) || !nodeByKey.has(referencedKey)) {
            continue;
        }
        const groupKey = referencerKey + '::' + referencedKey;
        if (!groups.has(groupKey)) {
            groups.set(groupKey, { referencerKey, referencedKey, edgeCount: 0 });
        }
        groups.get(groupKey).edgeCount++;
    }
    return groups;
}

/**
 * One connector per (referencer, referenced) pair. A counterpart of the SAME object type as the
 * center overrides direction to 'self' regardless of which side referenced which — the
 * record-mode reading of "this relates to itself," since two distinct record nodes (not one) are
 * what a same-typeKey pair actually means here.
 */
function buildConnector(group, centerNodeKey, nodeByKey) {
    const counterpartKey = group.referencerKey === centerNodeKey ? group.referencedKey : group.referencerKey;
    const counterpartNode = nodeByKey.get(counterpartKey);
    const centerNode = nodeByKey.get(centerNodeKey);
    if (!counterpartNode || !centerNode) {
        return null;
    }
    const structuralDirection = group.referencerKey === centerNodeKey ? 'outgoing' : 'incoming';
    const direction = counterpartNode.typeKey === centerNode.typeKey ? 'self' : structuralDirection;
    const relationshipTypeLabel = group.edgeCount > 1 ? 'Related Records' : 'Related Record';

    return {
        connectorKey: direction + '::' + counterpartNode.nodeKey,
        counterpartObject: buildRecordRef(counterpartNode),
        direction,
        fields: [],
        relationshipCount: group.edgeCount,
        primaryRelationshipType: 'Lookup',
        relationshipTypeLabel,
        isSystemRelationship: false
    };
}

function buildRecordRef(node) {
    const parsed = parseRecordNodeKey(node.nodeKey);
    return {
        nodeKey: node.nodeKey,
        label: node.label,
        /** Already the record's own object API name, never the record Id (OI_RecordHierarchyService.cls's own secondaryKey convention) — exactly the caption text a card subtitle needs to tell an Account card apart from a Contact card. */
        secondaryKey: node.secondaryKey,
        iconName: node.iconName,
        colorToken: node.colorToken,
        isCustom: false,
        objectApiName: parsed ? parsed.objectApiName : node.secondaryKey,
        recordId: parsed ? parsed.recordId : null
    };
}

function sortConnectors(connectors) {
    return connectors.slice().sort((a, b) => (a.counterpartObject.label || '').localeCompare(b.counterpartObject.label || ''));
}
