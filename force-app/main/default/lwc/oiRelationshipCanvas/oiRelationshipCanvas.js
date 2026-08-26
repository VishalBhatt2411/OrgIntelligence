/**
 * Purpose: The presentational directional-lane relationship canvas (GraphUI.md §42, ADR-0023;
 *          generalized to Record analyze mode by ADR-0024) — shared by Object and Record analyze
 *          mode's own directional lane layout, rendered as a real SVG diagram: counterparts
 *          referencing the center on the left, the centered entity fixed in the middle,
 *          counterparts the center references on the right, self-relationships below, all
 *          joined by actual connector lines carrying their own field/relationship-type label.
 *          Never calls Apex, never touches oiGraphCanvas's radial layout or its Field-mode
 *          rendering path (Field mode is the one remaining analyze mode that still needs a
 *          general, multi-type egocentric neighborhood view, not this single-type directional
 *          inventory — ADR-0023/ADR-0024 both leave it untouched).
 * Responsibilities: Derive the lane model via c/objectRelationshipView (Object mode) or
 *                    c/recordRelationshipView (Record mode, selected by the `mode` prop) from
 *                    already-fetched props; compute a deterministic org-chart-style coordinate
 *                    layout (fixed card geometry, per-lane vertical centering, a shared vertical
 *                    "trunk" per lane so N converging/diverging connectors stay orthogonal and
 *                    non-crossing); render neighbor/center/self cards as SVG foreignObject HTML,
 *                    connectors as SVG paths with an arrowhead marker and a label attached to the
 *                    line; apply the Business/System/All relationship-visibility toggle (Object
 *                    mode only — Record mode's fragment carries no field-level detail to classify
 *                    System vs. Business by, so the toggle is hidden rather than offered and left
 *                    non-functional, see showVisibilityToggle); bound each lane to a small,
 *                    deterministic initial set with a client-only "show more" reveal; emit
 *                    select/explorefromhere/edgeclick.
 * Dependencies: c/objectRelationshipView, c/recordRelationshipView (pure transforms, no Apex).
 * Limitations: Deterministic lane layout only — no force-relaxation pass. The "trunk"
 *              convergence is a deliberate visual simplification for several relationships
 *              pointing at one center — each branch still carries its own label, only the final
 *              approach into the center card is shared. Record mode's connectors carry no
 *              fields[] breakdown (c/recordRelationshipView's own limitation) — the connector
 *              label and oiRelationshipConnectorDetail both degrade gracefully to a fieldless
 *              "Related Record" reading rather than assuming a field is always present.
 * Known platform quirk, mirrored from oiGraphCanvas.js (see that file's own doc comment for the
 *              full explanation): viewBox/markerWidth/markerHeight must be written in the
 *              template with exact SVG camelCase (never hyphenated/lowercased); refX/refY
 *              cannot be written as template markup at all (LWC's attribute validator rejects
 *              any name ending outside [a-z0-9]) and are set imperatively in renderedCallback;
 *              the arrow marker's id is patched imperatively too, since LWC's synthetic shadow
 *              renderer suffixes literal ids per instance and a template-level marker-end="url(#...)"
 *              can never track that suffix on its own.
 */
import { LightningElement, api, track } from 'lwc';
import { buildObjectRelationshipView, DEFAULT_VISIBLE_PER_LANE } from 'c/objectRelationshipView';
import { buildRecordRelationshipView } from 'c/recordRelationshipView';

const MODE_RECORD = 'Record';

const VISIBILITY_BUSINESS = 'business';
const VISIBILITY_SYSTEM = 'system';
const VISIBILITY_ALL = 'all';

const MIN_ZOOM = 0.5;
const MAX_ZOOM = 2;
const ZOOM_STEP = 0.1;
const VIEW_OPTION_CHOICES = [
    { value: 'fit', label: 'Fit to Screen' },
    { value: '50', label: '50%' },
    { value: '75', label: '75%' },
    { value: '100', label: '100%' },
    { value: '125', label: '125%' },
    { value: '150', label: '150%' }
];

function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
}

/** VisualDesignSpecification.md §5's card contract targets ~236x80 for neighbor cards; matched exactly here (rather than the previous 225x68) now that each card also carries its own divider + relationship-field footer row (see buildIncomingEntry/buildOutgoingEntry and the template's .oi-orc-card-footer), which needs the extra height to avoid crowding. */
const CARD_WIDTH = 236;
const CARD_HEIGHT = 80;
/** CENTER_WIDTH stays wider than the reference's ~160px: real object labels ("Opportunity"), the type caption, and the "Analyzing" status pill routinely need more room than that at real org data volumes — VisualDesignSpecification.md §9's own tolerance ("card/control dimensions within 4px unless dynamic text requires more width") anticipates exactly this. CENTER_HEIGHT is matched exactly (185 -> 196). */
const CENTER_WIDTH = 210;
const CENTER_HEIGHT = 196;
const ROW_GAP = 26;
const ROW_HEIGHT = CARD_HEIGHT + ROW_GAP;
const MARGIN_X = 24;
const TOP_MARGIN = 30;
const SELF_CARD_WIDTH = 190;
const SELF_CARD_HEIGHT = 62;
const SELF_CAPTION_HEIGHT = 42;
const SELF_ENTRY_GAP = 22;
const SELF_ENTRY_HEIGHT = SELF_CAPTION_HEIGHT + SELF_CARD_HEIGHT + SELF_ENTRY_GAP;

