/**
 * Purpose: The Detail Panel (GraphUI.md §7) — a container: calls getNodeDetail on
 *          selection, renders a curated, human-readable summary for Object/Field nodes plus
 *          a generic fallback for every other node type.
 * Responsibilities: Re-fetch whenever nodeKey changes (a reactive @api setter); render
 *                    loading/error/empty/detail states explicitly (GraphUI.md §29); surface
 *                    Label/API Name/Namespace/Custom-vs-Standard/Data Type/Parent
 *                    Object/Referenced Object directly from OI_NodeDetailDTO's own fields and
 *                    attributes (real scanner data only — nothing here is fabricated); render
 *                    an honest "Structural Connections" summary from
 *                    outgoingRelationshipCounts/incomingRelationshipCounts/
 *                    directConnectionCount (OI_RelationshipCounts) — explicitly scoped to
 *                    structural edges only, never presented as Apex/Flow/Trigger dependency
 *                    or impact analysis, since no scanner discovers those yet.
 * Limitations: Full Impact Analysis ("what breaks if I change this") is not implemented —
 *              deferred alongside a real OI_DependencyController (Roadmap Phase 4). Parent
 *              Object for a Field is derived from the field's own deterministic
 *              "Object.Field" secondaryKey format (OI_FieldScanner's documented,
 *              non-heuristic fullyQualifiedName convention) rather than a second Apex
 *              round-trip. A Record Analysis node (ADR-0021) has no "attributes blob" or
 *              metadata relationship-count concept — OI_GraphController.getNodeDetail
 *              doesn't know about it at all — so selecting one instead re-resolves its own
 *              summary from OI_RecordHierarchyController.getRecordFragment (cacheable,
 *              already the exact call that revealed it) and derives an honest Record
 *              Overview (name/Id/object, all parsed from the real nodeKey — never a second
 *              query) plus a real Hierarchy summary (parent lookups by target, child records
 *              grouped by object, both counted directly from the SAME fragment's own edges —
 *              never fabricated, never a fresh query). Record relationship counts are
 *              deliberately never merged into relationshipCountRows/directConnectionCount:
 *              those are RelationshipCounts.md's metadata-structural vocabulary
 *              (HAS_FIELD/LOOKUP_TO/MASTER_DETAIL_TO edges between metadata components) and
 *              a record's own parent/child *data* relationships are a categorically
 *              different thing — conflating them would misrepresent one as the other.
 *              Owner/CreatedDate/LastModifiedDate are not shown: OI_RecordHierarchyService's
 *              query never selects them (it selects only Id/Name and populated reference
 *              fields, by design, to stay within governor limits on wide objects), so
 *              showing them here would require a second per-record query this panel does
 *              not make — a real, scoped gap, not an oversight.
 * Fields section (Hierarchy Visualizer field-browser sprint): for an Object node, a
 *              dedicated Show All/Standard/Custom field browser — the deliberate answer to
 *              moving field-browsing off the canvas card ("see fields when asked") rather
 *              than the generic Structural Connections table above, which stays untouched
 *              and still reports a plain Has Field *count* like every other edge type. The
 *              field list itself is loaded lazily, only once the user explicitly expands the
 *              section (getFieldSummaries, one bulk call, never per-field) — mirroring this
 *              same panel's own Impact Analysis precedent of "a heavier read is a distinct,
 *              explicit action, never automatic on selection." Loaded field data is cached
 *              per node selection only (a fresh nodeKey clears it); it is not re-fetched on
 *              every search/filter keystroke, which only re-filters the already-loaded list
 *              client-side.
 */
import { LightningElement, api } from 'lwc';
import getNodeDetail from '@salesforce/apex/OI_GraphController.getNodeDetail';
import getFieldSummaries from '@salesforce/apex/OI_GraphController.getFieldSummaries';
import getRecordFragment from '@salesforce/apex/OI_RecordHierarchyController.getRecordFragment';
import getImpact from '@salesforce/apex/OI_DependencyController.getImpact';
import getNodeIntelligence from '@salesforce/apex/OI_GraphController.getNodeIntelligence';
import { resolveNodeStyle, resolveEdgeStyle } from 'c/presentationRegistry';
import { parseRecordNodeKey } from 'c/recordNodeKey';

const OBJECT_TYPE_KEY = 'SalesforceMetadata.CustomObject';
const FIELD_TYPE_KEY = 'SalesforceMetadata.CustomField';
const HAS_FIELD_TYPE_KEY = 'SalesforceMetadata.HAS_FIELD';
const LOOKUP_TO_TYPE_KEY = 'SalesforceMetadata.LOOKUP_TO';
const MASTER_DETAIL_TO_TYPE_KEY = 'SalesforceMetadata.MASTER_DETAIL_TO';
const RECORD_TYPE_PREFIX = 'SalesforceRecord.';
const RECORD_PARENT_EDGE_TYPE_KEY = 'SalesforceRecord.LOOKUP_TO';
const RECORD_CHILD_EDGE_TYPE_KEY = 'SalesforceRecord.CHILD_OF';
const FIELD_TYPE_FILTERS = ['All', 'Standard', 'Custom'];
/** GraphUI.md §42/Intelligence Panel rebuild — a scanned-but-old result is flagged rather than presented as fresh. A tunable client constant, same MVP-constant precedent as oiGraphExplorer.js's WORKING_SET_CEILING. */
const STALE_THRESHOLD_MS = 30 * 24 * 60 * 60 * 1000;
/** OI_NodeIntelligenceService's own fixed, small category vocabulary (never a dynamic/open-ended list) — a plain lookup table, not a per-type branch in rendering logic. */
const CATEGORY_ICON_NAMES = {
    Automation: 'utility:apex_plugin',
    Code: 'utility:code_playground',
    Security: 'utility:lock'
};

/** Attribute keys already surfaced explicitly elsewhere in the template — excluded from the generic "Other Attributes" fallback table so nothing is shown twice. */
const CURATED_ATTRIBUTE_KEYS = new Set(['label', 'custom', 'namespace', 'type', 'referenceTo', 'relationshipName']);

