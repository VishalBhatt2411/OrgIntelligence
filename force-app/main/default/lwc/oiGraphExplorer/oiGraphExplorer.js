/**
 * Purpose: The Graph UI shell/container (GraphUI.md §3) — the only component in this
 *          subsystem that calls Apex. Owns the authoritative GraphViewState and the
 *          Presentation Type Registry cache lifecycle (§10, §20), and the Analyze mode
 *          (Object/Field/Record) that makes the graph a deliberate Hierarchy Visualizer
 *          rather than a generic explorer (see PRD "Primary User Experience").
 * Responsibilities: Search selection -> a curated, mode-driven getGraphFragment call
 *                    (hopDepth 2 for Object — reaches both referenced and referencing
 *                    objects in one fetch, since a field's reference edge and its parent's
 *                    HAS_FIELD edge are each one further hop from the object itself; hopDepth
 *                    1 for Field — reaches both its parent object and any referenced object
 *                    directly, since HAS_FIELD/LOOKUP_TO/MASTER_DETAIL_TO are each exactly
 *                    one hop from the field), applied via graphViewState.js's
 *                    setCenterFromFragment; expand/collapse -> bounded one-hop
 *                    getGraphFragment calls via applyExpand/applyCollapse; resolve node/edge
 *                    styling via the registry before handing already-resolved props down to
 *                    oiGraphCanvas (§20 — the lookup happens one level up, never inside
 *                    oiGraphNode itself).
 * Limitations: nodeTypeFilter[] is not wired (a full oiFilterPanel is deferred, Backlog
 *              UI-4, Phase 3) — but a lightweight edgeTypeFilter now exists, folded directly
 *              into the relationship legend itself (click a legend entry to hide/show that
 *              edge type) rather than a separate filter panel, per the "avoid overbuilding a
 *              giant filter panel" guidance — see hiddenEdgeTypes/handleToggleEdgeTypeFilter.
 *              Max_Canvas_Working_Set__c is not read dynamically
 *              (OI_SettingsController.getSettings() backing oiSettingsPanel is itself
 *              deferred, Backlog UI-8, P1) — a client constant matching the shipped
 *              default (1000) is used instead; the working-set-ceiling check itself is
 *              real and enforced (GraphUI.md §26), only its configured source is
 *              simplified for this MVP. Record analyze mode (ADR-0021) centers on a live,
 *              non-persisted record hierarchy fragment (OI_RecordHierarchyController) —
 *              a parallel path from Object/Field's OI_GraphController, joined back into the
 *              exact same GraphViewState/Canvas rendering once a fragment is in hand.
 */
import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getGraphFragment from '@salesforce/apex/OI_GraphController.getGraphFragment';
import getRecordFragment from '@salesforce/apex/OI_RecordHierarchyController.getRecordFragment';
import getNavigationTarget from '@salesforce/apex/OI_GraphController.getNavigationTarget';
import { getObjectInfos } from 'lightning/uiObjectInfoApi';
import {
    createGraphViewState,
    setCenterFromFragment,
    applyExpand,
    applyCollapse,
    selectNode,
    snapshotNodes,
    snapshotEdges,
    isWorkingSetCeilingHit
} from 'c/graphViewState';
import { loadPresentationRegistry, resolveNodeStyle, resolveEdgeStyle } from 'c/presentationRegistry';
import { parseRecordNodeKey } from 'c/recordNodeKey';
import { createRelationshipFilter, applyRelationshipFilter } from 'c/graphRelationshipFilter';
import { buildObjectRelationshipView } from 'c/objectRelationshipView';
import { navigateToTarget, NAVIGATION_KIND_RECORD } from 'c/metadataNavigation';

const WORKING_SET_CEILING = 1000;
const OBJECT_TYPE_KEY = 'SalesforceMetadata.CustomObject';
const FIELD_TYPE_KEY = 'SalesforceMetadata.CustomField';
const HAS_FIELD_EDGE_TYPE_KEY = 'SalesforceMetadata.HAS_FIELD';