/**
 * The card-to-trunk segment (where a connector's own label sits) used to be a fixed 150/2=75px
 * regardless of what the label actually said — live-org verification (a real Account with
 * several multi-field connectors, e.g. "3 Lookup Relationships") showed labels routinely wider
 * than that, so the label's own opaque background visually cut across the vertical trunk line
 * it should have stopped well short of, instead of sitting cleanly within its own segment the
 * way the reference design does. LABEL_SEGMENT_MIN is the old fixed value, kept as the floor for
 * short labels; LABEL_SEGMENT_MAX caps how far one unusually long label can stretch the whole
 * lane before CSS truncation (see .oi-orc-connector-label's max-width) takes over instead.
 * FINAL_SEGMENT is the old TRUNK_GAP/2's *other* half — the unlabeled trunk-to-center approach —
 * which never needed to grow, since nothing is ever drawn on it.
 */
const LABEL_SEGMENT_MIN = 75;
const LABEL_SEGMENT_MAX = 260;
const LABEL_H_PADDING = 28;
const FINAL_SEGMENT = 75;
/** A deliberately generous estimate for the connector label's 0.72rem semibold font. Keeping layout geometry independent of Canvas APIs makes it deterministic in Lightning, Jest, and hardened browser contexts; CSS truncation remains the final safety net for unusually wide glyphs. */
const FALLBACK_CHAR_WIDTH = 7;

function measureLabelWidth(text) {
    return (text || '').length * FALLBACK_CHAR_WIDTH;
}

/** The connector's own label text (extracted from decorateConnector so the label-segment-width computation below can measure it before full decoration happens — see that method's own doc comment for what each branch means). */
function buildConnectorLabelText(connector) {
    const hasFieldDetail = connector.fields.length > 0 && !!connector.fields[0].fieldApiName;
    const relationshipTypeLabel = connector.relationshipTypeLabel || (connector.primaryRelationshipType === 'MasterDetail' ? 'Master-Detail' : 'Lookup');
    let connectorLabel;
    if (hasFieldDetail) {
        connectorLabel = connector.relationshipCount > 1 ? `${connector.relationshipCount} ${relationshipTypeLabel} Relationships` : `${connector.fields[0].fieldApiName} · ${relationshipTypeLabel}`;
    } else {
        connectorLabel = connector.relationshipCount > 1 ? `${connector.relationshipCount} ${relationshipTypeLabel}` : relationshipTypeLabel;
    }
    return { connectorLabel, relationshipTypeLabel };
}

/** The card-to-trunk segment length this lane needs so its widest label fits entirely within its own segment — never spilling across the trunk line the way a fixed-width gap would for a long label. Deterministic given the same connector set (§"Deterministic SVG diagram geometry" — canvas measureText has no randomness), so this stays consistent with the rest of this file's no-force-relaxation layout philosophy. */
function computeLabelSegment(connectors) {
    let maxWidth = 0;
    for (const connector of connectors) {
        const { connectorLabel } = buildConnectorLabelText(connector);
        const width = measureLabelWidth(connectorLabel);
        if (width > maxWidth) {
            maxWidth = width;
        }
    }
    return clamp(maxWidth + LABEL_H_PADDING, LABEL_SEGMENT_MIN, LABEL_SEGMENT_MAX);
}

export default class OiRelationshipCanvas extends LightningElement {
    @api nodes = [];
    @api edges = [];
    /** 'Object' (default) or 'Record' — selects both the presentation transform (below) and every mode-aware label/affordance in this file. Field mode never renders this component (oiGraphExplorer.html gates it to Object/Record only). */
    @api mode = 'Object';

    @track visibilityMode = VISIBILITY_BUSINESS;
    @track showAllIncoming = false;
    @track showAllOutgoing = false;
    @track hoveredConnectorKey = null;
    @track selectedConnectorKey = null;
    /** View controls (toolbar "View Options" + floating zoom controls) — presentation-only, client-side state; never affects the fetched working set or the deterministic diagram/lane geometry itself, only how it's scaled/framed on screen. */
    @track zoomLevel = 1;
    @track viewOptionMode = 'fit';
    @track isViewOptionsOpen = false;
    @track isMaximized = false;
    /** Export state — see handleExportDiagram's doc comment for why this goes through a template-declared anchor rather than a `document.createElement`'d one. */
    @track exportHref = null;
    exportFileName = 'relationships.svg';

    _centerNodeKey;
    _handleDocumentClick;
    _pendingExportClick = false;

    /**
     * A fresh center is a fresh view (GraphUI.md §11's principle, already applied to the radial
     * canvas's own relationship filter by oiGraphExplorer.js's resetRelationshipFilter) — the
     * Business/System/All toggle, show-more reveals, and hover/select emphasis are all scoped to
     * whichever object is currently centered, never carried over from the previous one. The
     * zoom/view-option state resets the same way, since "Fit to Screen" for the previous object's
     * diagram bounds has no meaning for a differently-shaped new one; isMaximized is deliberately
     * left untouched, since staying in a maximized canvas while navigating between objects is a
     * user preference about screen real estate, not something tied to any one diagram.
     */
    @api
    get centerNodeKey() {
        return this._centerNodeKey;
    }

    set centerNodeKey(value) {
        if (value === this._centerNodeKey) {
            return;
        }
        this._centerNodeKey = value;
        this.visibilityMode = VISIBILITY_BUSINESS;
        this.showAllIncoming = false;
        this.showAllOutgoing = false;
        this.hoveredConnectorKey = null;
        this.selectedConnectorKey = null;
        this.zoomLevel = 1;
        this.viewOptionMode = 'fit';
        this.isViewOptionsOpen = false;
    }