export default class OiNodeDetailPanel extends LightningElement {
    @api registry = null;
    /** Object mode's distinct-object relationship counts (Self/Referenced/Referencing), supplied by oiGraphExplorer — null for Field/Record modes, or before a center is selected, so this panel falls back to its existing generic relationshipCountRows there (GraphUI.md §42's curated Relationships breakdown is an Object-mode concept). */
    @api objectRelationshipSummary = null;

    detail = null;
    isLoading = false;
    errorMessage = null;
    fieldSummaries = null;
    isLoadingFields = false;
    fieldsErrorMessage = null;
    fieldSearchTerm = '';
    fieldTypeFilter = 'All';
    fieldsVisible = false;
    impactResult = null;
    impactDirection = null;
    isLoadingImpact = false;
    impactErrorMessage = null;
    intelligence = null;
    isLoadingIntelligence = false;
    intelligenceErrorMessage = null;
    technicalDetailsVisible = false;
    intelligenceRequestId = 0;
    /** The currently-open drill-down selection, or null. Cleared on every new node selection so a dialog can never outlive the node it describes. */
    drilldown = null;
    /** Collapsible-section UI state (GraphUI.md §42 Intelligence Panel rebuild) — a set of collapsed section keys ('fields'/'relationships'/'Automation'/'Code'/'Security'/'impact'); Technical Details keeps its own pre-existing technicalDetailsVisible toggle (already collapsed-by-default) rather than joining this set. Empty (everything expanded) on a fresh node selection. */
    collapsedSections = new Set();
    /** Which categories' "Coverage details" disclosure is open — collapsed (empty set) by default on a fresh node selection. */
    expandedCoverageDetails = new Set();
    /** Whole-panel chrome (Intelligence Panel header) — isPanelExpanded collapses the entire body to reclaim canvas space; isPanelPinned, when on, keeps collapsedSections/expandedCoverageDetails as-is across a node change instead of resetting them, so a layout a user has arranged (e.g. "just show me Security") survives browsing between nodes. Neither is node-specific state, so neither is touched by the nodeKey setter's reset logic below. */
    isPanelExpanded = true;
    isPanelPinned = false;
    _nodeKey;
    detailRequestId = 0;
    fieldRequestId = 0;
    impactRequestId = 0;

    @api
    get nodeKey() {
        return this._nodeKey;
    }

    set nodeKey(value) {
        this._nodeKey = value;
        this.resetFieldBrowser();
        this.resetImpactAnalysis();
        this.resetIntelligence();
        if (!this.isPanelPinned) {
            this.collapsedSections = new Set();
            this.expandedCoverageDetails = new Set();
        }
        this.loadDetail();
        /**
         * Loaded automatically on selection, unlike Impact Analysis which stays an explicit
         * action. The difference is cost and intent: this is a bounded 1-hop read answering
         * "what directly touches this?", which is the question a user has simply by selecting
         * something — making them click for it is what made the old panel feel like a debug
         * view. Impact Analysis is a multi-hop traversal answering a deliberate question, so it
         * stays opt-in.
         */
        this.loadIntelligence();
    }

    resetIntelligence() {
        this.intelligenceRequestId++;
        this.intelligence = null;
        this.isLoadingIntelligence = false;
        this.intelligenceErrorMessage = null;
        this.technicalDetailsVisible = false;
        this.drilldown = null;
    }

    async loadIntelligence() {
        const requestId = ++this.intelligenceRequestId;
        if (!this._nodeKey) {
            return;
        }
        this.isLoadingIntelligence = true;
        this.intelligenceErrorMessage = null;
        try {
            const result = await getNodeIntelligence({ nodeKey: this._nodeKey });
            /** Same stale-response guard the other loaders use — a slower earlier request must never overwrite a newer selection's data. */
            if (requestId !== this.intelligenceRequestId) {
                return;
            }
            this.intelligence = result;
        } catch (error) {
            if (requestId !== this.intelligenceRequestId) {
                return;
            }
            this.intelligence = null;
            this.intelligenceErrorMessage = (error && error.body && error.body.message) || 'Something went wrong loading intelligence for this component.';
        } finally {
            if (requestId === this.intelligenceRequestId) {
                this.isLoadingIntelligence = false;
            }
        }
    }

    /**
     * The Automation / Code / Security sections, each always rendered once intelligence has
     * loaded — including when empty. An empty section that states its own coverage is
     * informative ("no triggers found, and here is what we can detect"); omitting it entirely
     * leaves the user unable to tell "nothing found" from "not looked for", which is the exact
     * ambiguity this sprint exists to remove.
     *
     * Empty-state classification (GraphUI.md §42 Intelligence Panel rebuild, item 22): an empty
     * category is never presented as a single undifferentiated "nothing found" — it is one of
     * Unscanned / Stale / Possibly Incomplete / True Zero, in that priority order, derived
     * entirely from fields OI_NodeIntelligenceDTO already returns (lastScannedAt,
     * hasCoverageLimitations, category.truncated) — no Apex change. True per-category
     * Unsupported-vs-Degraded precision would need an additive OI_NodeIntelligenceDTO.Category
     * status field (reusing OI_ScanCoverage's existing vocabulary) — a known, documented Phase-2
     * gap, not built here.
     */
    get intelligenceSections() {
        if (!this.intelligence || !this.intelligence.categories) {
            return [];
        }
        return this.intelligence.categories.map((category) => {
            const hasItems = (category.items || []).length > 0;
            const emptyStateKind = hasItems ? null : this.classifyEmptyState(category);
            return {
                key: category.category,
                title: category.category,
                iconName: CATEGORY_ICON_NAMES[category.category] || 'utility:knowledge_base',
                iconModifierClass: 'oi-node-detail-panel-section-icon is-' + category.category.toLowerCase(),
                items: (category.items || []).map((item) => ({
                    ...item,
                    directionLabel: item.direction === 'incoming' ? 'uses this' : 'used by this'
                })),
                hasItems,
                countLabel: `${(category.items || []).length}`,
                truncated: !!category.truncated,
                coverageNote: category.coverageNote,
                isCoverageDetailsExpanded: this.expandedCoverageDetails.has(category.category),
                emptyStateKind,
                emptyStateMessage: emptyStateKind ? buildEmptyStateMessage(category.category, emptyStateKind) : null,
                emptyStateBadgeClass: emptyStateKind ? `oi-node-detail-panel-empty-state-badge oi-node-detail-panel-empty-state-${emptyStateKind}` : null,
                isExpanded: !this.collapsedSections.has(category.category)
            };
        });
    }