/** themeInfo.iconUrl looks like ".../assets/icons/standard/account_120.png" or ".../custom/custom18_120.png" — this parses it back into the exact <lightning-icon> name ("standard:account"/"custom:custom18") Setup already assigned that object, standard or custom, with no per-object configuration of our own to maintain. */
const OBJECT_ICON_URL_PATTERN = /\/(standard|custom)\/([a-zA-Z0-9_]+?)(?:_\d+)?\.(?:png|svg)(?:[?#].*)?$/i;

function parseObjectIconName(themeInfo) {
    const iconUrl = themeInfo && themeInfo.iconUrl;
    if (!iconUrl) {
        return null;
    }
    const match = OBJECT_ICON_URL_PATTERN.exec(iconUrl);
    return match ? `${match[1]}:${match[2]}` : null;
}

/** Object needs 2 hops to reach both referenced and referencing objects; Field needs only 1 to reach its parent object and any referenced object. Record centering goes through selectAndCenterRecord instead (a different Apex method entirely), not this map. */
const HOP_DEPTH_BY_MODE = { Object: 2, Field: 1 };

export default class OiGraphExplorer extends NavigationMixin(LightningElement) {
    @track viewState = createGraphViewState();
    @track isLoadingFragment = false;
    @track errorMessage = null;
    @track workingSetCeilingHit = false;
    @track analyzeMode = 'Object';
    @track fieldModeObjectKey = null;
    @track fieldModeObjectLabel = null;
    @track fieldModeFieldOptions = [];
    @track isLoadingFieldOptions = false;
    @track recordModeObjectApiName = null;
    @track recordModeObjectLabel = null;
    @track isLoadingRecordModeObject = false;
    @track hiddenEdgeTypes = new Set();
    @track relationshipDirection = 'both';
    @track restrictToDirectOnly = false;
    /** GraphUI.md §42.4 — the connector currently open in oiRelationshipConnectorDetail, Object mode only. Cleared whenever the center changes (resetRelationshipFilter's sibling concern, same lifecycle). */
    @track selectedConnector = null;
    @track selectedConnectorRootObject = null;
    /**
     * VisualDesignSpecification.md §3.1/§3.2: once an object is analyzed, the workspace moves
     * directly from the mode selector to one compact context toolbar — a full-width search row
     * competing with it is exactly the "search hierarchy" gap the current-state assessment calls
     * out (CurrentUIVisualGapAssessment.md, P0 "Overall composition"). Object mode therefore
     * collapses its search bar into oiRelationshipCanvas's own "Analyzing Object" chip once a
     * center exists, surfacing a compact "Change object" affordance instead — mirroring the
     * pattern Field/Record mode's object picker already uses (resetFieldModePicker/
     * resetRecordModePicker) rather than inventing a new interaction. False (search bar showing)
     * whenever there is no center node yet, regardless of this flag.
     */
    @track isObjectSearchOpen = false;

    /**
     * Per-SObject card icon/color, resolved via the platform's own UI API (CLAUDE.md's API
     * Selection Priority ranks UI API above Tooling/REST/SOQL for exactly this kind of read).
     * The Presentation Type Registry (GraphUI.md §20) is deliberately generic per *metadata
     * category* (typeKey) — every Object node shares one typeKey regardless of whether it's
     * Account, Contact, or a customer's own custom object — so without this, every card in
     * Object analyze mode would render the same generic icon. This resolves the other axis
     * (per-object-API-name) entirely client-side via Lightning Data Service, which already
     * knows every org's assigned standard/custom icon and enforces the same FLS/CRUD a user
     * already has — no new Apex surface, no Custom Metadata to maintain per object. Falls back
     * to the registry's generic icon whenever UI API has nothing for an object (unknown object,
     * no assigned icon, or the wire hasn't resolved yet) — never an error, matching §20's
     * unregistered-type contract.
     */
    @track objectIconByApiName = new Map();
    _objectApiNamesCache = [];

    registry = null;
    centerRequestId = 0;
    fieldObjectRequestId = 0;
    recordObjectRequestId = 0;

    connectedCallback() {
        this.loadRegistry();
    }

    async loadRegistry() {
        try {
            this.registry = await loadPresentationRegistry();
        } catch {
            this.registry = null;
        }
    }

    /** The distinct Object-node API names currently in the working set — reference-stable across renders when the set hasn't actually changed, so the getObjectInfos wire below doesn't re-subscribe on every unrelated render. */
    get objectApiNames() {
        const distinct = new Set();
        for (const node of snapshotNodes(this.viewState)) {
            if (node.typeKey === OBJECT_TYPE_KEY && node.secondaryKey) {
                distinct.add(node.secondaryKey);
            }
        }
        const next = [...distinct].sort();
        const prev = this._objectApiNamesCache;
        if (prev.length === next.length && prev.every((value, index) => value === next[index])) {
            return prev;
        }
        this._objectApiNamesCache = next;
        return next;
    }

    @wire(getObjectInfos, { objectApiNames: '$objectApiNames' })
    wiredObjectInfos({ data }) {
        if (!data || !Array.isArray(data.results)) {
            return;
        }
        const next = new Map();
        for (const entry of data.results) {
            const result = entry && entry.result;
            if (!result || !result.apiName) {
                continue;
            }
            const iconName = parseObjectIconName(result.themeInfo);
            if (iconName) {
                next.set(result.apiName, iconName);
            }
        }
        this.objectIconByApiName = next;
    }

    get hasCenterNode() {
        return !!this.viewState.centerNodeKey;
    }

    /**
     * Every currently-loaded node, styled — the full working set, unfiltered by the
     * relationship-view filter (oiFilterPanel/graphRelationshipFilter.js's own job, applied by
     * canvasNodes/canvasEdges below). Memoized by (viewState, registry) reference identity —
     * live-org validation against a heavily-customized Account (a large 2-hop working set even
     * within Max_Canvas_Working_Set__c) showed this matters: this getter, and allCanvasEdges
     * below, are each read from multiple places in one render pass (the canvas's own nodes/edges
     * props, plus objectRelationshipSummary's own derivation) — recomputing the full
     * registry-resolution map() every single time added up to a real, noticeable freeze, not
     * just restated theoretical O(n) cost.
     */
    get allCanvasNodes() {
        if (
            this._allCanvasNodesCache &&
            this._allCanvasNodesCache.viewState === this.viewState &&
            this._allCanvasNodesCache.registry === this.registry &&
            this._allCanvasNodesCache.objectIconByApiName === this.objectIconByApiName
        ) {
            return this._allCanvasNodesCache.value;
        }
        const value = snapshotNodes(this.viewState).map((node) => {
            const style = resolveNodeStyle(this.registry, node.typeKey);
            const perObjectIconName = node.typeKey === OBJECT_TYPE_KEY ? this.objectIconByApiName.get(node.secondaryKey) : null;
            return {
                ...node,
                iconName: perObjectIconName || style.iconName,
                colorToken: style.colorToken,
                typeLabel: style.displayLabel || node.typeKey,
                showFieldList: style.showFieldList
            };
        });
        this._allCanvasNodesCache = { viewState: this.viewState, registry: this.registry, objectIconByApiName: this.objectIconByApiName, value };
        return value;
    }

    /** Every currently-loaded edge, styled — the filter panel's checkbox list is built from this unfiltered set so a hidden type's own checkbox never disappears (a filter that hides its own control could never be turned back on). */
    /**
     * sourceRoleLabel/targetRoleLabel travel through here too, unlike lineStyle/displayLabel
     * which fully REPLACE the registry-blind edge shape: the Canvas needs both role labels (it
     * decides per-edge, per-node which one applies depending on which side is the BFS parent) so
     * it can answer "why is this node here?" without importing the registry itself
     * (container/presentational split, GraphUI.md §3). edge.viaFieldApiName already survives
     * the spread unchanged — it travels with the edge summary from the server and needs no
     * registry resolution.
     */
    get allCanvasEdges() {
        if (this._allCanvasEdgesCache && this._allCanvasEdgesCache.viewState === this.viewState && this._allCanvasEdgesCache.registry === this.registry) {
            return this._allCanvasEdgesCache.value;
        }
        const value = snapshotEdges(this.viewState).map((edge) => {
            const style = resolveEdgeStyle(this.registry, edge.typeKey);
            return {
                ...edge,
                lineStyle: style.lineStyle,
                displayLabel: style.displayLabel || edge.typeKey,
                isFieldMembership: style.isFieldMembership,
                sourceRoleLabel: style.sourceRoleLabel,
                targetRoleLabel: style.targetRoleLabel,
                description: style.description
            };
        });
        this._allCanvasEdgesCache = { viewState: this.viewState, registry: this.registry, value };
        return value;
    }

    /**
     * Object mode's curated Intelligence Panel relationship counts (GraphUI.md §42's Intelligence
     * Panel rebuild) — Self Relationships / Referenced Objects / Referencing Objects are DISTINCT
     * OBJECT counts, which the panel's own getNodeDetail response cannot derive (its
     * incoming/outgoing counts are per-edge-type, not per-distinct-object), so they're computed
     * once here from the same already-fetched working set the canvas itself uses, via the
     * existing objectRelationshipView.js transform — no new fetch. Incoming/Outgoing
     * Lookups/Master-Detail are deliberately NOT recomputed from this same bounded working set
     * even though they could be — the panel already has always-complete counts for those four
     * from OI_RelationshipCounts (server-computed, independent of canvas pagination), and reusing
     * those is both simpler and more robust than trusting the canvas's own working set to be
     * exhaustive. null outside Object mode (or before a center is selected) so the panel can fall
     * back to its existing generic relationship rows for Field/Record.
     */
    get objectRelationshipSummary() {
        if (!this.isObjectMode || !this.hasCenterNode) {
            return null;
        }
        const nodes = this.allCanvasNodes;
        const edges = this.allCanvasEdges;
        const centerNodeKey = this.viewState.centerNodeKey;
        if (
            this._objectRelationshipSummaryCache &&
            this._objectRelationshipSummaryCache.nodes === nodes &&
            this._objectRelationshipSummaryCache.edges === edges &&
            this._objectRelationshipSummaryCache.centerNodeKey === centerNodeKey
        ) {
            return this._objectRelationshipSummaryCache.value;
        }
        const view = buildObjectRelationshipView(nodes, edges, centerNodeKey);
        const value = {
            selfRelationships: view.selfRelationships.length,
            referencedObjects: view.outgoingRelationships.length,
            referencingObjects: view.incomingRelationships.length
        };
        this._objectRelationshipSummaryCache = { nodes, edges, centerNodeKey, value };
        return value;
    }

    /** The active relationship-view filter (GraphUI.md §22, Backlog UI-4) — a directed-BFS-from-center filter (graphRelationshipFilter.js), not a flat "hide this type" pass, so direction/depth compose correctly with multi-hop chains. */
    get relationshipFilter() {
        return { ...createRelationshipFilter(), edgeTypeKeys: this.allowedEdgeTypeKeys, direction: this.relationshipDirection, maxDepth: this.restrictToDirectOnly ? 1 : null };
    }

    get allowedEdgeTypeKeys() {
        const allKnown = new Set(this.allCanvasEdges.map((edge) => edge.typeKey));
        for (const hidden of this.hiddenEdgeTypes) {
            allKnown.delete(hidden);
        }
        return allKnown;
    }

    /**
     * Object mode's default declutter pass: a plain data field (Name, Amount__c,
     * Description__c...) creates no inter-object relationship and is pure noise on a canvas
     * whose job is showing structure, not enumerating every field as a node — oiSchemaObjectCard
     * already moved full field browsing to the Detail Panel's "Show Fields" list for exactly
     * this reason (its own doc comment: "the card no longer lists fields inline"). A field is
     * kept on the canvas only if it is itself the source of some non-HAS_FIELD edge (i.e. it
     * actually creates a relationship, such as a lookup/master-detail reference) — never a
     * hardcoded LOOKUP_TO/MASTER_DETAIL_TO check, so a future relationship-flavored edge type
     * (e.g. a dependency edge) is picked up automatically without touching this method. Field
     * mode is untouched (its whole purpose is browsing one object's own fields). Nothing is
     * dropped from the fetched working set — only from what's rendered by default; the full
     * field list stays one click away via Field mode or the Detail Panel's Show Fields action.
     */
    get relationshipOnlyView() {
        if (!this.isObjectMode) {
            return { nodes: this.allCanvasNodes, edges: this.allCanvasEdges };
        }
        const relationshipFieldKeys = new Set(
            this.allCanvasEdges.filter((edge) => edge.typeKey !== HAS_FIELD_EDGE_TYPE_KEY).map((edge) => edge.sourceNodeKey)
        );
        const prunedFieldKeys = new Set(
            this.allCanvasNodes.filter((node) => node.typeKey === FIELD_TYPE_KEY && !relationshipFieldKeys.has(node.nodeKey)).map((node) => node.nodeKey)
        );
        if (prunedFieldKeys.size === 0) {
            return { nodes: this.allCanvasNodes, edges: this.allCanvasEdges };
        }
        return {
            nodes: this.allCanvasNodes.filter((node) => !prunedFieldKeys.has(node.nodeKey)),
            edges: this.allCanvasEdges.filter((edge) => !prunedFieldKeys.has(edge.sourceNodeKey) && !prunedFieldKeys.has(edge.targetNodeKey))
        };
    }

    /** What actually reaches oiGraphCanvas — the declutter-passed working set (above), then narrowed by the active relationship filter. Purely a client-side rendering concern (§26-style precedent): never touches the real GraphViewState, never re-fetches. */
    get filteredView() {
        const { nodes, edges } = this.relationshipOnlyView;
        return applyRelationshipFilter(nodes, edges, this.viewState.centerNodeKey, this.relationshipFilter);
    }

    get canvasNodes() {
        return this.filteredView.nodes;
    }

    get canvasEdges() {
        return this.filteredView.edges;
    }

    /**
     * The distinct edge types currently loaded, in oiFilterPanel's expected shape — each a
     * togglable checkbox with a one-line description, so the filter panel doubles as the graph's
     * relationship legend (this sprint's requirement) rather than a bare list of raw names a
     * viewer has to already know the meaning of.
     */
    get edgeTypeFilterOptions() {
        const seen = new Map();
        for (const edge of this.allCanvasEdges) {
            if (!seen.has(edge.typeKey)) {
                seen.set(edge.typeKey, {
                    typeKey: edge.typeKey,
                    displayLabel: edge.displayLabel,
                    description: edge.description,
                    isChecked: !this.hiddenEdgeTypes.has(edge.typeKey),
                    swatchClass: 'oi-filter-panel-swatch oi-filter-panel-swatch-' + edge.lineStyle
                });
            }
        }
        return Array.from(seen.values());
    }

    get hasFilterPanel() {
        return this.edgeTypeFilterOptions.length > 0;
    }

    /** Toggles one edge type's inclusion — a pure client-side view concern, exactly like oiGraphCanvas's own cluster-expand toggles; never calls Apex and never touches GraphViewState. */
    handleEdgeTypeToggle(event) {
        const typeKey = event.detail.typeKey;
        const updated = new Set(this.hiddenEdgeTypes);
        if (updated.has(typeKey)) {
            updated.delete(typeKey);
        } else {
            updated.add(typeKey);
        }
        this.hiddenEdgeTypes = updated;
    }

    /** Recomputes the combined direction from the panel's two independent checkboxes — guarded so unchecking both at once (which would filter every relationship out) is a no-op instead of a silently empty graph. */
    handleDirectionToggle(event) {
        const { showParents, showChildren } = event.detail;
        if (!showParents && !showChildren) {
            return;
        }
        this.relationshipDirection = showParents && showChildren ? 'both' : showParents ? 'outgoing' : 'incoming';
    }

    handleDepthToggle(event) {
        this.restrictToDirectOnly = event.detail.restrictToDirectOnly;
    }

    get selectedNodeKey() {
        return this.viewState.selectedNodeKey;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get isObjectMode() {
        return this.analyzeMode === 'Object';
    }

    get isFieldMode() {
        return this.analyzeMode === 'Field';
    }

    get isRecordMode() {
        return this.analyzeMode === 'Record';
    }

    /** ADR-0024: Object and Record analyze mode share the same directional lane canvas (oiRelationshipCanvas) — only Field mode still uses the generic radial canvas (oiGraphCanvas), since it's the one mode genuinely browsing a multi-type neighborhood rather than a single-type directional inventory. */
    get usesRelationshipCanvas() {
        return this.isObjectMode || this.isRecordMode;
    }

    get objectModeButtonClass() {
        return this.analyzeModeButtonClass(this.isObjectMode);
    }

    get fieldModeButtonClass() {
        return this.analyzeModeButtonClass(this.isFieldMode);
    }

    get recordModeButtonClass() {
        return this.analyzeModeButtonClass(this.isRecordMode);
    }

    analyzeModeButtonClass(isActive) {
        return 'oi-analyze-mode-button' + (isActive ? ' is-active' : '');
    }

    /** Field mode's own search step always searches Objects first (§ field-object-scoping fix) — a field is only ever picked from the resulting object's own field list, never searched org-wide by raw text, which is ambiguous across objects that share a field label. */
    get searchTypeKeyFilter() {
        return OBJECT_TYPE_KEY;
    }

    get searchPlaceholder() {
        return this.isFieldMode ? 'First, search for the object this field belongs to (e.g. Account)...' : 'Search objects (e.g., Account, Opportunity...)';
    }

    /** Object mode's own compact-toolbar counterpart to hasFieldModeObject/hasRecordModeObject below — true whenever the full search bar should render, false once a center exists and the user hasn't asked to change it. */
    get shouldShowObjectSearchBar() {
        return !this.hasCenterNode || this.isObjectSearchOpen;
    }

    /** The centered object's own already-styled summary (label/icon), for the compact "Object: <label>" banner replacing the search bar once analyzed — derived from allCanvasNodes, no new fetch. */
    get centerObjectSummary() {
        if (!this.isObjectMode || !this.hasCenterNode) {
            return null;
        }
        return this.allCanvasNodes.find((node) => node.nodeKey === this.viewState.centerNodeKey) || null;
    }

    handleChangeObjectSearch() {
        this.isObjectSearchOpen = true;
    }

    get hasFieldModeObject() {
        return !!this.fieldModeObjectKey;
    }

    get hasFieldModeOptions() {
        return this.fieldModeFieldOptions.length > 0;
    }

    get hasRecordModeObject() {
        return !!this.recordModeObjectApiName;
    }

    get recordSearchPlaceholder() {
        return `Search ${this.recordModeObjectLabel || 'records'}...`;
    }

    handleAnalyzeModeChange(event) {
        const mode = event.currentTarget.dataset.mode;
        if (mode === this.analyzeMode) {
            return;
        }
        this.analyzeMode = mode;
        // Invalidate picker/centering responses started in the previous mode. Without this,
        // a slow Object response can overwrite a newer Field/Record interaction.
        this.centerRequestId++;
        this.fieldObjectRequestId++;
        this.recordObjectRequestId++;
        this.isLoadingFragment = false;
        this.isLoadingFieldOptions = false;
        this.isLoadingRecordModeObject = false;
        this.errorMessage = null;
        this.resetFieldModePicker();
        this.resetRecordModePicker();
        this.isObjectSearchOpen = false;
        this.closeConnectorDetail();
        // A tab switch is a fresh view, not an edit to the old one (GraphUI.md §11's "a new
        // center means a new view" principle, applied here to "a new mode means a new view"):
        // without this, the previous mode's centerNodeKey/nodes/edges/selectedNodeKey stay in
        // viewState (hasCenterNode isn't gated by analyzeMode), so the old graph renders,
        // scattered and disconnected, under the newly-selected tab until the user completes a
        // brand-new search in it.
        this.viewState = createGraphViewState();
        this.workingSetCeilingHit = false;
        this.resetRelationshipFilter();
    }

    handleSearchSelect(event) {
        return this.selectAndCenter(event.detail.nodeKey);
    }

    /** Field mode step 1: the search bar here picks the object, not the field — this only loads that object's own field list (already-known 1-hop data, no new Apex method) for step 2 to pick from. */
    async handleFieldModeObjectSelect(event) {
        const requestId = ++this.fieldObjectRequestId;
        const objectNodeKey = event.detail.nodeKey;
        this.isLoadingFieldOptions = true;
        this.errorMessage = null;
        try {
            const fragment = await getGraphFragment({ nodeKey: objectNodeKey, hopDepth: 1, pageCursor: null, knownChecksums: {} });
            if (requestId !== this.fieldObjectRequestId || !this.isFieldMode) {
                return;
            }
            const objectSummary = (fragment.nodes || []).find((n) => n.nodeKey === objectNodeKey);
            /**
             * Only this object's OWN fields — the outgoing HAS_FIELD edge specifically, in the
             * object->field direction. A 1-hop fragment also contains other objects' lookup/
             * master-detail fields that merely reference this object (e.g. Contact.AccountId
             * pointing at Account) via incoming LOOKUP_TO/MASTER_DETAIL_TO edges; those belong
             * to Contact, not Account, and must never appear in Account's own field picker.
             */
            const ownFieldKeys = new Set(
                (fragment.edges || []).filter((e) => e.typeKey === HAS_FIELD_EDGE_TYPE_KEY && e.sourceNodeKey === objectNodeKey).map((e) => e.targetNodeKey)
            );
            const fieldOptions = (fragment.nodes || [])
                .filter((n) => n.typeKey === FIELD_TYPE_KEY && ownFieldKeys.has(n.nodeKey))
                .map((n) => ({ label: `${n.label} (${n.secondaryKey})`, value: n.nodeKey }))
                .sort((a, b) => a.label.localeCompare(b.label));
            this.fieldModeObjectKey = objectNodeKey;
            this.fieldModeObjectLabel = objectSummary ? objectSummary.label : objectNodeKey;
            this.fieldModeFieldOptions = fieldOptions;
        } catch (error) {
            if (requestId === this.fieldObjectRequestId && this.isFieldMode) {
                this.errorMessage = this.extractErrorMessage(error);
            }
        } finally {
            if (requestId === this.fieldObjectRequestId) {
                this.isLoadingFieldOptions = false;
            }
        }
    }

    /** Field mode step 2: the actual field selection — reuses the same curated center-on-node flow every other mode uses. */
    handleFieldPicked(event) {
        return this.selectAndCenter(event.detail.value);
    }

    handleChangeFieldModeObject() {
        this.resetFieldModePicker();
    }

    resetFieldModePicker() {
        this.fieldModeObjectKey = null;
        this.fieldModeObjectLabel = null;
        this.fieldModeFieldOptions = [];
    }

    /** Record mode step 1: resolve the chosen metadata object node to its real API name (a zero-hop fetch — only the center node's own summary is needed, not its neighbors) so oiRecordPicker can search actual records of that object. */
    async handleRecordModeObjectSelect(event) {
        const requestId = ++this.recordObjectRequestId;
        const objectNodeKey = event.detail.nodeKey;
        this.isLoadingRecordModeObject = true;
        this.errorMessage = null;
        try {
            const fragment = await getGraphFragment({ nodeKey: objectNodeKey, hopDepth: 0, pageCursor: null, knownChecksums: {} });
            if (requestId !== this.recordObjectRequestId || !this.isRecordMode) {
                return;
            }
            const objectSummary = (fragment.nodes || []).find((n) => n.nodeKey === objectNodeKey);
            if (!objectSummary) {
                this.errorMessage = 'No object found for that selection.';
                return;
            }
            this.recordModeObjectApiName = objectSummary.secondaryKey;
            this.recordModeObjectLabel = objectSummary.label;
        } catch (error) {
            if (requestId === this.recordObjectRequestId && this.isRecordMode) {
                this.errorMessage = this.extractErrorMessage(error);
            }
        } finally {
            if (requestId === this.recordObjectRequestId) {
                this.isLoadingRecordModeObject = false;
            }
        }
    }

    /** Record mode step 2: the actual record selection. */
    handleRecordPicked(event) {
        return this.selectAndCenterRecord(this.recordModeObjectApiName, event.detail.recordId);
    }

    handleChangeRecordModeObject() {
        this.resetRecordModePicker();
    }

    resetRecordModePicker() {
        this.recordModeObjectApiName = null;
        this.recordModeObjectLabel = null;
    }

    /** Centers the graph on a live record hierarchy fragment (ADR-0021) — once fetched, it flows through the exact same GraphViewState/Canvas rendering as any metadata fragment; nothing downstream needs to know a record, not scanned metadata, produced it. */
    async selectAndCenterRecord(objectApiName, recordId) {
        const requestId = ++this.centerRequestId;
        this.isLoadingFragment = true;
        this.errorMessage = null;
        try {
            const fragment = await getRecordFragment({ objectApiName, recordId });
            if (requestId !== this.centerRequestId || !this.isRecordMode) {
                return;
            }
            if (!fragment.nodes || fragment.nodes.length === 0) {
                this.errorMessage = 'No record found for that selection.';
                return;
            }
            setCenterFromFragment(this.viewState, fragment);
            this.workingSetCeilingHit = false;
            this.resetRelationshipFilter();
            this.refreshViewState();
        } catch (error) {
            if (requestId === this.centerRequestId) {
                this.errorMessage = this.extractErrorMessage(error);
            }
        } finally {
            if (requestId === this.centerRequestId) {
                this.isLoadingFragment = false;
            }
        }
    }

    handleCanvasSelect(event) {
        selectNode(this.viewState, event.detail.nodeKey);
        this.refreshViewState();
    }

    async handleCanvasOpen(event) {
        const nodeKey = event.detail && event.detail.nodeKey;
        const recordRef = parseRecordNodeKey(nodeKey);
        if (recordRef) {
            navigateToTarget(this, { kind: NAVIGATION_KIND_RECORD, recordId: recordRef.recordId, objectApiName: recordRef.objectApiName });
            return;
        }
        const node = this.allCanvasNodes.find((candidate) => candidate.nodeKey === nodeKey);
        if (!node || !node.typeKey || !node.secondaryKey) {
            this.errorMessage = 'This item cannot be opened directly.';
            return;
        }
        try {
            const target = await getNavigationTarget({ typeKey: node.typeKey, apiName: node.secondaryKey });
            const result = navigateToTarget(this, target);
            if (!result.navigated) {
                this.errorMessage = result.message;
            }
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
        }
    }

    /** A field row picked from the detail panel's field browser — a plain selection exactly like clicking an already-visible canvas node, never a re-center/re-fetch. If the field isn't part of the current working set (not yet expanded into view), it simply won't be highlighted on the canvas; the detail panel itself still resolves it independently via its own getNodeDetail call. */
    handleDetailPanelSelect(event) {
        selectNode(this.viewState, event.detail.nodeKey);
        this.refreshViewState();
    }

    /**
     * "Highlight on Graph" (GraphUI.md §7): the detail panel's already-fetched Impact Analysis
     * subgraph is merged into GraphViewState exactly as an ordinary expand would — the exact
     * same applyExpand call handleExpand itself uses, just fed a fragment the shell never
     * requested via getGraphFragment. This is the concrete unification GraphUI.md §7 mandates:
     * one reference-counting visibility model, never a second one built just for impact
     * results, so collapsing the origin node later correctly retracts these nodes too.
     */
    handleHighlightImpact(event) {
        const { nodeKey, fragment } = event.detail;
        if (!nodeKey || !fragment) {
            return;
        }
        applyExpand(this.viewState, nodeKey, fragment);
        this.workingSetCeilingHit = isWorkingSetCeilingHit(this.viewState, WORKING_SET_CEILING);
        this.refreshViewState();
    }

    async selectAndCenter(nodeKey) {
        const requestId = ++this.centerRequestId;
        this.isLoadingFragment = true;
        this.errorMessage = null;
        try {
            const hopDepth = HOP_DEPTH_BY_MODE[this.analyzeMode] ?? 1;
            const fragment = await getGraphFragment({ nodeKey, hopDepth, pageCursor: null, knownChecksums: {} });
            if (requestId !== this.centerRequestId) {
                return;
            }
            if (!fragment.nodes || fragment.nodes.length === 0) {
                this.errorMessage = 'No node found for that selection.';
                return;
            }
            setCenterFromFragment(this.viewState, fragment);
            this.workingSetCeilingHit = false;
            this.resetRelationshipFilter();
            this.isObjectSearchOpen = false;
            this.refreshViewState();
        } catch (error) {
            if (requestId === this.centerRequestId) {
                this.errorMessage = this.extractErrorMessage(error);
            }
        } finally {
            if (requestId === this.centerRequestId) {
                this.isLoadingFragment = false;
            }
        }
    }

    /** Field mode's own expand affordance — Object and Record mode never emit this event (both moved to oiRelationshipCanvas's "Explore From Here" re-centering instead, ADR-0024), so a nodeKey reaching here is always a metadata nodeKey, never a record one. */
    async handleExpand(event) {
        const nodeKey = event.detail.nodeKey;
        if (isWorkingSetCeilingHit(this.viewState, WORKING_SET_CEILING)) {
            this.workingSetCeilingHit = true;
            return;
        }
        this.isLoadingFragment = true;
        this.errorMessage = null;
        try {
            const fragment = await getGraphFragment({ nodeKey, hopDepth: 1, pageCursor: null, knownChecksums: {} });
            applyExpand(this.viewState, nodeKey, fragment);
            this.workingSetCeilingHit = isWorkingSetCeilingHit(this.viewState, WORKING_SET_CEILING);
            this.refreshViewState();
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
        } finally {
            this.isLoadingFragment = false;
        }
    }

    handleCollapse(event) {
        applyCollapse(this.viewState, event.detail.nodeKey);
        this.workingSetCeilingHit = false;
        this.refreshViewState();
    }

    /** LWC does not deep-track Map/Set mutations inside a @track field — a new top-level reference is required to force a re-render after any graphViewState.js mutation. */
    refreshViewState() {
        this.viewState = { ...this.viewState };
    }

    /** A fresh center is a fresh view (GraphUI.md §11) — the relationship filter is a view concern scoped to the current exploration, not a sticky global preference, so it resets exactly when GraphViewState itself is fully replaced (never on expand/collapse, which keep the same center). */
    resetRelationshipFilter() {
        this.hiddenEdgeTypes = new Set();
        this.relationshipDirection = 'both';
        this.restrictToDirectOnly = false;
        this.closeConnectorDetail();
    }

    /**
     * oiRelationshipCanvas's "Explore From Here" (GraphUI.md §42.5, ADR-0024) — a neighbor
     * card's own action to re-center on it, shared by both Object and Record mode since both
     * render that same canvas. A full view replacement, identical to a fresh search selection,
     * not a partial rewind — the same semantics §23's breadcrumb re-centering already
     * established. Record mode's counterpart cards carry record nodeKeys, not metadata ones, so
     * re-centering there must go through selectAndCenterRecord (a different Apex method
     * entirely) rather than selectAndCenter — the nodeKey format alone (c/recordNodeKey) is
     * what distinguishes the two, exactly as handleExpand used to before Record mode moved off
     * oiGraphCanvas.
     */
    handleExploreFromHere(event) {
        const nodeKey = event.detail.nodeKey;
        const recordRef = parseRecordNodeKey(nodeKey);
        if (recordRef) {
            return this.selectAndCenterRecord(recordRef.objectApiName, recordRef.recordId);
        }
        return this.selectAndCenter(nodeKey);
    }

    /** Object canvas connector click (GraphUI.md §42.4) — opens oiRelationshipConnectorDetail with the descriptor the canvas already computed; no new fetch. */
    handleObjectCanvasEdgeClick(event) {
        this.selectedConnector = event.detail.connector;
        this.selectedConnectorRootObject = event.detail.rootObject;
    }

    handleConnectorDetailClose() {
        this.closeConnectorDetail();
    }

    closeConnectorDetail() {
        this.selectedConnector = null;
        this.selectedConnectorRootObject = null;
    }

    extractErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return 'Something went wrong. Please try again.';
    }
}