    connectedCallback() {
        this._handleDocumentClick = (event) => {
            if (!this.isViewOptionsOpen) {
                return;
            }
            const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
            const trigger = this.template.querySelector('[data-id="view-options-trigger"]');
            const menu = this.template.querySelector('[data-id="view-options-menu"]');
            if ((trigger && path.includes(trigger)) || (menu && path.includes(menu))) {
                return;
            }
            this.isViewOptionsOpen = false;
        };
        document.addEventListener('click', this._handleDocumentClick);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this._handleDocumentClick);
        if (this.exportHref) {
            URL.revokeObjectURL(this.exportHref);
        }
    }

    renderedCallback() {
        this.syncSvgDefReferences();
        if (this._pendingExportClick) {
            this._pendingExportClick = false;
            const link = this.template.querySelector('[data-id="export-link"]');
            if (link) {
                link.click();
            }
        }
    }

    /**
     * Memoized by reference identity on (nodes, edges, centerNodeKey) — live-org validation
     * against a heavily-customized Account (hundreds of fields/relationships within its own
     * 2-hop working set, well short of Max_Canvas_Working_Set__c but still substantial) showed
     * this matters in practice: the template references `diagram` (which itself reads `view`)
     * from well over a dozen distinct bindings, and without memoization every one of them re-ran
     * this O(n) transform over the full working set in the same render pass — quadratic-feeling
     * in practice even though each individual call is linear. oiGraphExplorer.js's own
     * allCanvasNodes/allCanvasEdges getters recompute a fresh array reference only once per
     * actual data change (each render pass sees the same reference for its duration), so
     * reference equality here is a correct and cheap cache key, not an approximation.
     */
    get view() {
        if (
            this._viewCache &&
            this._viewCache.nodes === this.nodes &&
            this._viewCache.edges === this.edges &&
            this._viewCache.centerNodeKey === this.centerNodeKey &&
            this._viewCache.mode === this.mode
        ) {
            return this._viewCache.value;
        }
        const value = this.isRecordMode
            ? buildRecordRelationshipView(this.nodes, this.edges, this.centerNodeKey)
            : buildObjectRelationshipView(this.nodes, this.edges, this.centerNodeKey);
        this._viewCache = { nodes: this.nodes, edges: this.edges, centerNodeKey: this.centerNodeKey, mode: this.mode, value };
        return value;
    }

    get isRecordMode() {
        return this.mode === MODE_RECORD;
    }

    get diagramViewBox() {
        const d = this.diagram;
        return `0 0 ${d.canvasWidth} ${d.canvasHeight}`;
    }


    get rootObject() {
        return this.view.rootObject;
    }

    get hasRootObject() {
        return !!this.rootObject;
    }

    get rootObjectTypeLabel() {
        if (!this.rootObject) {
            return '';
        }
        return this.isRecordMode ? `${this.rootObject.secondaryKey} Record` : this.rootObject.isCustom ? 'Custom Object' : 'Standard Object';
    }

    get rootObjectAriaLabel() {
        if (!this.rootObject) {
            return '';
        }
        return `${this.rootObject.label}, ${this.rootObjectTypeLabel}, currently analyzed`;
    }

    get analyzingObjectSubtitle() {
        return this.rootObject ? this.rootObjectTypeLabel : '';
    }

    /** "Analyzing Object" vs "Analyzing Record" — the toolbar chip's own caption, mode-aware. */
    get analyzingLabel() {
        return this.isRecordMode ? 'Analyzing Record' : 'Analyzing Object';
    }

    get incomingLaneTitle() {
        return this.isRecordMode ? 'Records Referencing This Record' : 'Objects Referencing This Object';
    }

    get outgoingLaneTitle() {
        return this.isRecordMode ? 'Records This Record References' : 'Objects This Object References';
    }

    get incomingLaneInfoText() {
        return this.isRecordMode ? 'Records with a lookup pointing to this record, and child records related to it' : 'Objects with a Lookup or Master-Detail field pointing to this object';
    }

    get outgoingLaneInfoText() {
        return this.isRecordMode ? 'Records this record looks up to, or is a child of' : 'Fields on this object that look up or master-detail to another object';
    }

    /** Object mode's Business/System/All toggle needs field-level detail c/recordRelationshipView cannot supply (no originating field on a record edge, see that module's own Limitations) — hidden rather than offered non-functional in Record mode; filterByVisibility bypasses filtering entirely there so every fetched relationship still renders. */
    get showVisibilityToggle() {
        return !this.isRecordMode;
    }

    get incomingEmptyMessage() {
        return this.isRecordMode ? 'No records reference this record.' : 'No objects reference this object.';
    }

    get outgoingEmptyMessage() {
        return this.isRecordMode ? 'This record has no parent lookups or child records.' : 'This object references no other objects.';
    }

    get hostClass() {
        return 'oi-orc' + (this.isMaximized ? ' oi-orc-is-maximized' : '');
    }

    // --- View Options (zoom + fit-to-screen + maximize + export — toolbar/canvas chrome only, never a data fetch) ---

    get zoomPercentLabel() {
        return `${Math.round(this.zoomLevel * 100)}%`;
    }

    /**
     * Zoom is applied by scaling the SVG's own rendered width/height (viewBox stays fixed at
     * the diagram's true coordinate space, §"Deterministic SVG diagram geometry") rather than
     * a CSS `transform: scale()` on top of an unscaled element — a CSS transform changes only
     * paint, never the element's layout box, so the diagram-wrapper's scrollable area (and the
     * space it reserves below the fold for the self-relationship lane, which sits below the
     * main diagram in the same coordinate space) stayed at the full unscaled size regardless of
     * zoom, leaving a large dead zone around the visually-shrunk diagram at low zoom and making
     * the self-relationship cards look disconnected/far away. Scaling width/height directly
     * shrinks the actual layout box in lockstep with the visual content, exactly like resizing
     * a raster image — no dead space at any zoom level.
     */
    get svgRenderWidth() {
        return Math.round(this.diagram.canvasWidth * this.zoomLevel);
    }

    get svgRenderHeight() {
        return Math.round(this.diagram.canvasHeight * this.zoomLevel);
    }

    get viewOptionsLabel() {
        if (this.viewOptionMode === 'custom') {
            return this.zoomPercentLabel;
        }
        const match = VIEW_OPTION_CHOICES.find((choice) => choice.value === this.viewOptionMode);
        return match ? match.label : 'Fit to Screen';
    }

    get viewOptionChoices() {
        return VIEW_OPTION_CHOICES.map((choice) => ({
            ...choice,
            buttonClass: 'oi-orc-view-options-item' + (this.viewOptionMode === choice.value ? ' is-active' : '')
        }));
    }

    handleToggleViewOptions(event) {
        event.stopPropagation();
        this.isViewOptionsOpen = !this.isViewOptionsOpen;
    }

    handleSelectViewOption(event) {
        const value = event.currentTarget.dataset.option;
        this.isViewOptionsOpen = false;
        if (value === 'fit') {
            this.applyFitToScreen();
            return;
        }
        this.viewOptionMode = value;
        this.zoomLevel = Number(value) / 100;
    }

    /**
     * Measures the diagram wrapper's actual rendered box against the deterministic diagram's own
     * canvasWidth/canvasHeight (§ "Deterministic SVG diagram geometry" below) and picks the
     * largest scale that keeps the whole diagram inside it — a real fit computation, not a fixed
     * "reset to 100%" standing in for one.
     */
    applyFitToScreen() {
        this.viewOptionMode = 'fit';
        const wrapper = this.template.querySelector('[data-id="diagram-wrapper"]');
        const d = this.diagram;
        if (!wrapper || !d.canvasWidth || !d.canvasHeight) {
            this.zoomLevel = 1;
            return;
        }
        const rect = wrapper.getBoundingClientRect();
        if (!rect.width || !rect.height) {
            this.zoomLevel = 1;
            return;
        }
        const scale = Math.min(rect.width / d.canvasWidth, rect.height / d.canvasHeight);
        this.zoomLevel = clamp(Math.round(scale * 100) / 100, MIN_ZOOM, MAX_ZOOM);
    }

    handleFitToScreen() {
        this.applyFitToScreen();
    }

    handleZoomIn() {
        this.viewOptionMode = 'custom';
        this.zoomLevel = clamp(Math.round((this.zoomLevel + ZOOM_STEP) * 100) / 100, MIN_ZOOM, MAX_ZOOM);
    }

    handleZoomOut() {
        this.viewOptionMode = 'custom';
        this.zoomLevel = clamp(Math.round((this.zoomLevel - ZOOM_STEP) * 100) / 100, MIN_ZOOM, MAX_ZOOM);
    }

    handleZoomReset() {
        this.viewOptionMode = '100';
        this.zoomLevel = 1;
    }

    handleToggleMaximize() {
        this.isMaximized = !this.isMaximized;
    }

    get maximizeIconName() {
        return this.isMaximized ? 'utility:contract' : 'utility:expand_alt';
    }

    get maximizeButtonLabel() {
        return this.isMaximized ? 'Restore canvas size' : 'Maximize canvas';
    }

    /**
     * Client-side export — the already-rendered SVG is serialized and offered as a download,
     * exactly the data the user is already looking at, no server round-trip. Deliberately clicks
     * a real anchor DECLARED IN THIS COMPONENT'S OWN TEMPLATE (visually hidden, never a
     * `document.createElement`'d element attached/clicked out-of-band) — Lightning Web Security's
     * DOM isolation blocks a component from creating a detached element and appending/clicking it
     * against the global document (verified against a real deploy: that pattern throws there even
     * though it works in a plain, non-Lightning page); an anchor that is genuinely part of the
     * component's own shadow tree stays inside LWS's expected boundary, which is the documented
     * safe pattern for a client-side file export/download from inside an LWC.
     */
    handleExportDiagram() {
        const svg = this.template.querySelector('[data-id="orc-svg"]');
        if (!svg) {
            return;
        }
        if (this.exportHref) {
            URL.revokeObjectURL(this.exportHref);
        }
        const clone = svg.cloneNode(true);
        clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
        const source = new XMLSerializer().serializeToString(clone);
        /**
         * Lightning Web Security wraps Blob and validates its MIME type against a fixed allow-list.
         * "image/svg+xml" is on it, but only as a SANITIZED type — LWS runs its content through an
         * SVG sanitizer that scrutinizes (and can reject) exactly the constructs this diagram's SVG
         * legitimately uses: <foreignObject> islands of real HTML (the neighbor/center cards,
         * buttons, <lightning-icon>) are indistinguishable, to a conservative sanitizer, from the
         * classic SVG-based XSS vector they're built to catch. That throws under LWS on a real
         * deploy to this org, even with no charset parameter. "application/octet-stream" is on the
         * allow-list as an UNSANITIZED type — the correct choice here, since this is the app's own
         * already-rendered markup being exported, not third-party content that needs scrubbing —
         * and it doesn't change what file the user ends up with: the browser's Save dialog and the
         * OS both name/open the downloaded file by the anchor's own `download` filename (".svg"),
         * not by this Blob's MIME type.
         */
        const blob = new Blob([source], { type: 'application/octet-stream' });
        const fileSafeLabel = (this.rootObject ? this.rootObject.label : 'object').replace(/[^a-z0-9-_]+/gi, '-');
        this.exportFileName = `${fileSafeLabel}-relationships.svg`;
        this.exportHref = URL.createObjectURL(blob);
        this._pendingExportClick = true;
    }

    // --- Visibility toggle (Business / System / All — GraphUI.md §42.3) ---

    get isBusinessMode() {
        return this.visibilityMode === VISIBILITY_BUSINESS;
    }

    get isSystemMode() {
        return this.visibilityMode === VISIBILITY_SYSTEM;
    }

    get isAllMode() {
        return this.visibilityMode === VISIBILITY_ALL;
    }

    get businessToggleClass() {
        return this.toggleButtonClass(this.isBusinessMode);
    }

    get systemToggleClass() {
        return this.toggleButtonClass(this.isSystemMode);
    }

    get allToggleClass() {
        return this.toggleButtonClass(this.isAllMode);
    }

    toggleButtonClass(isActive) {
        return 'oi-orc-visibility-toggle' + (isActive ? ' is-active' : '');
    }

    handleVisibilityChange(event) {
        this.visibilityMode = event.currentTarget.dataset.mode;
    }

    filterByVisibility(connectors) {
        if (this.isRecordMode || this.visibilityMode === VISIBILITY_ALL) {
            return connectors;
        }
        if (this.visibilityMode === VISIBILITY_SYSTEM) {
            return connectors.filter((connector) => connector.isSystemRelationship);
        }
        return connectors.filter((connector) => !connector.isSystemRelationship);
    }

    get filteredIncoming() {
        return this.filterByVisibility(this.view.incomingRelationships);
    }

    get filteredOutgoing() {
        return this.filterByVisibility(this.view.outgoingRelationships);
    }

    get filteredSelf() {
        return this.filterByVisibility(this.view.selfRelationships);
    }

    get boundedIncoming() {
        return this.boundLane(this.filteredIncoming, this.showAllIncoming);
    }

    get boundedOutgoing() {
        return this.boundLane(this.filteredOutgoing, this.showAllOutgoing);
    }

    get hasIncoming() {
        return this.filteredIncoming.length > 0;
    }

    get hasOutgoing() {
        return this.filteredOutgoing.length > 0;
    }

    /** Whether Business mode specifically is the reason the outgoing lane reads empty — the honest, actionable empty state (item 10) offers "Show system relationships" only when that's genuinely the cause, never when there truly are none at all. */
    get isOutgoingEmptyByBusinessFilter() {
        return !this.hasOutgoing && this.isBusinessMode && this.view.outgoingRelationships.length > 0;
    }

    get incomingRemainingCount() {
        return Math.max(0, this.filteredIncoming.length - DEFAULT_VISIBLE_PER_LANE);
    }

    get outgoingRemainingCount() {
        return Math.max(0, this.filteredOutgoing.length - DEFAULT_VISIBLE_PER_LANE);
    }

    get hasMoreIncoming() {
        return !this.showAllIncoming && this.incomingRemainingCount > 0;
    }

    get hasMoreOutgoing() {
        return !this.showAllOutgoing && this.outgoingRemainingCount > 0;
    }

    get showMoreIncomingLabel() {
        return `+ Show ${this.incomingRemainingCount} more`;
    }

    get showMoreOutgoingLabel() {
        return `+ Show ${this.outgoingRemainingCount} more`;
    }

    boundLane(connectors, showAll) {
        return showAll ? connectors : connectors.slice(0, DEFAULT_VISIBLE_PER_LANE);
    }

    handleShowMoreIncoming(event) {
        event.stopPropagation();
        this.showAllIncoming = true;
    }

    handleShowMoreOutgoing(event) {
        event.stopPropagation();
        this.showAllOutgoing = true;
    }

    // --- Deterministic SVG diagram geometry ---

    /**
     * The whole diagram's coordinate layout, recomputed from the current (filtered, bounded)
     * lane contents — fixed card geometry and a per-lane vertical-centering formula, never a
     * force/random layout. An "org-chart trunk" per lane: each row branches horizontally off
     * its own card into a shared vertical trunk, which makes one final horizontal approach into
     * the center card — this keeps routing orthogonal and non-crossing regardless of how many
     * rows converge, while every branch still carries its own label.
     */
    get diagram() {
        const incoming = this.boundedIncoming;
        const outgoing = this.boundedOutgoing;
        const self = this.filteredSelf;
        /** Each lane reserves one extra row for its own "+ Show N more" affordance when there's a hidden remainder — it lives in the lane's own column, never as a floating control outside the composition. */
        const incomingRowSlots = incoming.length + (this.hasMoreIncoming ? 1 : 0);
        const outgoingRowSlots = outgoing.length + (this.hasMoreOutgoing ? 1 : 0);
        const rowCount = Math.max(incomingRowSlots, outgoingRowSlots, 1);
        const laneContentHeight = rowCount * ROW_HEIGHT - ROW_GAP;
        const bodyHeight = Math.max(laneContentHeight, CENTER_HEIGHT);
        const diagramHeight = TOP_MARGIN * 2 + bodyHeight;
        const centerY = TOP_MARGIN + bodyHeight / 2;

        /** Sized to each lane's own widest label (see computeLabelSegment's doc comment) — never a fixed constant, so a long "N Lookup Relationships" connector gets the room it needs instead of visually spilling across the trunk line. */
        const incomingLabelSegment = computeLabelSegment(incoming);
        const outgoingLabelSegment = computeLabelSegment(outgoing);

        const canvasWidth = MARGIN_X * 2 + CARD_WIDTH * 2 + incomingLabelSegment + outgoingLabelSegment + FINAL_SEGMENT * 2 + CENTER_WIDTH;
        const centerX = MARGIN_X + CARD_WIDTH + incomingLabelSegment + FINAL_SEGMENT;
        const incomingCardX = MARGIN_X;
        const outgoingCardX = canvasWidth - MARGIN_X - CARD_WIDTH;
        const incomingTrunkX = incomingCardX + CARD_WIDTH + incomingLabelSegment;
        const outgoingTrunkX = outgoingCardX - outgoingLabelSegment;
        const centerLeftX = centerX;
        const centerRightX = centerX + CENTER_WIDTH;
        const centerBottomY = centerY + CENTER_HEIGHT / 2;

        const selfHeight = self.length > 0 ? self.length * SELF_ENTRY_HEIGHT + 20 : 0;
        const canvasHeight = diagramHeight + selfHeight;

        const incomingCards = incoming.map((connector, index) => {
            const rowY = this.laneRowCenterY(index, incomingRowSlots, bodyHeight, TOP_MARGIN);
            return this.buildIncomingEntry(connector, index, rowY, incomingCardX, incomingTrunkX);
        });
        const outgoingCards = outgoing.map((connector, index) => {
            const rowY = this.laneRowCenterY(index, outgoingRowSlots, bodyHeight, TOP_MARGIN);
            return this.buildOutgoingEntry(connector, index, rowY, outgoingCardX, outgoingTrunkX);
        });

        const incomingShowMore = this.hasMoreIncoming
            ? this.buildShowMoreEntry(this.laneRowCenterY(incoming.length, incomingRowSlots, bodyHeight, TOP_MARGIN), incomingCardX, this.showMoreIncomingLabel)
            : null;
        const outgoingShowMore = this.hasMoreOutgoing
            ? this.buildShowMoreEntry(this.laneRowCenterY(outgoing.length, outgoingRowSlots, bodyHeight, TOP_MARGIN), outgoingCardX, this.showMoreOutgoingLabel)
            : null;

        const incomingTrunkPath = this.buildTrunkPath(incomingTrunkX, incomingCards, centerY);
        const outgoingTrunkPath = this.buildTrunkPath(outgoingTrunkX, outgoingCards, centerY);
        const incomingFinalPath = incoming.length > 0 ? `M ${incomingTrunkX} ${centerY} H ${centerLeftX}` : null;
        const outgoingFinalPath = outgoing.length > 0 ? `M ${centerRightX} ${centerY} H ${outgoingTrunkX}` : null;

        const selfEntries = self.map((connector, index) => this.buildSelfEntry(connector, index, centerX, centerBottomY, diagramHeight));

        const activeCard = [...incomingCards, ...outgoingCards].find((card) => card.connectorKey === this.selectedConnectorKey) || null;
        const exploreAction = activeCard
            ? {
                  x: activeCard.x,
                  y: activeCard.y + activeCard.height + 6,
                  width: activeCard.width,
                  height: 24,
                  nodeKey: activeCard.counterpartObject.nodeKey
              }
            : null;

        return {
            canvasWidth,
            canvasHeight,
            centerBox: { x: centerX, y: centerY - CENTER_HEIGHT / 2, width: CENTER_WIDTH, height: CENTER_HEIGHT },
            incomingCards,
            outgoingCards,
            incomingShowMore,
            outgoingShowMore,
            incomingTrunkPath,
            outgoingTrunkPath,
            incomingFinalPath,
            outgoingFinalPath,
            selfEntries,
            exploreAction
        };
    }

    buildShowMoreEntry(rowY, cardX, label) {
        return { x: cardX, y: rowY - CARD_HEIGHT / 2, width: CARD_WIDTH, height: CARD_HEIGHT, label };
    }

    laneRowCenterY(index, count, bodyHeight, topMargin) {
        const contentHeight = count * ROW_HEIGHT - ROW_GAP;
        const offset = topMargin + (bodyHeight - contentHeight) / 2;
        return offset + index * ROW_HEIGHT + CARD_HEIGHT / 2;
    }

    buildIncomingEntry(connector, index, rowY, cardX, trunkX) {
        const decorated = this.decorateConnector(connector, 'incoming', index);
        const branchPath = `M ${cardX + CARD_WIDTH} ${rowY} H ${trunkX}`;
        return {
            ...decorated,
            x: cardX,
            y: rowY - CARD_HEIGHT / 2,
            width: CARD_WIDTH,
            height: CARD_HEIGHT,
            rowY,
            branchPath,
            labelX: cardX + CARD_WIDTH + 8,
            labelY: rowY - 9
        };
    }

    buildOutgoingEntry(connector, index, rowY, cardX, trunkX) {
        const decorated = this.decorateConnector(connector, 'outgoing', index);
        const branchPath = `M ${trunkX} ${rowY} H ${cardX}`;
        return {
            ...decorated,
            x: cardX,
            y: rowY - CARD_HEIGHT / 2,
            width: CARD_WIDTH,
            height: CARD_HEIGHT,
            rowY,
            branchPath,
            labelX: trunkX + 8,
            labelY: rowY - 9
        };
    }

    /** The shared vertical spine one lane's branches merge into — spans from the topmost to the bottommost row, extended to include centerY so the final horizontal approach into the center card always has somewhere on the trunk to leave from. Null when the lane is empty. */
    buildTrunkPath(trunkX, cards, centerY) {
        if (cards.length === 0) {
            return null;
        }
        const ys = cards.map((card) => card.rowY).concat([centerY]);
        const minY = Math.min(...ys);
        const maxY = Math.max(...ys);
        return `M ${trunkX} ${minY} V ${maxY}`;
    }

    /**
     * A self-relationship is rendered as its own small "shadow" card below the center (labelled
     * "{Object} (Self)"), captioned "SELF RELATIONSHIP / {Object} references {Object}" above it,
     * joined to the real center card by a rounded down-and-back loop — the honest visual answer
     * to "this object references itself" (item 12), never a bare label with no connector at all.
     */
    buildSelfEntry(connector, index, centerX, centerBottomY, diagramHeight) {
        const decorated = this.decorateConnector(connector, 'self', index);
        const entryTop = diagramHeight + index * SELF_ENTRY_HEIGHT;
        const captionY = entryTop + 4;
        const cardTopY = entryTop + SELF_CAPTION_HEIGHT;
        const cardX = centerX + (CENTER_WIDTH - SELF_CARD_WIDTH) / 2;
        const leftX = centerX + CENTER_WIDTH * 0.32;
        const rightX = centerX + CENTER_WIDTH * 0.68;
        const cardLeftX = cardX + SELF_CARD_WIDTH * 0.3;
        const cardRightX = cardX + SELF_CARD_WIDTH * 0.7;
        const midY = (centerBottomY + cardTopY) / 2;
        const downPath = `M ${leftX} ${centerBottomY} Q ${leftX} ${midY} ${cardLeftX} ${cardTopY}`;
        const upPath = `M ${cardRightX} ${cardTopY} Q ${rightX} ${midY} ${rightX} ${centerBottomY}`;
        const captionBoxWidth = 260;
        const labelBoxWidth = 240;
        return {
            ...decorated,
            downPathKey: `self-down-${index}-${connector.connectorKey}`,
            upPathKey: `self-up-${index}-${connector.connectorKey}`,
            captionX: centerX + CENTER_WIDTH / 2 - captionBoxWidth / 2,
            captionY,
            captionWidth: captionBoxWidth,
            cardX,
            cardY: cardTopY,
            cardWidth: SELF_CARD_WIDTH,
            cardHeight: SELF_CARD_HEIGHT,
            downPath,
            upPath,
            labelX: centerX + CENTER_WIDTH / 2 - labelBoxWidth / 2,
            labelY: cardTopY + SELF_CARD_HEIGHT + 12,
            labelWidth: labelBoxWidth
        };
    }

    // --- Connector decoration (aggregation display, GraphUI.md §42.2 step 5) ---

    get activeConnectorKey() {
        return this.selectedConnectorKey || this.hoveredConnectorKey;
    }

    /**
     * The connector's own label, rendered on the line itself. Object mode's connectors always
     * carry field detail: a single relationship states its own field ("AccountId · Lookup");
     * more than one states the aggregate plainly ("3 Lookup Relationships") rather than a
     * cryptic "+2" a viewer has to decode. Record mode's connectors carry no field detail at all
     * (c/recordRelationshipView's own limitation — a record edge has no originating field) —
     * that case degrades to the connector's own relationshipTypeLabel alone ("Related Record"),
     * never a field-shaped string with nothing to fill it. Either way, the individual fields (or,
     * for records, the related record itself) are one click away via the connector detail
     * (oiRelationshipConnectorDetail), which already lists every one of them.
     */
    decorateConnector(connector, laneKey, index) {
        const { connectorLabel, relationshipTypeLabel } = buildConnectorLabelText(connector);
        const isActive = this.activeConnectorKey === connector.connectorKey;
        const isDimmed = false;
        return {
            ...connector,
            connectorLabel,
            relationshipTypeLabel,
            counterpartTypeLabel: this.counterpartTypeLabel(connector.counterpartObject),
            selfCaptionSubtitle: this.selfCaptionSubtitle(),
            lineClass: this.connectorLineClass(connector, laneKey, isActive, isDimmed),
            labelClass: this.connectorLabelClass(connector, laneKey, isActive, isDimmed),
            cardClass: 'oi-orc-card' + (isActive ? ' is-active' : '') + (isDimmed ? ' is-dimmed' : ''),
            cardAriaLabel: this.buildAriaLabel(connector, relationshipTypeLabel),
            rowKey: `${laneKey}-${index}-${connector.connectorKey}`
        };
    }

    /** The self-card's own subtitle (below its counterpart's name — see the self-card template, which renders the COUNTERPART's identity, not the root's own, since a record self-relationship's counterpart is a genuinely different record). */
    counterpartTypeLabel(counterpartObject) {
        return this.isRecordMode ? `${counterpartObject.secondaryKey} Record` : counterpartObject.isCustom ? 'Custom Object' : 'Standard Object';
    }

    /**
     * The self-relationship caption's own subtitle. Object mode's self connector always has
     * counterpart === center (the same object referencing itself), so "{label} references
     * {label}" is literally true. Record mode's self connector is a DIFFERENT record of the same
     * object type (records are individually keyed by Id, ADR-0024) — "{root} references {root}"
     * would misname the actual related record, so this reads as "{objectApiName} record related
     * to another {objectApiName} record" instead, naming the object type both records share
     * rather than a specific record name that would be wrong for one side of the pair.
     */
    selfCaptionSubtitle() {
        if (!this.rootObject) {
            return '';
        }
        if (this.isRecordMode) {
            return `${this.rootObject.secondaryKey} record related to another ${this.rootObject.secondaryKey} record`;
        }
        return `${this.rootObject.label} references ${this.rootObject.label}`;
    }

    /** Direction is color-coded (incoming = violet, outgoing = blue, self = pink) as a secondary cue; relationship type is never color-only — Master-Detail is a visibly heavier stroke than Lookup, and a System relationship (visible under System/All) is dashed, exactly matching the legend. */
    connectorLineClass(connector, laneKey, isActive, isDimmed) {
        let cls = 'oi-orc-connector-line oi-orc-connector-line-' + laneKey;
        cls += connector.primaryRelationshipType === 'MasterDetail' ? ' is-master-detail' : ' is-lookup';
        if (connector.isSystemRelationship) {
            cls += ' is-system';
        }
        if (isActive) {
            cls += ' is-active';
        }
        if (isDimmed) {
            cls += ' is-dimmed';
        }
        return cls;
    }

    connectorLabelClass(connector, laneKey, isActive, isDimmed) {
        let cls = 'oi-orc-connector-label oi-orc-connector-label-' + laneKey;
        if (isActive) {
            cls += ' is-active';
        }
        if (isDimmed) {
            cls += ' is-dimmed';
        }
        return cls;
    }

    buildAriaLabel(connector, relationshipTypeLabel) {
        const centerLabel = this.rootObject ? this.rootObject.label : '';
        const counterpartLabel = connector.counterpartObject.label;
        const fieldNames = connector.fields
            .map((field) => field.fieldApiName)
            .filter(Boolean)
            .join(', ');
        /** Record mode's connectors carry no fields — "through {fieldNames}" would read as "through ," with nothing to fill it, so that clause is dropped entirely rather than left dangling. */
        const throughClause = fieldNames ? ` through ${fieldNames}` : '';
        if (connector.direction === 'incoming') {
            return `${counterpartLabel} references ${centerLabel}${throughClause}, ${relationshipTypeLabel}`;
        }
        if (connector.direction === 'self') {
            return `${centerLabel} is related to ${counterpartLabel}${throughClause}, ${relationshipTypeLabel}`;
        }
        return `${centerLabel} references ${counterpartLabel}${throughClause}, ${relationshipTypeLabel}`;
    }

    findConnector(connectorKey) {
        const all = [...this.view.incomingRelationships, ...this.view.outgoingRelationships, ...this.view.selfRelationships];
        return all.find((connector) => connector.connectorKey === connectorKey) || null;
    }

    // --- Interactions ---

    handleCardSelect(event) {
        const nodeKey = event.currentTarget.dataset.nodeKey;
        const connectorKey = event.currentTarget.dataset.connectorKey;
        this.selectedConnectorKey = connectorKey || null;
        this.dispatchEvent(new CustomEvent('select', { detail: { nodeKey } }));
    }

    handleCardOpen(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('open', { detail: { nodeKey: event.currentTarget.dataset.nodeKey } }));
    }

    handleCardKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleCardSelect(event);
        }
    }

    handleCardMouseEnter(event) {
        this.hoveredConnectorKey = event.currentTarget.dataset.connectorKey || null;
    }

    handleCardMouseLeave() {
        this.hoveredConnectorKey = null;
    }

    handleExploreFromHere(event) {
        event.stopPropagation();
        const nodeKey = event.currentTarget.dataset.nodeKey;
        this.dispatchEvent(new CustomEvent('explorefromhere', { detail: { nodeKey } }));
    }

    /** Every connector click opens the full detail — oiRelationshipConnectorDetail already lists every aggregated field, so there is no separate inline expand affordance to keep in sync with it. */
    handleConnectorClick(event) {
        event.stopPropagation();
        const connectorKey = event.currentTarget.dataset.connectorKey;
        const connector = this.findConnector(connectorKey);
        if (!connector) {
            return;
        }
        this.selectedConnectorKey = connectorKey;
        this.dispatchEvent(new CustomEvent('edgeclick', { detail: { connector, rootObject: this.rootObject } }));
    }

    handleConnectorKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleConnectorClick(event);
        }
    }

    handleConnectorMouseEnter(event) {
        this.hoveredConnectorKey = event.currentTarget.dataset.connectorKey || null;
    }

    handleConnectorMouseLeave() {
        this.hoveredConnectorKey = null;
    }

    /**
     * Patches the arrow marker's refX/refY (cannot be written as template markup at all — LWC's
     * attribute validator rejects any name ending outside [a-z0-9]) and every connector path's
     * marker-end reference to whatever id LWC's synthetic shadow renderer actually assigned the
     * <marker> element — the same "known platform quirk" oiGraphCanvas.js already documents and
     * works around identically. Guarded per-element so a pure re-render never rewrites an
     * attribute that's already correct.
     */
    syncSvgDefReferences() {
        const marker = this.template.querySelector('[data-id="orc-arrow-marker"]');
        if (!marker) {
            return;
        }
        if (marker.getAttribute('refX') !== '7') {
            marker.setAttribute('refX', '7');
        }
        if (marker.getAttribute('refY') !== '4') {
            marker.setAttribute('refY', '4');
        }
        const arrowUrl = `url(#${marker.id})`;
        this.template.querySelectorAll('[data-id="orc-arrow-path"]').forEach((path) => {
            if (path.getAttribute('marker-end') !== arrowUrl) {
                path.setAttribute('marker-end', arrowUrl);
            }
        });
    }
}