    /** "Coverage details" disclosure (GraphUI.md §42, item 15) — the scanner's own honest "Detected... Not detected..." explanation stays available, just collapsed by default so it never dominates the primary panel the way a permanently-visible paragraph did. Independent of the section's own collapse state (collapsedSections) — collapsing/re-expanding a whole section shouldn't discard whether its coverage note was open. */
    handleCoverageDetailsToggle(event) {
        event.stopPropagation();
        const category = event.currentTarget.dataset.category;
        const updated = new Set(this.expandedCoverageDetails);
        if (updated.has(category)) {
            updated.delete(category);
        } else {
            updated.add(category);
        }
        this.expandedCoverageDetails = updated;
    }

    get hasIntelligenceSections() {
        return this.intelligenceSections.length > 0;
    }

    get hasIntelligenceError() {
        return !!this.intelligenceErrorMessage;
    }

    /** Whole-payload facts (one scan run backs every category), applied per-category only when that category is itself empty — priority order matches the honesty rule: a stale/unscanned signal always outranks a plain zero, since "zero" is only a trustworthy answer when the data behind it is current. */
    classifyEmptyState(category) {
        if (this.isIntelligenceUnscanned) {
            return 'unscanned';
        }
        if (category.truncated || this.hasCoverageLimitations) {
            return 'incomplete';
        }
        if (this.isIntelligenceStale) {
            return 'stale';
        }
        return 'zero';
    }

    get isIntelligenceUnscanned() {
        return !!this.intelligence && !this.intelligence.lastScannedAt;
    }

    get isIntelligenceStale() {
        if (!this.intelligence || !this.intelligence.lastScannedAt) {
            return false;
        }
        return Date.now() - new Date(this.intelligence.lastScannedAt).getTime() > STALE_THRESHOLD_MS;
    }

    /** Toggles one collapsible section open/closed (Fields, Structural Connections, an intelligence category, Impact) — a plain UI concern, never touching data state. Technical Details keeps its own separate, pre-existing toggle. */
    handleSectionToggle(event) {
        const section = event.currentTarget.dataset.section;
        const updated = new Set(this.collapsedSections);
        if (updated.has(section)) {
            updated.delete(section);
        } else {
            updated.add(section);
        }
        this.collapsedSections = updated;
    }

    // --- Panel chrome (Intelligence Panel header: collapse whole body / pin section layout) ---

    handleTogglePanelExpanded() {
        this.isPanelExpanded = !this.isPanelExpanded;
    }

    get panelToggleIconName() {
        return this.isPanelExpanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get panelToggleLabel() {
        return this.isPanelExpanded ? 'Collapse Intelligence Panel' : 'Expand Intelligence Panel';
    }

    handleTogglePin() {
        this.isPanelPinned = !this.isPanelPinned;
    }

    get pinToggleLabel() {
        return this.isPanelPinned ? 'Unpin panel layout (stop keeping sections open across selections)' : 'Pin panel layout (keep sections open when you select another node)';
    }

    get pinToggleClass() {
        return 'oi-node-detail-panel-pin-toggle' + (this.isPanelPinned ? ' is-active' : '');
    }

    get isFieldsExpanded() {
        return !this.collapsedSections.has('fields');
    }

    get isRelationshipsExpanded() {
        return !this.collapsedSections.has('relationships');
    }

    get isImpactExpanded() {
        return !this.collapsedSections.has('impact');
    }

    /**
     * "Last scanned" provenance. Every number in this panel comes from the persisted scan graph,
     * never a live org read, so stating when it was scanned is what separates trustworthy
     * intelligence from a confident-looking guess. Renders an explicit never-scanned state
     * rather than silently omitting the line, which would read as freshness.
     */
    get scanFreshnessLabel() {
        if (!this.intelligence) {
            return null;
        }
        if (!this.intelligence.lastScannedAt) {
            return 'Never scanned — run a scan to build metadata intelligence.';
        }
        const scannedAt = new Date(this.intelligence.lastScannedAt);
        return `Metadata intelligence last scanned ${scannedAt.toLocaleString()}`;
    }

    get hasScanFreshness() {
        return !!this.scanFreshnessLabel;
    }

    get hasCoverageLimitations() {
        return !!(this.intelligence && this.intelligence.hasCoverageLimitations);
    }

    get technicalDetailsToggleLabel() {
        return this.technicalDetailsVisible ? 'Hide technical details' : 'Show technical details';
    }

    handleToggleTechnicalDetails() {
        this.technicalDetailsVisible = !this.technicalDetailsVisible;
    }

    handleIntelligenceRowClick(event) {
        const nodeKey = event.currentTarget.dataset.nodeKey;
        this.dispatchEvent(new CustomEvent('select', { detail: { nodeKey } }));
    }

    /** A fresh node selection is a fresh Impact Analysis section too — a previous selection's forward/reverse result must never bleed into the newly-selected node's panel. */
    resetImpactAnalysis() {
        this.impactRequestId++;
        this.impactResult = null;
        this.impactDirection = null;
        this.isLoadingImpact = false;
        this.impactErrorMessage = null;
    }

    /** A fresh node selection is a fresh Fields section — loaded field data, search text, and the Standard/Custom filter are all scoped to whichever object is currently selected, never carried over to the next one. */
    resetFieldBrowser() {
        this.fieldRequestId++;
        this.fieldSummaries = null;
        this.isLoadingFields = false;
        this.fieldsErrorMessage = null;
        this.fieldSearchTerm = '';
        this.fieldTypeFilter = 'All';
        this.fieldsVisible = false;
    }

    async loadDetail() {
        const requestId = ++this.detailRequestId;
        const requestedNodeKey = this._nodeKey;
        if (!this._nodeKey) {
            this.detail = null;
            this.errorMessage = null;
            return;
        }
        this.isLoading = true;
        this.errorMessage = null;
        try {
            const recordRef = parseRecordNodeKey(this._nodeKey);
            if (recordRef) {
                const fragment = await getRecordFragment({ objectApiName: recordRef.objectApiName, recordId: recordRef.recordId });
                if (requestId !== this.detailRequestId) {
                    return;
                }
                const summary = (fragment.nodes || []).find((n) => n.nodeKey === requestedNodeKey);
                if (!summary) {
                    this.detail = null;
                    this.errorMessage = 'No record found for that selection.';
                    return;
                }
                this.detail = {
                    ...summary,
                    isRecord: true,
                    recordRef,
                    ...this.deriveRecordHierarchy(fragment, requestedNodeKey),
                    attributes: {},
                    outgoingRelationshipCounts: {},
                    incomingRelationshipCounts: {},
                    directConnectionCount: 0
                };
            } else {
                const detail = await getNodeDetail({ nodeKey: requestedNodeKey });
                if (requestId !== this.detailRequestId) {
                    return;
                }
                this.detail = detail;
            }
        } catch (error) {
            if (requestId === this.detailRequestId) {
                this.detail = null;
                this.errorMessage = (error && error.body && error.body.message) || 'Something went wrong loading node detail.';
            }
        } finally {
            if (requestId === this.detailRequestId) {
                this.isLoading = false;
            }
        }
    }

    /**
     * Every parent lookup and child record already sits in this SAME fragment's own
     * nodes/edges (OI_RecordHierarchyService always returns the center plus its one-hop
     * neighborhood in a single call) — this just groups what's already there: one row per
     * distinct parent record, child records grouped by object (a flat per-record list would
     * be unreadable for an object with hundreds of children, and OI_RecordHierarchyService's
     * own MAX_CHILDREN_PER_RELATIONSHIP cap means "3 of possibly more" is the honest framing
     * anyway, not "exactly 3").
     */
    deriveRecordHierarchy(fragment, centerNodeKey) {
        const nodesByKey = new Map((fragment.nodes || []).map((n) => [n.nodeKey, n]));
        const parentRows = [];
        const childCountsByTypeKey = new Map();
        for (const edge of fragment.edges || []) {
            if (edge.sourceNodeKey !== centerNodeKey) {
                continue;
            }
            const target = nodesByKey.get(edge.targetNodeKey);
            if (!target) {
                continue;
            }
            if (edge.typeKey === RECORD_PARENT_EDGE_TYPE_KEY) {
                parentRows.push({ nodeKey: target.nodeKey, label: target.label, typeLabel: this.recordTypeDisplayLabel(target.typeKey) });
            } else if (edge.typeKey === RECORD_CHILD_EDGE_TYPE_KEY) {
                childCountsByTypeKey.set(target.typeKey, (childCountsByTypeKey.get(target.typeKey) || 0) + 1);
            }
        }
        const childRows = Array.from(childCountsByTypeKey.entries()).map(([typeKey, count]) => ({
            key: typeKey,
            typeLabel: this.recordTypeDisplayLabel(typeKey),
            count
        }));
        return { parentRows, childRows, hasMoreRelationships: !!fragment.hasMore };
    }

    /** "SalesforceRecord.Contact" -> "Contact" — there is no per-object registry entry for every possible SObject a record hierarchy might touch (unlike the fixed, small metadata typeKey set), so the object's own real API name, already embedded in the typeKey by OI_RecordSchemaUtil's own deterministic convention, IS the honest display label — never a guess. */
    recordTypeDisplayLabel(typeKey) {
        const registered = resolveNodeStyle(this.registry, typeKey).displayLabel;
        if (registered) {
            return registered;
        }
        return typeKey && typeKey.startsWith(RECORD_TYPE_PREFIX) ? typeKey.slice(RECORD_TYPE_PREFIX.length) : typeKey;
    }

    get isRecordDetail() {
        return !!this.detail && !!this.detail.isRecord;
    }

    get recordObjectApiName() {
        return this.detail && this.detail.recordRef ? this.detail.recordRef.objectApiName : '';
    }

    get recordId() {
        return this.detail && this.detail.recordRef ? this.detail.recordRef.recordId : '';
    }

    get recordParentRows() {
        return (this.detail && this.detail.parentRows) || [];
    }

    get hasRecordParents() {
        return this.recordParentRows.length > 0;
    }

    get recordChildRows() {
        return (this.detail && this.detail.childRows) || [];
    }

    get hasRecordChildren() {
        return this.recordChildRows.length > 0;
    }

    get hasRecordHierarchy() {
        return this.hasRecordParents || this.hasRecordChildren;
    }

    get recordHasMoreNote() {
        return !!(this.detail && this.detail.hasMoreRelationships);
    }

    get hasSelection() {
        return !!this._nodeKey;
    }

    get hasDetail() {
        return !!this.detail;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get isObject() {
        return !!this.detail && this.detail.typeKey === OBJECT_TYPE_KEY;
    }

    get isField() {
        return !!this.detail && this.detail.typeKey === FIELD_TYPE_KEY;
    }

    get typeDisplayLabel() {
        if (!this.detail) {
            return '';
        }
        if (this.detail.isRecord) {
            return this.recordTypeDisplayLabel(this.detail.typeKey) + ' Record';
        }
        return resolveNodeStyle(this.registry, this.detail.typeKey).displayLabel || this.detail.typeKey;
    }

    get apiName() {
        return this.detail ? this.detail.secondaryKey : '';
    }

    get attributes() {
        return (this.detail && this.detail.attributes) || {};
    }

    get hasCustomFlag() {
        const custom = this.attributes.custom;
        return custom === true || custom === false;
    }

    get customOrStandardLabel() {
        return this.attributes.custom === true ? 'Custom' : 'Standard';
    }

    get namespaceDisplay() {
        return this.attributes.namespace ? this.attributes.namespace : 'None (org-native)';
    }

    get dataTypeDisplay() {
        return this.attributes.type || '—';
    }

    /**
     * "Account.OwnerId" -> "Account" — the parent object's API name, derived from the
     * deterministic fullyQualifiedName format OI_FieldScanner always produces, not a guess.
     */
    get parentObjectApiName() {
        if (!this.isField || !this.apiName || this.apiName.indexOf('.') === -1) {
            return null;
        }
        return this.apiName.split('.')[0];
    }

    get hasParentObject() {
        return !!this.parentObjectApiName;
    }

    get referencedObjects() {
        const referenceTo = this.attributes.referenceTo;
        return Array.isArray(referenceTo) ? referenceTo : [];
    }

    get hasReferencedObjects() {
        return this.referencedObjects.length > 0;
    }

    get referencedObjectsDisplay() {
        return this.referencedObjects.join(', ');
    }

    get relationshipName() {
        return this.attributes.relationshipName || null;
    }

    /**
     * Derived from the field's own OUTGOING structural edges (LOOKUP_TO/MASTER_DETAIL_TO) —
     * a Field node never stores its own relationship kind as an attribute; that fact only
     * exists on the edge, which OI_RelationshipCounts already surfaces here for free.
     */
    get fieldRelationshipTypeLabel() {
        if (!this.detail || !this.detail.outgoingRelationshipCounts) {
            return null;
        }
        const outgoingTypes = Object.keys(this.detail.outgoingRelationshipCounts).filter((typeKey) => typeKey !== HAS_FIELD_TYPE_KEY);
        if (outgoingTypes.length === 0) {
            return null;
        }
        return outgoingTypes.map((typeKey) => resolveEdgeStyle(this.registry, typeKey).displayLabel || typeKey).join(', ');
    }

    get hasFieldRelationshipType() {
        return !!this.fieldRelationshipTypeLabel;
    }

    /**
     * "Type" as shown in the Overview grid — deliberately distinct from typeDisplayLabel (the
     * registry's generic per-typeKey label, e.g. plain "Object") for an Object node specifically:
     * Overview states "Standard Object"/"Custom Object" directly, reusing the same custom flag
     * customOrStandardLabel already derives, rather than making a reader cross-reference a
     * separate "Custom / Standard" row to learn what kind of Object they're looking at. Field and
     * Record nodes have no such distinct concept, so they fall back to the registry label as
     * before.
     */
    get overviewTypeLabel() {
        if (this.isObject && this.hasCustomFlag) {
            return `${this.customOrStandardLabel} Object`;
        }
        return this.typeDisplayLabel;
    }

    /**
     * The Overview section's ordered (label, value) pairs, replacing what used to be a hand-built
     * table with an lwc:if per node kind — a flat list a single template loop renders as a
     * two-column grid (GraphUI.md §42's approved Overview layout), the same information as
     * before, just described once as data instead of duplicated across four branching template
     * blocks. Order matters: it is exactly the on-screen order.
     */
    get overviewFields() {
        if (!this.detail) {
            return [];
        }
        if (this.isRecordDetail) {
            return [
                { key: 'name', label: 'Name', value: this.detail.label },
                { key: 'object', label: 'Object', value: this.recordObjectApiName },
                { key: 'recordId', label: 'Record Id', value: this.recordId }
            ];
        }
        const fields = [];
        /** A label that differs from the API name (e.g. a custom field's "Deal Size" vs. Deal_Size__c) is real identity information the API Name row alone can't carry — shown whenever the two actually differ, never as a redundant repeat of the same string. */
        if (this.detail.label && this.detail.label !== this.apiName) {
            fields.push({ key: 'name', label: 'Name', value: this.detail.label });
        }
        fields.push({ key: 'apiName', label: 'API Name', value: this.apiName });
        if (this.isField) {
            fields.push({ key: 'type', label: 'Type', value: this.overviewTypeLabel });
            fields.push({ key: 'dataType', label: 'Data Type', value: this.dataTypeDisplay });
            if (this.hasCustomFlag) {
                fields.push({ key: 'customStandard', label: 'Custom / Standard', value: this.customOrStandardLabel });
            }
            if (this.hasParentObject) {
                fields.push({ key: 'parentObject', label: 'Parent Object', value: this.parentObjectApiName });
            }
            if (this.hasFieldRelationshipType) {
                fields.push({ key: 'relationshipType', label: 'Relationship Type', value: this.fieldRelationshipTypeLabel });
            }
            if (this.hasReferencedObjects) {
                fields.push({ key: 'referencedObjects', label: 'Referenced Object(s)', value: this.referencedObjectsDisplay });
                fields.push({ key: 'relationshipName', label: 'Relationship Name', value: this.relationshipName });
            }
            return fields;
        }
        fields.push({ key: 'type', label: 'Type', value: this.overviewTypeLabel });
        if (this.isObject) {
            fields.push({ key: 'namespace', label: 'Namespace', value: this.namespaceDisplay });
        }
        if (this.hasCustomFlag) {
            fields.push({ key: 'customStandard', label: 'Custom / Standard', value: this.customOrStandardLabel });
        }
        return fields;
    }

    /**
     * The structural relationship summary — every row now a drill-down trigger.
     *
     * Each row carries the (direction, edgeTypeKey) pair the drill-down needs, which is the same
     * pair this count was computed from. That is what makes the product's central promise
     * enforceable: clicking "52" opens exactly those 52, because both sides describe the same
     * selection rather than two independently-derived ones.
     */
    get relationshipCountRows() {
        if (!this.detail) {
            return [];
        }
        const rows = [];
        const outgoing = this.detail.outgoingRelationshipCounts || {};
        const incoming = this.detail.incomingRelationshipCounts || {};
        for (const typeKey of Object.keys(outgoing)) {
            rows.push({
                key: 'out-' + typeKey,
                direction: 'Outgoing',
                drilldownDirection: 'outgoing',
                edgeTypeKey: typeKey,
                label: resolveEdgeStyle(this.registry, typeKey).displayLabel || typeKey,
                count: outgoing[typeKey]
            });
        }
        for (const typeKey of Object.keys(incoming)) {
            rows.push({
                key: 'in-' + typeKey,
                direction: 'Incoming',
                drilldownDirection: 'incoming',
                edgeTypeKey: typeKey,
                label: resolveEdgeStyle(this.registry, typeKey).displayLabel || typeKey,
                count: incoming[typeKey]
            });
        }
        return rows;
    }

    /**
     * Opens the drill-down for one summary row. State lives here rather than in the child so the
     * child stays a pure, parameterised view that can be reused by any other surface later
     * (the graph canvas, a future Org Health page) without inheriting this panel's state.
     */
    handleDrilldownOpen(event) {
        const key = event.currentTarget.dataset.rowKey;
        const row = this.relationshipCountRows.find((candidate) => candidate.key === key);
        if (!row) {
            return;
        }
        this.drilldown = {
            direction: row.drilldownDirection,
            edgeTypeKey: row.edgeTypeKey,
            relationshipLabel: row.label
        };
    }

    handleDrilldownClose() {
        this.drilldown = null;
    }

    /** A drill-down row asking to be shown on the graph closes the dialog and re-emits upward — the panel never mutates graph state itself. */
    handleDrilldownNodeSelect(event) {
        const nodeKey = event.detail.nodeKey;
        this.drilldown = null;
        this.dispatchEvent(new CustomEvent('select', { detail: { nodeKey } }));
    }

    get hasDrilldown() {
        return !!this.drilldown;
    }

    get drilldownAnchorLabel() {
        return this.detail ? this.detail.label : '';
    }

    get hasRelationshipCounts() {
        return this.hasCuratedRelationshipRows || this.relationshipCountRows.length > 0;
    }

    /**
     * The curated Object-relationship breakdown (GraphUI.md §42's Intelligence Panel rebuild,
     * item 14): Incoming/Outgoing Lookups and Master-Detail are HAS_FIELD-free, schema-membership
     * information moved out entirely (it already powers the Fields section's own count) — this
     * section only ever shows genuine object-to-object relationship metrics, never raw internal
     * edge-type taxonomy. The four counts are read directly from the same
     * incoming/outgoingRelationshipCounts getNodeDetail already returns (no new fetch); Self
     * Relationships/Referenced Objects/Referencing Objects are DISTINCT OBJECT counts the
     * container computes once from the already-fetched canvas working set (objectRelationshipSummary)
     * since a per-edge-type count cannot answer "how many distinct objects," and are simply
     * omitted (not shown as a fabricated zero) when that summary isn't available yet.
     */
    get curatedRelationshipRows() {
        if (!this.detail) {
            return [];
        }
        const incoming = this.detail.incomingRelationshipCounts || {};
        const outgoing = this.detail.outgoingRelationshipCounts || {};
        const rows = [
            { key: 'in-lookup', direction: 'incoming', edgeTypeKey: LOOKUP_TO_TYPE_KEY, label: 'Incoming Lookups', count: incoming[LOOKUP_TO_TYPE_KEY] || 0, isDrilldownEligible: true },
            { key: 'in-md', direction: 'incoming', edgeTypeKey: MASTER_DETAIL_TO_TYPE_KEY, label: 'Incoming Master-Detail', count: incoming[MASTER_DETAIL_TO_TYPE_KEY] || 0, isDrilldownEligible: true },
            { key: 'out-lookup', direction: 'outgoing', edgeTypeKey: LOOKUP_TO_TYPE_KEY, label: 'Outgoing Lookups', count: outgoing[LOOKUP_TO_TYPE_KEY] || 0, isDrilldownEligible: true },
            { key: 'out-md', direction: 'outgoing', edgeTypeKey: MASTER_DETAIL_TO_TYPE_KEY, label: 'Outgoing Master-Detail', count: outgoing[MASTER_DETAIL_TO_TYPE_KEY] || 0, isDrilldownEligible: true }
        ];
        if (this.objectRelationshipSummary) {
            rows.push(
                { key: 'self', label: 'Self Relationships', count: this.objectRelationshipSummary.selfRelationships, isDrilldownEligible: false },
                { key: 'referenced-objects', label: 'Referenced Objects', count: this.objectRelationshipSummary.referencedObjects, isDrilldownEligible: false },
                { key: 'referencing-objects', label: 'Referencing Objects', count: this.objectRelationshipSummary.referencingObjects, isDrilldownEligible: false }
            );
        }
        return rows;
    }

    /** Object mode only — Field/Record keep the existing generic relationshipCountRows (their own drilldown-eligible per-edge-type breakdown, unchanged). */
    get hasCuratedRelationshipRows() {
        return this.isObject && this.curatedRelationshipRows.length > 0;
    }

    get relationshipSectionCount() {
        return this.hasCuratedRelationshipRows ? this.curatedRelationshipRows.length : this.relationshipCountRows.length;
    }

    /** Mirrors handleDrilldownOpen's row-key lookup, scoped to the curated row shape — kept separate rather than unified with the generic handler since the two row shapes (curated vs. per-edge-type) diverge slightly (isDrilldownEligible has no equivalent on the generic rows). */
    handleCuratedDrilldownOpen(event) {
        const key = event.currentTarget.dataset.rowKey;
        const row = this.curatedRelationshipRows.find((candidate) => candidate.key === key);
        if (!row || !row.isDrilldownEligible) {
            return;
        }
        this.drilldown = {
            direction: row.direction,
            edgeTypeKey: row.edgeTypeKey,
            relationshipLabel: row.label
        };
    }

    get directConnectionCount() {
        return (this.detail && this.detail.directConnectionCount) || 0;
    }

    get attributeRows() {
        if (!this.detail || !this.detail.attributes) {
            return [];
        }
        return Object.keys(this.detail.attributes)
            .filter((key) => !CURATED_ATTRIBUTE_KEYS.has(key))
            .map((key) => ({
                key,
                value: this.detail.attributes[key] === null || this.detail.attributes[key] === undefined ? '' : String(this.detail.attributes[key])
            }));
    }

    get hasOtherAttributes() {
        return this.attributeRows.length > 0;
    }

    /** Free — already part of every getNodeDetail response via OI_RelationshipCounts, so the field count is visible even before the user asks to load the actual field list. */
    get fieldCount() {
        return (this.detail && this.detail.outgoingRelationshipCounts && this.detail.outgoingRelationshipCounts[HAS_FIELD_TYPE_KEY]) || 0;
    }

    get hasFieldsToShow() {
        return this.fieldCount > 0;
    }

    get areFieldsLoaded() {
        return this.fieldSummaries !== null;
    }

    get hasFieldsError() {
        return !!this.fieldsErrorMessage;
    }

    /** Lazy, explicit load (see class doc comment's "Fields section" note) — one bulk call, made only the first time the section is opened; a subsequent Show Fields (after Hide Fields collapsed the section) just flips visibility back on against the already-cached list, no redundant Apex call. */
    async handleShowFields() {
        if (this.areFieldsLoaded) {
            this.fieldsVisible = true;
            return;
        }
        const requestId = ++this.fieldRequestId;
        const requestedNodeKey = this._nodeKey;
        this.isLoadingFields = true;
        this.fieldsErrorMessage = null;
        try {
            const summaries = await getFieldSummaries({ objectNodeKey: requestedNodeKey });
            if (requestId !== this.fieldRequestId) {
                return;
            }
            this.fieldSummaries = summaries;
            this.fieldsVisible = true;
        } catch (error) {
            if (requestId === this.fieldRequestId) {
                this.fieldSummaries = null;
                this.fieldsErrorMessage = (error && error.body && error.body.message) || 'Something went wrong loading fields.';
            }
        } finally {
            if (requestId === this.fieldRequestId) {
                this.isLoadingFields = false;
            }
        }
    }

    /** Collapses the Fields section without discarding fieldSummaries — the loaded list stays cached so the next Show Fields is instant. */
    handleHideFields() {
        this.fieldsVisible = false;
    }

    handleFieldSearchInput(event) {
        this.fieldSearchTerm = event.target.value;
    }

    handleFieldTypeFilterChange(event) {
        this.fieldTypeFilter = event.currentTarget.dataset.filter;
    }

    get fieldTypeFilterOptions() {
        return FIELD_TYPE_FILTERS.map((filterValue) => {
            const isActive = filterValue === this.fieldTypeFilter;
            return { value: filterValue, isActive, buttonClass: 'oi-node-detail-panel-field-filter-button' + (isActive ? ' is-active' : '') };
        });
    }

    /** Client-side only — the already-loaded field list is what's being searched/filtered, never a new fetch (matching graphRelationshipFilter.js's own "already-loaded working set" framing for the canvas). */
    get filteredFieldRows() {
        if (!this.fieldSummaries) {
            return [];
        }
        const term = this.fieldSearchTerm.trim().toLowerCase();
        return this.fieldSummaries
            .filter((field) => {
                if (this.fieldTypeFilter === 'Standard' && field.isCustom !== false) {
                    return false;
                }
                if (this.fieldTypeFilter === 'Custom' && field.isCustom !== true) {
                    return false;
                }
                if (!term) {
                    return true;
                }
                return (field.label || '').toLowerCase().includes(term) || (field.apiName || '').toLowerCase().includes(term);
            })
            .map((field) => ({
                nodeKey: field.nodeKey,
                label: field.label,
                apiName: field.apiName,
                dataType: field.dataType || '—',
                badgeLabel: field.isCustom === true ? 'Custom' : field.isCustom === false ? 'Standard' : '—',
                badgeClass: 'oi-node-detail-panel-field-badge' + (field.isCustom === true ? ' is-custom' : field.isCustom === false ? ' is-standard' : '')
            }))
            .sort((a, b) => a.label.localeCompare(b.label));
    }

    get hasFilteredFieldRows() {
        return this.filteredFieldRows.length > 0;
    }

    /** A field row selection is a plain selection, not a re-center — the canvas's own selectedNodeKey flows down to this same panel, so clicking a field here just makes this panel reload to show that field's own detail next, exactly as clicking an already-visible field pill on the canvas would. */
    handleFieldRowClick(event) {
        const nodeKey = event.currentTarget.dataset.nodeKey;
        this.dispatchEvent(new CustomEvent('select', { detail: { nodeKey } }));
    }

    /**
     * Impact Analysis (GraphUI.md §7) — a distinct, explicit action on top of the always-on
     * Structural Connections summary above, never automatic on selection. Generic: shown for
     * every node type, not gated to Apex classes specifically, since the underlying traversal
     * itself is generic — a node type with no dependency-flavored edges simply gets an honest
     * empty result, never a hardcoded per-type branch here.
     */
    async handleShowForwardImpact() {
        await this.loadImpact('forward');
    }

    async handleShowReverseImpact() {
        await this.loadImpact('reverse');
    }

    async loadImpact(direction) {
        const requestId = ++this.impactRequestId;
        const requestedNodeKey = this._nodeKey;
        this.isLoadingImpact = true;
        this.impactErrorMessage = null;
        this.impactDirection = direction;
        try {
            const result = await getImpact({ nodeKey: requestedNodeKey, direction, depth: null });
            if (requestId !== this.impactRequestId) {
                return;
            }
            this.impactResult = result;
        } catch (error) {
            if (requestId === this.impactRequestId) {
                this.impactResult = null;
                this.impactErrorMessage = (error && error.body && error.body.message) || 'Something went wrong computing impact analysis.';
            }
        } finally {
            if (requestId === this.impactRequestId) {
                this.isLoadingImpact = false;
            }
        }
    }

    get hasImpactResult() {
        return !!this.impactResult;
    }

    get hasImpactError() {
        return !!this.impactErrorMessage;
    }

    get impactDirectionLabel() {
        return this.impactDirection === 'reverse' ? 'What depends on this' : 'What does this depend on';
    }

    /**
     * Client-side row shaping only — the already-fetched affectedComponents list, never a new
     * fetch. The type column resolves through the Presentation Registry (§20) rather than
     * printing the raw typeKey: an impact result can now legitimately mix Apex classes,
     * triggers, Flows, objects and permission sets in one list (Backlog DE-8/DE-9/DE-11), and
     * "SalesforceMetadata.PermissionSet" is an internal key, not something to show a user.
     * Falls back to the raw typeKey when the registry has no descriptor, exactly like every
     * other registry consumer here — a generic default, never a crash and never a per-type
     * branch in component code.
     */
    get impactAffectedRows() {
        if (!this.impactResult) {
            return [];
        }
        return (this.impactResult.affectedComponents || []).map((component) => ({
            nodeKey: component.nodeKey,
            label: component.label,
            typeLabel: this.recordTypeDisplayLabel(component.typeKey),
            hopDistance: component.hopDistance,
            cycleBadgeVisible: !!component.isInCycle
        }));
    }

    get hasImpactAffectedRows() {
        return this.impactAffectedRows.length > 0;
    }

    /**
     * A per-metadata-type breakdown of the impact result (Backlog DE-14) — "3 Apex Classes,
     * 1 Apex Trigger, 2 Permission Sets" — shown above the flat table.
     *
     * Why this earns its place rather than being decoration: before the cross-metadata scanners
     * landed, every impact row was an Apex class, so a flat list carried no ambiguity. Now a
     * single result mixes kinds whose consequences are completely different in nature — an Apex
     * class appearing means code may break, whereas a permission set appearing means someone
     * loses ACCESS. Leading with the composition lets a reader see that mix before reading
     * rows, instead of inferring it by scanning a type column.
     *
     * Counting order is insertion order (first-appearance), which follows the traversal's own
     * hop ordering — nearest-impact types surface first, rather than being alphabetized into an
     * order that discards that signal.
     */
    get impactTypeBreakdown() {
        const countByTypeLabel = new Map();
        for (const row of this.impactAffectedRows) {
            countByTypeLabel.set(row.typeLabel, (countByTypeLabel.get(row.typeLabel) || 0) + 1);
        }
        return [...countByTypeLabel.entries()].map(([typeLabel, count]) => ({
            key: typeLabel,
            text: `${count} ${count === 1 ? typeLabel : pluralizeTypeLabel(typeLabel)}`
        }));
    }

    /** One type in the whole result is exactly the pre-DE-8/9/11 situation — the breakdown would just restate the table's own uniform type column, so it is suppressed rather than shown as a single redundant chip. */
    get hasImpactTypeBreakdown() {
        return this.impactTypeBreakdown.length > 1;
    }

    /** Same plain-selection pattern as handleFieldRowClick — never a re-center. */
    handleImpactRowClick(event) {
        const nodeKey = event.currentTarget.dataset.nodeKey;
        this.dispatchEvent(new CustomEvent('select', { detail: { nodeKey } }));
    }

    /**
     * "Highlight on Graph" (GraphUI.md §7): merges the already-fetched impact subgraph into
     * the shell's own GraphViewState exactly as an ordinary expand would — via a bottom-up
     * event the shell (oiGraphExplorer, the only place a GraphViewState mutation happens)
     * resolves by calling graphViewState.js's existing applyExpand(state, nodeKey, fragment)
     * unchanged. This panel never touches GraphViewState itself. impactResult.subgraph is
     * shaped exactly like an OI_GraphFragmentDTO (nodes[]/edges[]/hasMore/nextCursor), so no
     * transformation is needed before handing it to applyExpand.
     */
    handleHighlightOnGraph() {
        if (!this.impactResult) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('highlightimpact', {
                detail: { nodeKey: this.impactResult.rootNodeKey, fragment: this.impactResult.subgraph }
            })
        );
    }
}

/**
 * Builds an honest, category-specific empty-state message (GraphUI.md §42, item 22) — never a
 * single generic "nothing found" that could just as easily mean "not scanned yet" or "results
 * are old." categoryLabel is one of the fixed 'Automation'/'Code'/'Security' category names
 * OI_NodeIntelligenceService always returns, never a raw internal key.
 */
function buildEmptyStateMessage(categoryLabel, kind) {
    const lowerLabel = (categoryLabel || 'automation').toLowerCase();
    switch (kind) {
        case 'unscanned':
            return `${categoryLabel} data has not been scanned yet.`;
        case 'stale':
            return `Results shown are from an older scan — rescan to refresh ${lowerLabel} data.`;
        case 'incomplete':
            return `${categoryLabel} results may be incomplete for this org — see the coverage note below.`;
        default:
            return `No ${lowerLabel} detected for this component.`;
    }
}

/**
 * Pluralizes a registry-supplied node-type label for the impact type breakdown (DE-14).
 *
 * This exists because the labels are ADMIN-CONFIGURABLE Custom Metadata values, not a fixed
 * internal enum — so a naive `label + 's'` is wrong for a real shipped label in this very
 * package ("Apex Class" -> "Apex Classs"). Handles the two English rules that actually bite for
 * noun-phrase labels: a sibilant ending takes "es", and a consonant+y ending becomes "ies".
 * Deliberately NOT a general inflection library — irregular plurals ("Person" -> "People") are
 * knowingly unhandled, since every label this platform ships is a regular noun phrase and
 * vendoring an inflector to cover a case no shipped label hits would be unjustified weight
 * (CLAUDE.md: prefer simple architecture that scales, never complexity that merely looks
 * thorough). A future irregular label would read slightly wrong here — cosmetic, never
 * incorrect data — which is the accepted trade.
 */
function pluralizeTypeLabel(label) {
    if (!label) {
        return label;
    }
    if (/(s|x|z|ch|sh)$/i.test(label)) {
        return `${label}es`;
    }
    if (/[^aeiou]y$/i.test(label)) {
        return `${label.slice(0, -1)}ies`;
    }
    return `${label}s`;
}
