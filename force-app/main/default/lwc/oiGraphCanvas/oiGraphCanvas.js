/**
 * Purpose: The presentational Graph Canvas (GraphUI.md §4) — renders the current visible
 *          node/edge set with a radial/egocentric layout (§17, ADR-0019) as an infinite,
 *          Google-Maps-style pannable/zoomable surface. Never fetches data; never contains
 *          a type-specific conditional (styling arrives already resolved via props, per the
 *          container's registry lookup, §20).
 * Responsibilities: Compute ring-by-hop-distance layout from the currently visible set
 *                    only (a client-local layout decision, not a correctness one, §17);
 *                    absorb a field node into its owning object's Schema-Builder-style card
 *                    (GraphUI.md §20 addendum) whenever the owner's registry-resolved
 *                    showFieldList is true and the connecting edge's registry-resolved
 *                    isFieldMembership is true — never a hardcoded typeKey check — re-
 *                    anchoring any other edge that touched the absorbed field onto its
 *                    owner so relationship lines always connect card-to-card, exactly like
 *                    native Schema Builder; group same-typeKey neighbors of one parent into
 *                    a single collapsible cluster card when the group is large (§26 hub-node
 *                    handling) — a pure rendering decision over already-fetched data, never
 *                    a new fetch and never a change to the real visible node/edge set the
 *                    container owns (field absorption already handles the common "hub object
 *                    with 50 fields" case before clustering ever sees it; clustering remains
 *                    for large non-absorbed neighbor sets, e.g. many related objects/records);
 *                    render nodes via child oiGraphNode/oiSchemaObjectCard instances inside
 *                    SVG <foreignObject> elements (the standard, correct mechanism for
 *                    embedding a Web Component inside an <svg> tree); render edges
 *                    directly as <path> elements, one per visible edge, never componentized
 *                    (§6); support manual per-node dragging, cursor-anchored wheel zoom,
 *                    double-click-to-zoom, momentum/inertia panning (a fast drag-release
 *                    "flick" coasts to a stop under simulated friction, exactly like Google
 *                    Maps — see startMomentum), a Google-Maps-style zoom control (+/-/reset,
 *                    smoothly animated), and a passive overview mini-map — all client-only
 *                    view concerns (position/viewport offsets), never a data or layout-model
 *                    change; emit expand/collapse/select — never decide what those mean.
 * Layout refinement (2026-08-19): §17's force-relaxation pass — previously undocumented as
 *              unimplemented right here — is now implemented as a barycenter-reordering
 *              heuristic; see computeBaseLayout()'s own doc comment for the full mechanism.
 *              It is in-house and dependency-free, not the "vendored layout-math library"
 *              ADR-0020 anticipated: the actual math needed (fixed-radius rings + circular-
 *              mean angular attraction) is bespoke to this radial/hub-node design with no
 *              drop-in off-the-shelf equivalent, so vendoring a general force-simulation
 *              library would have meant overriding most of it anyway while also taking on a
 *              static-resource CSP/license review (CodingStandards §11) for no real reuse
 *              benefit. ADR-0020 should be amended to reflect this, not left describing a
 *              dependency that was never actually added.
 * Limitations: No touch/pinch (§31, explicitly desktop/tablet-first). The
 *              mini-map is the passive "Viewport Mini-map" half only (GraphUI.md §24) —
 *              the server-backed Frontier Summary half is not built. A field that
 *              self-references its own owning object (e.g. a hierarchical lookup) collapses
 *              to a zero-length edge after absorption and is not drawn as a loop-back arc —
 *              its own detail panel remains the way to inspect that relationship.
 *              oiSchemaObjectCard no longer lists its owner's fields inline (Hierarchy
 *              Visualizer field-browser sprint) — it renders a fixed-size card with a plain
 *              field-count line; browsing fields (Show All/Standard/Custom, search, field
 *              type) is the Detail Panel's job now, on demand. This canvas still absorbs
 *              field nodes off the rendered surface entirely (buildFieldAbsorptionMap,
 *              unchanged) — only the card's own inline listing of them is gone.
 * Known platform quirk: LWC's synthetic-shadow renderer appends a per-instance suffix to
 *              any element's literal id="..." attribute (so two instances of this
 *              component on one page never collide), but it has no way to know that a
 *              sibling fill="url(#...)"/marker-end="url(#...)" attribute is a *reference*
 *              to that id — so the grid pattern and edge arrowheads would silently point at
 *              a stale, wrong id and never paint (the background would look completely
 *              static during a pan — nodes move, the backdrop doesn't — since the flat CSS
 *              background color behind the SVG is all that would remain visible). There is
 *              no template-expression fix (LWC decides the suffix, not us); renderedCallback
 *              reads back whatever id LWC actually assigned and patches the referencing
 *              attributes to match — see syncSvgDefReferences().
 * Known platform quirk (viewBox — the inverse-looking failure mode of the one above, and the
 *              actual root cause behind "the graph feels unusable — elements don't move on
 *              zoom, only the background dots do"): SVG defines several attributes in
 *              camelCase (viewBox, markerWidth, markerHeight, refX, refY, patternUnits, ...).
 *              HTML's own tokenizer lowercases every attribute name it parses regardless of
 *              source spelling, so the *only* way LWC's template compiler can put the correct
 *              casing back on the wire is a fixed lookup table keyed by the all-lowercase form
 *              (e.g. "viewbox" -> "viewBox") — but the compiler *also* requires the literal
 *              template source to already match that corrected casing character-for-character
 *              (`getTemplateAttribute`'s own raw-source check), so a template attribute must be
 *              spelled exactly `viewBox={viewBox}` / `markerWidth="8"` — proper SVG camelCase,
 *              not all-lowercase and not hyphenated. Two wrong spellings both look plausible
 *              and both silently break in different ways: `view-box`/`marker-width`
 *              (hyphenated) misses the lookup table entirely and compiles to a literal,
 *              meaningless attribute the SVG renderer ignores — the real viewBox attribute
 *              controlling what portion of the coordinate space is visible is never set at
 *              all, so every pan/zoom/wheel/momentum/fit-to-screen mutation of panX/panY/zoom
 *              has ZERO effect on anything drawn in SVG space (nodes, edges, arrowheads stay
 *              frozen at their first-paint position) while the grid backdrop still visibly
 *              changes — its apparent motion comes from a wholly separate, unaffected
 *              mechanism (the <pattern>'s own width/height scaling inversely with zoom, see
 *              gridTileSize below); `viewbox`/`markerwidth` (all-lowercase) instead fails
 *              LWC's raw-source-casing check and is a hard *build-time* compiler error
 *              (LWC1055), which is the safe failure mode. Do not "simplify" this markup's
 *              casing in either direction. A dedicated regression test (oiGraphCanvas.test.js,
 *              "sets the real SVG viewBox attribute...") asserts the live DOM attribute by its
 *              correct SVG name, and that the hyphenated lookalike is absent, so this specific
 *              defect class cannot regress unnoticed again.
 * Known platform quirk (refX/refY on the arrow marker — a harder variant of the one above,
 *              with no template-markup fix at all): LWC's general attribute-name validator
 *              rejects any attribute whose name ends in a character outside `[a-z0-9]`
 *              (ATTRIBUTE_NAME_MUST_END_WITH_ALPHA_NUMERIC_CHARACTER, LWC1125) — a check that
 *              runs on the already-SVG-corrected name and has no camelCase exception. refX and
 *              refY are two of the small handful of real SVG attributes that end in an
 *              uppercase letter (targetX/Y and pointsAtX/Y/Z are the same shape), so they can
 *              never be written as template markup, full stop — unlike viewBox/markerWidth/
 *              markerHeight above, which merely need the *right* casing, refX/refY have no
 *              casing that compiles. They are instead set imperatively via plain
 *              `setAttribute` in `syncSvgDefReferences()`, the same place this file already
 *              patches `fill`/`marker-end` for the id-suffix quirk above — see that method.
 * Performance: Pan/zoom must never trigger a layout recompute. The expensive part (field
 *              absorption + BFS ring assignment + clustering) is memoized in
 *              `getBaseLayout()`, invalidated only when nodes/edges/expandedClusters/
 *              selectedNodeKey/centerNodeKey actually change — never on a pan or zoom, which
 *              touch none of those. Per-node manual-drag offsets are a
 *              second, cheap memoized layer on top (`getLayout()`) so dragging one node re-
 *              runs a single O(n) map, not the full ring/cluster algorithm. Two getters do
 *              read panX/panY/zoom directly — `viewBox` (the viewport transform itself) and
 *              `renderableNodes`/`renderableEdges` (virtualization, see below) — but both are
 *              cheap O(n) passes over the already-memoized layout, never a re-run of ring
 *              assignment or clustering, so reading them every pan/zoom tick is by design, not
 *              an oversight. Raw pointermove events (which fire far faster than the display
 *              can repaint) are coalesced to at most one state update per animation frame via
 *              scheduleFrameFlush() — the standard technique behind every smooth drag/pan
 *              interaction (Figma, Google Maps included), rather than reacting to, and
 *              re-rendering on, every single input event.
 * Virtualization (ADR-0020, GraphUI.md §4/§26): `positionedNodes` (`getLayout()`'s own output)
 *              represents the FULL currently-loaded working set and is what every non-
 *              rendering consumer (mini-map, fit-to-screen, center-on-selected, reset-layout)
 *              reasons against, since those all need to know about nodes that aren't currently
 *              on screen. `renderableNodes`/`renderableEdges` are a second, template-only
 *              view: the subset of that full set whose footprint
 *              intersects the current viewport expanded by a margin (see
 *              getVirtualizationWindow()) — only *these* get a real `<foreignObject>` and
 *              child LWC instance. A node that pans out of the window is unmounted (LWC tears
 *              down its component instance) and remounts fresh, from props, if it pans back
 *              in — safe because no oiGraphNode/oiSchemaObjectCard instance holds any
 *              meaningful state that doesn't already come from props (selection/expansion/
 *              drag-offset all live in this component or its container, never inside the
 *              child). An edge renders as long as at least one endpoint is within the window,
 *              not only when both are — so a line leading toward a just-off-screen node stays
 *              visible right up to the margin's edge instead of vanishing mid-canvas one frame
 *              before its node would.
 */
import { LightningElement, api, track } from 'lwc';

const RING_SPACING = 160;
const RING_GAP = 32;
const VIEW_WIDTH = 900;
const VIEW_HEIGHT = 600;
/** Tall enough for two stacked lines (the primary label plus the secondaryKey caption — oiGraphNode.html/css) — every plain node reserves this slot even when a given node's secondaryKey happens to be blank, so height stays a single constant per CLAUDE.md's "no hardcoded per-type branching" spirit rather than varying by content. */
const NODE_HEIGHT = 68;
const NODE_GAP = 20;
/** Fixed — the card no longer lists individual fields (that moved to the Detail Panel's Fields section), so its footprint is header + subheader + one field-count line, the same for every object regardless of how many fields it has. Only width scales with label length (see itemFootprint); height never does. */
const SCHEMA_CARD_HEIGHT = 78;
/**
 * Dynamic-width sizing constants for itemFootprint(). A short label (e.g. "User") no longer sits
 * cramped inside the same box a long one (e.g. "Custom_Object_With_A_Long_Name__c") is forced to
 * truncate against — width now scales with the label's own character count, clamped to a
 * sane min/max, with the CSS ellipsis (oiGraphNode.css/oiSchemaObjectCard.css) remaining the
 * correctness backstop once MAX width is hit regardless of how accurate this estimate is.
 * AVG_CHAR_PX is a lightweight heuristic (average glyph width at the node label's font-size/
 * weight), not a live DOM text measurement — measuring every node via getComputedTextLength
 * would be one forced layout per node on every layout pass, working against virtualization's
 * whole point on a large working set.
 * CHROME_PX constants below are calibrated against the actual rendered row (padding + border +
 * every flex gap + the icon + the widest possible expand/collapse toggle text), not just "icon
 * plus a little padding" — an undercounted chrome budget is exactly what silently truncates a
 * label the estimate believed would fit (e.g. "Vishal Bhat" clipping to "Vishal B…"), since the
 * CSS ellipsis backstop then fires far more often than the layout math ever intended.
 */
const AVG_CHAR_PX = 7.2;
const MIN_NODE_WIDTH = 140;
/**
 * Real Salesforce record Names/Subjects (Opportunities, Tasks, Campaigns...) routinely run
 * 30-60+ characters — a cap tuned only against short metadata labels (Objects/Fields/Flows)
 * clamps real record data far more often than intended. Raised accordingly; this is a soft
 * ceiling on how wide a single card is allowed to get before falling back to the hover tooltip
 * (oiGraphNode.js's tooltipText) — not an attempt to fit every possible name inline, which would
 * defeat the point of a compact radial graph entirely.
 */
const MAX_NODE_WIDTH = 360;
/** oiGraphNode.html/css row: 19px h-padding + 5px border + 2 flex gaps (12.8px) + icon (16px) + "Collapse" toggle (~64px, the wider of the two toggle labels) ≈ 117px, rounded up for rendering slop across fonts/browsers. */
const NODE_LABEL_CHROME_PX = 120;
const MIN_SCHEMA_CARD_WIDTH = 210;
const MAX_SCHEMA_CARD_WIDTH = 420;
/** oiSchemaObjectCard.html/css header row: 2px border + 17.6px h-padding + 2 flex gaps (11.2px) + icon (16px) + "Collapse" toggle (~58.8px) ≈ 106px, rounded up. */
const SCHEMA_CARD_LABEL_CHROME_PX = 108;
/** The schema card's subheader (secondaryKey) is a separate full-width row below the header — it shares no icon/toggle/flex-gap chrome with anything, only its own small horizontal padding plus the card border, so it gets its own, much smaller chrome budget rather than reusing the header's. */
const SCHEMA_CARD_SECONDARY_CHROME_PX = 24;
const MIN_ZOOM = 0.2;
const MAX_ZOOM = 3;
const ZOOM_BUTTON_STEP = 0.35;
const ZOOM_ANIMATION_MS = 200;
const CLUSTER_THRESHOLD = 8;
/** Safety cap on barycenter-relaxation sweeps (see computeBaseLayout's Pass 3) — convergence in
 * practice is much faster (a pure tree converges in a single sweep with zero reorders, since
 * every node then has exactly one inner-ring neighbor and no reordering is possible), so this
 * only bounds the pathological case of a deep chain of nested hub references. */
const RELAXATION_SWEEPS = 6;
/** Extra clearance beyond the curve's own bow for a visible edge label, so text never sits directly on the stroke it describes. */
const EDGE_LABEL_OFFSET_PX = 10;
/** How far apart two edges sharing the same resolved endpoints fan out from each other (buildParallelEdgeIndex) — enough to read as two distinct lines/labels at normal zoom without the group ballooning into its own separate layout concern. */
const PARALLEL_EDGE_SEPARATION_PX = 16;
const CLUSTER_PREFIX = '__cluster__::';
const DRAG_THRESHOLD_PX = 3;
const MINIMAP_WIDTH = 150;
const MINIMAP_HEIGHT = 100;
const POINTER_HISTORY_WINDOW_MS = 120;
const MOMENTUM_MIN_VELOCITY = 0.15;
const MOMENTUM_DECELERATION = 0.004;
const DOUBLE_CLICK_ZOOM_STEP = ZOOM_BUTTON_STEP * 2;
/**
 * A wider tile (was 28) with the dot's radius no longer tied to its own center offset — see
 * gridDotCenter below — reads as a quiet, professional "infinite canvas" texture (the same
 * restrained dot-grid convention Figma/Miro/tldraw use) rather than a dense, high-contrast
 * pattern competing with the graph itself for attention.
 */
const GRID_BASE_TILE_PX = 36;
const GRID_DOT_RADIUS_RATIO = 1 / 36;
const FIT_TO_SCREEN_PADDING = 1.15;
/** Virtualization margin, expressed as a multiple of the current viewport's own width/height (so it shrinks/grows with zoom automatically, exactly like the viewport rect itself) — one full viewport's worth of buffer on every side means a normal-speed pan never shows visible pop-in, since nodes materialize a full screen-width before they'd actually be needed. */
const VIRTUALIZATION_MARGIN_RATIO = 1;
const KNOWN_EDGE_LINE_STYLES = new Set(['solid', 'dashed', 'dotted']);

export default class OiGraphCanvas extends LightningElement {
    @api nodes = [];
    @api edges = [];
    @api selectedNodeKey;

    @track panX = 0;
    @track panY = 0;
    @track zoom = 1;
    @track expandedClusters = new Set();
    /** Path-to-centre highlight focus (GraphUI.md-adjacent, this sprint's explainability requirement) — transient hover state, deliberately not part of the memoized layout. */
    @track hoveredNodeKey = null;
    /** Maximize + export — toolbar/canvas chrome only, mirroring oiRelationshipCanvas's own identical controls (audit #07/#08: this toolbar never had them at all, not merely a dead handler). Never affects the fetched working set or the layout/virtualization math above. */
    @track isMaximized = false;
    @track exportHref = null;
    exportFileName = 'graph.svg';

    manualOffsets = new Map();
    isPanning = false;
    lastPointer = null;
    draggingNodeKey = null;
    dragMoved = false;
    zoomAnimationHandle = null;
    frameHandle = null;
    pendingPanDelta = null;
    pendingNodeDelta = null;
    pointerHistory = [];
    momentumHandle = null;
    _centerNodeKey;
    _baseLayoutCache = null;
    _layoutCache = null;
    _pendingExportClick = false;

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

    disconnectedCallback() {
        if (this.exportHref) {
            URL.revokeObjectURL(this.exportHref);
        }
    }

    get hostClass() {
        return 'oi-graph-canvas-container' + (this.isMaximized ? ' oi-graph-canvas-is-maximized' : '');
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

    /** Client-side export, identical pattern to oiRelationshipCanvas.js's handleExportDiagram (see that method's own doc comment for why application/octet-stream + a template-declared anchor, not image/svg+xml or a document.createElement'd one, is the correct/only choice under Lightning Web Security). */
    handleExportDiagram() {
        const svg = this.template.querySelector('[data-id="canvas-svg"]');
        if (!svg) {
            return;
        }
        if (this.exportHref) {
            URL.revokeObjectURL(this.exportHref);
        }
        const clone = svg.cloneNode(true);
        clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
        const source = new XMLSerializer().serializeToString(clone);
        const blob = new Blob([source], { type: 'application/octet-stream' });
        this.exportHref = URL.createObjectURL(blob);
        this._pendingExportClick = true;
    }

    @api
    get centerNodeKey() {
        return this._centerNodeKey;
    }

    set centerNodeKey(value) {
        if (value !== this._centerNodeKey) {
            this.manualOffsets = new Map();
            this.expandedClusters = new Set();
            this.panX = 0;
            this.panY = 0;
            this.zoom = 1;
        }
        this._centerNodeKey = value;
    }

    /**
     * The grid pattern's tile is defined in the same world-space units as everything else on
     * the canvas, so a FIXED tile size becomes sub-pixel — and effectively invisible — once
     * zoomed out far enough (a 28-unit tile at 30% zoom renders as an ~8px, mostly-anti-
     * aliased-away smudge, which is functionally indistinguishable from "the background
     * doesn't move at all," even though it technically still does). Scaling the tile
     * inversely with zoom keeps its ON-SCREEN size constant at every zoom level — the same
     * reason a real map's grid/tile overlay never disappears no matter how far out you zoom.
     */
    get gridTileSize() {
        return GRID_BASE_TILE_PX / this.zoom;
    }

    /** Scales with gridTileSize so the dot's on-screen radius — not just the tile spacing — also stays constant across zoom levels; see gridTileSize's own doc comment. */
    get gridDotRadius() {
        return this.gridTileSize * GRID_DOT_RADIUS_RATIO;
    }

    /**
     * True tile center (tileSize / 2), deliberately NOT derived from the radius. The previous
     * version set this equal to the radius itself, which places a dot tangent to its tile's own
     * top/left edge — at the seam between tiles, that makes each dot touch its neighbor in the
     * next tile over, reading as a denser, quasi-continuous texture instead of isolated, evenly
     * floating dots. Centering properly is what actually makes the grid recede into a subtle
     * backdrop rather than a distracting pattern.
     */
    get gridDotCenter() {
        return this.gridTileSize / 2;
    }

    get viewBox() {
        const { x, y, width, height } = this.viewBoxRect(this.panX, this.panY, this.zoom);
        return `${x} ${y} ${width} ${height}`;
    }

    viewBoxRect(panX, panY, zoom) {
        const width = VIEW_WIDTH / zoom;
        const height = VIEW_HEIGHT / zoom;
        return {
            x: panX - width / 2 + VIEW_WIDTH / 2,
            y: panY - height / 2 + VIEW_HEIGHT / 2,
            width,
            height
        };
    }

    get isEmpty() {
        return !this.nodes || this.nodes.length === 0;
    }

    get zoomPercentDisplay() {
        return `${Math.round(this.zoom * 100)}%`;
    }

    get disableZoomIn() {
        return this.zoom >= MAX_ZOOM - 0.01;
    }

    get disableZoomOut() {
        return this.zoom <= MIN_ZOOM + 0.01;
    }

    get disableFitToScreen() {
        return this.isEmpty;
    }

    get disableCenterOnSelected() {
        return !this.selectedNodeKey || !this.positionedNodes.some((n) => n.nodeKey === this.selectedNodeKey);
    }

    get disableResetLayout() {
        return this.manualOffsets.size === 0;
    }

    get positionedNodes() {
        return this.getLayout().positioned;
    }

    /**
     * The world-space rectangle that currently warrants a real DOM element: the viewport
     * itself, expanded by VIRTUALIZATION_MARGIN_RATIO on every side. Deliberately computed
     * from `viewBoxRect` (the exact same math `viewBox` itself uses) rather than a separate
     * formula, so the two can never drift apart — the margin is always relative to whatever
     * is actually visible, at whatever zoom level is currently active.
     */
    getVirtualizationWindow() {
        const rect = this.viewBoxRect(this.panX, this.panY, this.zoom);
        const marginX = rect.width * VIRTUALIZATION_MARGIN_RATIO;
        const marginY = rect.height * VIRTUALIZATION_MARGIN_RATIO;
        return {
            minX: rect.x - marginX,
            maxX: rect.x + rect.width + marginX,
            minY: rect.y - marginY,
            maxY: rect.y + rect.height + marginY
        };
    }

    /**
     * The virtualized render list (ADR-0020, GraphUI.md §4/§26, see the class doc comment's
     * own "Virtualization" section): the subset of `positionedNodes` whose full footprint
     * (not just its center point — a wide schema card can have an in-view edge while its
     * center sits just outside the window) overlaps the current virtualization window. This
     * is the ONLY place the full working set gets narrowed down for rendering purposes; every
     * other consumer of `positionedNodes` (mini-map, fit-to-screen, center-on-selected,
     * reset-layout) intentionally keeps reading the full, unfiltered set.
     */
    /**
     * The path-to-centre highlight target: whatever is currently hovered, falling back to the
     * selection when nothing is hovered. Hover wins because it is the transient, exploratory
     * gesture the "why is this connected?" question is actually asked from; the selection stays
     * highlighted the rest of the time so the answer doesn't disappear the moment the pointer
     * moves away.
     */
    get activeFocusNodeKey() {
        return this.hoveredNodeKey || this.selectedNodeKey || null;
    }

    /** The BFS parent chain, exposed for path walking — topology only, so it is read straight off the memoized base layout and never recomputed per hover. */
    get pathAncestryMap() {
        return this.getBaseLayout().parentByKey || new Map();
    }

    /**
     * Every node key on the route from the current focus back to the centre, inclusive — null
     * when nothing is focused, which callers must treat as "no highlighting active" rather than
     * an empty path. Bounded by a guard against a malformed/cyclic ancestry map (should not
     * occur — parentByKey is built by a BFS that never revisits a key — but a rendering path
     * must never infinite-loop even on unexpected input).
     */
    get activePathKeySet() {
        const focus = this.activeFocusNodeKey;
        if (!focus) {
            return null;
        }
        const parentByKey = this.pathAncestryMap;
        const path = new Set([focus]);
        let current = focus;
        let guard = 0;
        while (parentByKey.has(current) && guard++ < 1000) {
            current = parentByKey.get(current);
            path.add(current);
        }
        return path;
    }

    /**
     * The virtualized render list (ADR-0020, GraphUI.md §4/§26, see the class doc comment's
     * own "Virtualization" section): the subset of `positionedNodes` whose full footprint
     * (not just its center point — a wide schema card can have an in-view edge while its
     * center sits just outside the window) overlaps the current virtualization window. This
     * is the ONLY place the full working set gets narrowed down for rendering purposes; every
     * other consumer of `positionedNodes` (mini-map, fit-to-screen, center-on-selected,
     * reset-layout) intentionally keeps reading the full, unfiltered set.
     *
     * Also where path-to-centre highlight state is stamped on: transient UI state (what is
     * currently hovered/selected), so it belongs at render time, not in the memoized topology
     * pass — hovering must never invalidate/recompute the layout itself.
     */
    get renderableNodes() {
        const window = this.getVirtualizationWindow();
        const visible = this.positionedNodes.filter((node) => boxIntersectsWindow(node, window));
        const pathKeys = this.activePathKeySet;
        if (!pathKeys) {
            return visible;
        }
        return visible.map((node) => ({
            ...node,
            isOnActivePath: pathKeys.has(node.nodeKey),
            isDimmed: !pathKeys.has(node.nodeKey)
        }));
    }

    /**
     * Groups edges (after field-absorption's resolveDisplayKey) by their resolved
     * (sourceKey, targetKey) pair — two distinct relationships that happen to connect the same
     * two cards (e.g. two different lookup fields on the same object both referencing the same
     * target object, a real, common case once fields absorb into their owning object) resolve to
     * literally identical endpoints, and curvedPath/edgeLabelPosition are pure functions of
     * nothing but those endpoints — without this, they'd render as one indistinguishable
     * overlapping line with one label silently overwriting the other. Returns a Map from edgeKey
     * to {index, count} so renderableEdges can fan each member of a group out to its own,
     * non-overlapping parallel curve (see PARALLEL_EDGE_SEPARATION_PX).
     */
    buildParallelEdgeIndex(edges, resolveDisplayKey) {
        const groups = new Map();
        for (const edge of edges || []) {
            if (edge.isFieldMembership) {
                continue;
            }
            const sourceKey = resolveDisplayKey(edge.sourceNodeKey);
            const targetKey = resolveDisplayKey(edge.targetNodeKey);
            if (sourceKey === targetKey) {
                continue;
            }
            const groupKey = sourceKey + '::' + targetKey;
            if (!groups.has(groupKey)) {
                groups.set(groupKey, []);
            }
            groups.get(groupKey).push(edge.edgeKey);
        }
        const indexByEdgeKey = new Map();
        for (const memberKeys of groups.values()) {
            memberKeys.forEach((edgeKey, index) => indexByEdgeKey.set(edgeKey, { index, count: memberKeys.length }));
        }
        return indexByEdgeKey;
    }

    get renderableEdges() {
        const layout = this.getLayout();
        const byKey = new Map();
        for (const node of layout.positioned) {
            byKey.set(node.nodeKey, node);
        }
        const renderableKeys = new Set(this.renderableNodes.map((node) => node.nodeKey));
        const fieldOwnerByFieldKey = layout.fieldOwnerByFieldKey || new Map();
        const treeEdgeKeys = layout.treeEdgeKeys || new Set();
        const resolveDisplayKey = (key) => fieldOwnerByFieldKey.get(key) || key;
        const pathKeys = this.activePathKeySet;
        const parallelIndex = this.buildParallelEdgeIndex(this.edges, resolveDisplayKey);
        const rendered = [];
        for (const edge of this.edges || []) {
            /** A field-membership edge (HAS_FIELD) is absorbed into the card's inline field list, never drawn as its own line — dropping the field node from `positioned` already achieves this, this check just makes the intent explicit. */
            if (edge.isFieldMembership) {
                continue;
            }
            const sourceKey = resolveDisplayKey(edge.sourceNodeKey);
            const targetKey = resolveDisplayKey(edge.targetNodeKey);
            /** A field's relationship to its own owning object (e.g. a self-referencing hierarchical lookup) collapses to a zero-length edge once both ends resolve to the same card — see the class doc-comment's Limitations note. */
            if (sourceKey === targetKey) {
                continue;
            }
            const source = byKey.get(sourceKey);
            const target = byKey.get(targetKey);
            if (!source || !target) {
                continue;
            }
            /** Symmetric around the base curve: a lone edge (count 1) gets offset 0 — pixel-identical to before this fix — and only a genuine duplicate pair/group fans out. */
            const parallel = parallelIndex.get(edge.edgeKey) || { index: 0, count: 1 };
            const parallelOffset = (parallel.index - (parallel.count - 1) / 2) * PARALLEL_EDGE_SEPARATION_PX;
            /** Virtualization (ADR-0020, §26): render as long as at least one endpoint is currently materialized — a line leading toward a just-off-screen node should stay visible up to the margin's edge, never vanish mid-canvas one frame before its own node would. Only an edge whose BOTH endpoints are outside the window gets skipped. */
            if (!renderableKeys.has(sourceKey) && !renderableKeys.has(targetKey)) {
                continue;
            }
            /** The registry documents three line styles (solid/dashed/dotted, GraphUI.md §21) — previously only two were actually recognized here, so a "dotted" registry value (introduced for SalesforceMetadata.REFERENCES, the Dependency Engine's new edge type) silently rendered as solid. Any recognized value now passes through; an unrecognized one still falls back to solid, never a broken/missing stroke. */
            const lineStyle = KNOWN_EDGE_LINE_STYLES.has(edge.lineStyle) ? edge.lineStyle : 'solid';
            /** A real edge that isn't part of the BFS tree that produced the current layout — e.g.
             * a second lookup reaching an already-placed node from a different branch
             * (GraphUI.md §18's hub-node case) — recedes visually (oi-graph-edge-secondary,
             * reduced opacity) so the primary radial structure reads clearly first. Still fully
             * drawn, never hidden: this only changes how it looks, not whether it renders. */
            const isSecondary = !treeEdgeKeys.has(`${sourceKey}::${targetKey}`);
            /**
             * Path-to-centre highlight for edges: both endpoints must be on the current path,
             * not just present in the path set independently — otherwise a lookup between two
             * unrelated ancestors that both happen to sit on the chain (rare, but possible in a
             * dense graph) would light up as if it were the traversed link. Good enough for a
             * tree-shaped path (the common case, since the path is exactly the chain of BFS
             * parents) without needing to track the literal sequence of edges walked.
             */
            const isOnActivePath = !!pathKeys && pathKeys.has(sourceKey) && pathKeys.has(targetKey);
            const isPathDimmed = !!pathKeys && !isOnActivePath;
            /** A visible label only for primary/tree edges by default (GraphUI.md's "intelligent hierarchy": concise labels on direct connections, secondary edges stay label-less until hover/selection reveals the full <title> tooltip already wired below) — showing a label on every secondary edge in a dense graph is exactly the clutter this sprint is required not to create. Path highlighting always shows its label, since a highlighted edge is by definition the one thing the user is currently asking about. */
            const showLabel = !isSecondary || isOnActivePath;
            /** Empty string, never null — the <text> element renders unconditionally now (see the template's own comment on why), so its content must always be a safe, definite value rather than something that merely happens to render as blank. */
            const shortLabel = showLabel ? this.buildEdgeShortLabel(edge) : '';
            const labelPosition = shortLabel ? edgeLabelPosition(source.cx, source.cy, target.cx, target.cy, parallelOffset) : null;
            rendered.push({
                edgeKey: edge.edgeKey,
                typeKey: edge.typeKey,
                displayLabel: edge.displayLabel || edge.typeKey,
                pathD: curvedPath(source.cx, source.cy, target.cx, target.cy, parallelOffset),
                cssClass:
                    'oi-graph-edge oi-graph-edge-' +
                    lineStyle +
                    (isSecondary ? ' oi-graph-edge-secondary' : '') +
                    (isOnActivePath ? ' oi-graph-edge-on-path' : '') +
                    (isPathDimmed ? ' oi-graph-edge-dimmed' : ''),
                shortLabel,
                labelKey: edge.edgeKey + '-label',
                labelX: labelPosition ? labelPosition.x : 0,
                labelY: labelPosition ? labelPosition.y : 0
            });
        }
        for (const clusterEdge of layout.clusterEdges) {
            const source = byKey.get(clusterEdge.sourceNodeKey);
            const target = byKey.get(clusterEdge.targetNodeKey);
            if (!source || !target) {
                continue;
            }
            if (!renderableKeys.has(clusterEdge.sourceNodeKey) && !renderableKeys.has(clusterEdge.targetNodeKey)) {
                continue;
            }
            const labelPosition = edgeLabelPosition(source.cx, source.cy, target.cx, target.cy);
            rendered.push({
                edgeKey: clusterEdge.edgeKey,
                typeKey: clusterEdge.typeKey,
                displayLabel: clusterEdge.displayLabel,
                pathD: curvedPath(source.cx, source.cy, target.cx, target.cy),
                cssClass: 'oi-graph-edge oi-graph-edge-solid oi-graph-edge-cluster',
                /** A cluster edge already carries an honest, non-technical summary ("68 × Object") — shown as its visible label directly, the same "concise, not raw" bar every other edge label meets. */
                shortLabel: clusterEdge.displayLabel,
                labelKey: clusterEdge.edgeKey + '-label',
                labelX: labelPosition.x,
                labelY: labelPosition.y
            });
        }
        return rendered;
    }

    /** The concise, on-canvas edge label — relationship name alone, or "field · relationship" when a via-field is known (e.g. "AccountId · Lookup"). Never the raw typeKey: displayLabel is already registry-resolved by the container. */
    buildEdgeShortLabel(edge) {
        const relationship = edge.displayLabel || edge.typeKey;
        return edge.viaFieldApiName ? `${edge.viaFieldApiName} · ${relationship}` : relationship;
    }

    /** A small overview thumbnail of every currently-positioned node plus a rectangle marking the current viewport (GraphUI.md §24's Viewport Mini-map half) — pure geometry derived from already-computed positions, zero server cost. */
    get miniMap() {
        const positioned = this.positionedNodes;
        if (positioned.length < 2) {
            return null;
        }
        const xs = positioned.map((n) => n.cx);
        const ys = positioned.map((n) => n.cy);
        const viewport = this.viewBoxRect(this.panX, this.panY, this.zoom);
        const minX = Math.min(...xs, viewport.x);
        const maxX = Math.max(...xs, viewport.x + viewport.width);
        const minY = Math.min(...ys, viewport.y);
        const maxY = Math.max(...ys, viewport.y + viewport.height);
        const spanX = Math.max(maxX - minX, 1);
        const spanY = Math.max(maxY - minY, 1);
        const scale = Math.min(MINIMAP_WIDTH / spanX, MINIMAP_HEIGHT / spanY);
        const offsetX = (MINIMAP_WIDTH - spanX * scale) / 2;
        const offsetY = (MINIMAP_HEIGHT - spanY * scale) / 2;
        const toMini = (x, y) => ({ x: (x - minX) * scale + offsetX, y: (y - minY) * scale + offsetY });

        const dots = positioned.map((n) => {
            const p = toMini(n.cx, n.cy);
            return { key: n.nodeKey, cx: p.x, cy: p.y, isCenter: n.nodeKey === this.centerNodeKey };
        });
        const topLeft = toMini(viewport.x, viewport.y);
        const bottomRight = toMini(viewport.x + viewport.width, viewport.y + viewport.height);
        return {
            width: MINIMAP_WIDTH,
            height: MINIMAP_HEIGHT,
            dots,
            viewportRect: {
                x: topLeft.x,
                y: topLeft.y,
                width: Math.max(bottomRight.x - topLeft.x, 4),
                height: Math.max(bottomRight.y - topLeft.y, 4)
            }
        };
    }

    get hasMiniMap() {
        return !!this.miniMap;
    }

    /**
     * The cheap, frequently-called layer: applies manual per-node drag offsets on top of the
     * memoized base layout. A pan or zoom changes neither manualOffsets nor any base-layout
     * input, so during a pure pan this returns the exact same cached objects every time —
     * child oiGraphNode instances then see identical props and LWC skips re-rendering them
     * entirely, which is what actually makes panning feel instant on a large graph.
     */
    getLayout() {
        const base = this.getBaseLayout();
        const cache = this._layoutCache;
        if (cache && cache.base === base && cache.manualOffsets === this.manualOffsets) {
            return cache.result;
        }
        const result = this.manualOffsets.size === 0 ? base : applyManualOffsets(base, this.manualOffsets);
        this._layoutCache = { base, manualOffsets: this.manualOffsets, result };
        return result;
    }

    /**
     * The expensive layer: BFS ring assignment + clustering (§17, §26). Memoized against the
     * only four inputs that can actually change its output — recomputing this on every pixel
     * of a pan/drag gesture (as an earlier version of this component did) is the difference
     * between a snappy canvas and a laggy one on any graph past a few dozen nodes.
     */
    getBaseLayout() {
        const cache = this._baseLayoutCache;
        if (
            cache &&
            cache.nodes === this.nodes &&
            cache.edges === this.edges &&
            cache.expandedClusters === this.expandedClusters &&
            cache.selectedNodeKey === this.selectedNodeKey &&
            cache.centerNodeKey === this._centerNodeKey
        ) {
            return cache.result;
        }
        const result = this.computeBaseLayout();
        this._baseLayoutCache = {
            nodes: this.nodes,
            edges: this.edges,
            expandedClusters: this.expandedClusters,
            selectedNodeKey: this.selectedNodeKey,
            centerNodeKey: this._centerNodeKey,
            result
        };
        return result;
    }

    /**
     * Field absorption (GraphUI.md §20 addendum): a field is folded into its owning object's
     * card whenever BOTH sides of the connecting edge opt in via the registry — the owner's
     * showFieldList and the edge's isFieldMembership — never a hardcoded typeKey check. A
     * field with no absorbing owner (registry not loaded yet, or its owner isn't a card type)
     * simply isn't in the returned map and renders as its own standalone pill, exactly as
     * before this feature existed.
     */
    buildFieldAbsorptionMap(nodeByKey) {
        const fieldOwnerByFieldKey = new Map();
        for (const edge of this.edges || []) {
            if (!edge.isFieldMembership) {
                continue;
            }
            const owner = nodeByKey.get(edge.sourceNodeKey);
            if (owner && owner.showFieldList && nodeByKey.has(edge.targetNodeKey)) {
                fieldOwnerByFieldKey.set(edge.targetNodeKey, edge.sourceNodeKey);
            }
        }
        return fieldOwnerByFieldKey;
    }

    /** Each absorbed field keeps its own isSelected/isExpanded/hasMoreNeighbors — it is still a first-class node, merely rendered as a row inside its owner's card instead of positioned separately, so selecting or expanding it works exactly as it did as a standalone pill. */
    buildFieldListsByOwner(fieldOwnerByFieldKey, nodeByKey) {
        const fieldsByOwnerKey = new Map();
        for (const [fieldKey, ownerKey] of fieldOwnerByFieldKey) {
            const fieldNode = nodeByKey.get(fieldKey);
            if (!fieldsByOwnerKey.has(ownerKey)) {
                fieldsByOwnerKey.set(ownerKey, []);
            }
            fieldsByOwnerKey.get(ownerKey).push({
                nodeKey: fieldNode.nodeKey,
                label: fieldNode.label,
                iconName: fieldNode.iconName,
                isSelected: fieldNode.nodeKey === this.selectedNodeKey,
                isExpanded: !!fieldNode.isExpanded,
                hasMoreNeighbors: !!fieldNode.hasMoreNeighbors
            });
        }
        return fieldsByOwnerKey;
    }

    /**
     * Ring assignment from the currently visible set only — a layout decision, not a
     * traversal correctness decision (GraphUI.md §17). Runs over the field-absorbed node/edge
     * set: an absorbed field never gets its own ring slot, and BFS/edges treat it as if it
     * were its owner (resolveDisplayKey) so centering on a field, or following a lookup that
     * originates from one, behaves as "center on/connect to the object," matching native
     * Schema Builder's object-is-the-atomic-node model. Also groups a hub node's same-typeKey
     * neighbors into one collapsible cluster card per (parent, typeKey) when that group is
     * large (§26) — clustering is entirely local to this render pass; it never touches the
     * real node/edge set the container owns, and expanding a cluster only reveals nodes that
     * were already fetched and already visible in `this.nodes`/`this.edges`. Manual drag
     * offsets are deliberately NOT applied here — see getLayout().
     *
     * Four passes, each building on the last:
     *   1. Radius per ring — unchanged from v1, order-invariant (a sum and a max, neither
     *      affected by which item within a ring comes first), so it is computed once and
     *      never revisited by the relaxation in pass 3.
     *   2. Initial angle assignment — the original v1 sequential arc-slicing formula, in each
     *      ring's natural (insertion) order. Always a valid, non-overlapping layout on its own,
     *      exactly reproducing v1's output — the relaxation below is strictly additive
     *      refinement on top of this baseline, never a replacement for it.
     *   3. Barycenter relaxation (§17's "light force-relaxation pass... to reduce edge
     *      crossings", the gap this file's own Limitations note used to describe as missing).
     *      The classic barycenter heuristic from layered/Sugiyama-style graph drawing, adapted
     *      to concentric rings: each sweep re-sorts every ring's items by the circular mean of
     *      their STRICTLY-INNER-ring neighbors' current angles — real graph adjacency, not
     *      just the one BFS parent that revealed them, so a node referenced from two different
     *      branches (GraphUI.md §18's hub-node case) is pulled toward sitting angularly between
     *      all of them — then re-slices that ring with the exact same overlap-safe formula from
     *      pass 2. Restricting influence to strictly-inner rings is what guarantees convergence
     *      instead of oscillation: an inner ring can never be pulled by an outer one it already
     *      helped position, so once a ring stops reordering it never moves again in a later
     *      sweep. "Repulsion between same-ring nodes" (§17) is satisfied by construction, not a
     *      soft force — the arc-slicing in passes 2/3 allocates each item an angular width
     *      sized to its own footprint, a hard guarantee of zero overlap rather than one
     *      competing forces merely tend toward. Stops the moment a full sweep reorders nothing
     *      (a pure tree — every existing Jest fixture before this change — converges with zero
     *      reorders, reproducing v1's exact output byte-for-byte).
     *   4. Final placement — stamps cx/cy from each ring's pass-1 radius and each item's
     *      pass-3 angle, via the same placeItem every prior version used.
     */
    computeBaseLayout() {
        const nodes = this.nodes || [];
        const nodeByKey = new Map();
        for (const node of nodes) {
            nodeByKey.set(node.nodeKey, node);
        }

        const fieldOwnerByFieldKey = this.buildFieldAbsorptionMap(nodeByKey);
        const resolveDisplayKey = (key) => fieldOwnerByFieldKey.get(key) || key;
        const fieldsByOwnerKey = this.buildFieldListsByOwner(fieldOwnerByFieldKey, nodeByKey);
        const displayNodes = nodes.filter((node) => !fieldOwnerByFieldKey.has(node.nodeKey));

        const adjacency = new Map();
        for (const node of displayNodes) {
            adjacency.set(node.nodeKey, []);
        }
        for (const edge of this.edges || []) {
            if (edge.isFieldMembership) {
                continue;
            }
            const source = resolveDisplayKey(edge.sourceNodeKey);
            const target = resolveDisplayKey(edge.targetNodeKey);
            if (source === target) {
                continue;
            }
            if (adjacency.has(source)) {
                adjacency.get(source).push(target);
            }
            if (adjacency.has(target)) {
                adjacency.get(target).push(source);
            }
        }

        const effectiveCenterKey = this.centerNodeKey ? resolveDisplayKey(this.centerNodeKey) : this.centerNodeKey;

        const ringByKey = new Map();
        const parentByKey = new Map();
        if (effectiveCenterKey && adjacency.has(effectiveCenterKey)) {
            ringByKey.set(effectiveCenterKey, 0);
            let frontier = [effectiveCenterKey];
            let ring = 0;
            while (frontier.length > 0) {
                ring += 1;
                const next = [];
                for (const key of frontier) {
                    for (const neighbor of adjacency.get(key) || []) {
                        if (!ringByKey.has(neighbor)) {
                            ringByKey.set(neighbor, ring);
                            parentByKey.set(neighbor, key);
                            next.push(neighbor);
                        }
                    }
                }
                frontier = next;
            }
        }

        const byKey = new Map();
        for (const node of displayNodes) {
            byKey.set(node.nodeKey, node);
        }

        const { displayItems, clusterEdges } = this.groupIntoClusters(displayNodes, byKey, ringByKey, parentByKey, effectiveCenterKey);

        for (const item of displayItems) {
            const fields = fieldsByOwnerKey.get(item.nodeKey);
            if (fields) {
                item.fields = fields;
            }
        }

        /**
         * "Why is this node here?" (this sprint's central requirement): every non-center item
         * gets a relationshipRole/relationshipContext/relationshipVia stamped on it from the
         * edge that connects it to its BFS parent, plus its hop distance. Built once here, on
         * the memoized base layout, rather than per-render — this is graph topology, not a
         * transient UI concern.
         */
        const edgeRoleByPair = this.buildEdgeRoleIndex(nodeByKey, resolveDisplayKey);
        for (const item of displayItems) {
            item.hopDistance = item.ring;
            if (item.ring === 0) {
                continue;
            }
            /** A cluster card's parent lives on its own parentKey (stamped in groupIntoClusters) since parentByKey never learns synthetic cluster keys; every other item's parent comes from the real BFS map. */
            const parentKey = item.parentKey || parentByKey.get(item.nodeKey);
            if (!parentKey) {
                continue;
            }
            const parentNode = byKey.get(parentKey);
            item.relationshipContext = parentNode ? parentNode.label : null;
            /** A cluster resolves its role from one representative member (see groupIntoClusters) — every member shares the grouping typeKey, so one sample's edge is representative. */
            const roleSourceKey = item.sampleMemberKey || item.nodeKey;
            const relationship = this.resolveRelationshipContext(roleSourceKey, parentKey, edgeRoleByPair);
            if (relationship) {
                item.relationshipRole = relationship.role;
                item.relationshipVia = relationship.viaFieldApiName;
            }
        }

        /** Extends real graph adjacency with cluster edges so a clustered hub still
         * participates in relaxation via its one real connection to its parent — built once
         * here rather than special-cased inside the relaxation loop below. */
        const layoutAdjacency = new Map();
        for (const [key, neighbors] of adjacency) {
            layoutAdjacency.set(key, [...neighbors]);
        }
        for (const clusterEdge of clusterEdges) {
            if (!layoutAdjacency.has(clusterEdge.sourceNodeKey)) {
                layoutAdjacency.set(clusterEdge.sourceNodeKey, []);
            }
            if (!layoutAdjacency.has(clusterEdge.targetNodeKey)) {
                layoutAdjacency.set(clusterEdge.targetNodeKey, []);
            }
            layoutAdjacency.get(clusterEdge.sourceNodeKey).push(clusterEdge.targetNodeKey);
            layoutAdjacency.get(clusterEdge.targetNodeKey).push(clusterEdge.sourceNodeKey);
        }

        const byRing = new Map();
        const ringOfKey = new Map();
        for (const item of displayItems) {
            if (!byRing.has(item.ring)) {
                byRing.set(item.ring, []);
            }
            byRing.get(item.ring).push(item);
            ringOfKey.set(item.nodeKey, item.ring);
        }

        const footprintByKey = new Map();
        for (const item of displayItems) {
            footprintByKey.set(item.nodeKey, itemFootprint(item));
        }

        const sortedRings = [...byRing.keys()].sort((a, b) => a - b);

        // Pass 1: radius per ring (order-invariant — see the method doc comment).
        const radiusByRing = new Map();
        let previousOuterRadius = 0;
        for (const ring of sortedRings) {
            const ringItems = byRing.get(ring);
            const footprints = ringItems.map((item) => footprintByKey.get(item.nodeKey));
            const maxHalfHeight = Math.max(...footprints.map((f) => f.height / 2));
            if (ring === 0) {
                radiusByRing.set(ring, 0);
                previousOuterRadius = maxHalfHeight;
                continue;
            }
            const totalSpan = footprints.reduce((sum, f) => sum + f.width + NODE_GAP, 0);
            const requiredRadius = totalSpan / (2 * Math.PI);
            const minRadiusForSpacing = previousOuterRadius + RING_GAP + maxHalfHeight;
            const radius = Math.max(minRadiusForSpacing, requiredRadius, ring * RING_SPACING);
            radiusByRing.set(ring, radius);
            previousOuterRadius = radius + maxHalfHeight;
        }

        // Pass 2: initial deterministic angle assignment (v1's own formula, unchanged).
        const angleByKey = new Map();
        for (const ring of sortedRings) {
            if (ring === 0) {
                continue;
            }
            assignSequentialRingAngles(byRing.get(ring), footprintByKey, angleByKey);
        }

        // Pass 3: barycenter relaxation — see this method's own doc comment.
        for (let sweep = 0; sweep < RELAXATION_SWEEPS; sweep++) {
            let anyReordered = false;
            for (const ring of sortedRings) {
                if (ring === 0) {
                    continue;
                }
                const ringItems = byRing.get(ring);
                if (ringItems.length < 2) {
                    continue;
                }
                const reordered = sortRingByBarycenter(ringItems, ring, angleByKey, ringOfKey, layoutAdjacency);
                if (reordered.some((item, index) => item !== ringItems[index])) {
                    anyReordered = true;
                }
                byRing.set(ring, reordered);
                assignSequentialRingAngles(reordered, footprintByKey, angleByKey);
            }
            if (!anyReordered) {
                break;
            }
        }

        // Pass 4: stamp final positions from pass 1's radius and pass 3's relaxed angle.
        const positioned = [];
        const centerX = VIEW_WIDTH / 2;
        const centerY = VIEW_HEIGHT / 2;
        for (const ring of sortedRings) {
            const radius = radiusByRing.get(ring);
            for (const item of byRing.get(ring)) {
                const footprint = footprintByKey.get(item.nodeKey);
                if (ring === 0) {
                    positioned.push(this.placeItem(item, footprint, centerX, centerY));
                    continue;
                }
                const angle = angleByKey.get(item.nodeKey);
                const cx = centerX + radius * Math.cos(angle);
                const cy = centerY + radius * Math.sin(angle);
                positioned.push(this.placeItem(item, footprint, cx, cy));
            }
        }

        /** Real (non-cluster) tree edges only, both directions (source::target and
         * target::source — renderableEdges doesn't know which side is which) — used there to
         * mark any OTHER real edge (a second lookup reaching an already-placed node from a
         * different branch, GraphUI.md §18's hub-node case) as visually secondary. Never
         * affects which edges render, only how — every real edge is still drawn (ADR-0019's
         * topological-honesty guarantee). */
        const treeEdgeKeys = new Set();
        for (const [child, parent] of parentByKey) {
            treeEdgeKeys.add(`${child}::${parent}`);
            treeEdgeKeys.add(`${parent}::${child}`);
        }

        return { positioned, clusterEdges, fieldOwnerByFieldKey, treeEdgeKeys, parentByKey };
    }

    /** Stamps a display item's final screen-space box from its already-computed center point and footprint — shared by the ring-0 (dead-center) and per-ring (angular) placement paths so both stay in sync on isSelected. */
    placeItem(item, footprint, cx, cy) {
        return {
            ...item,
            cx,
            cy,
            x: cx - footprint.width / 2,
            y: cy - footprint.height / 2,
            width: footprint.width,
            height: footprint.height,
            isSelected: item.nodeKey === this.selectedNodeKey
        };
    }

    /** Builds the render-time node list: real, non-absorbed nodes, with any large same-typeKey sibling group replaced by one cluster card (§26) — unless the user has already expanded that specific cluster. */
    groupIntoClusters(nodes, byKey, ringByKey, parentByKey, effectiveCenterKey) {
        const groups = new Map();
        const singles = [];
        for (const node of nodes) {
            const ring = ringByKey.has(node.nodeKey) ? ringByKey.get(node.nodeKey) : node.nodeKey === effectiveCenterKey ? 0 : 1;
            if (ring === 0) {
                singles.push({ ...node, ring });
                continue;
            }
            const parentKey = parentByKey.get(node.nodeKey) || '__root__';
            const groupKey = CLUSTER_PREFIX + parentKey + '::' + node.typeKey;
            if (!groups.has(groupKey)) {
                groups.set(groupKey, { groupKey, parentKey, ring, members: [] });
            }
            groups.get(groupKey).members.push(node);
        }

        const displayItems = [...singles];
        const clusterEdges = [];
        for (const group of groups.values()) {
            const isLarge = group.members.length > CLUSTER_THRESHOLD;
            const isExpanded = this.expandedClusters.has(group.groupKey);
            if (!isLarge || isExpanded) {
                for (const member of group.members) {
                    displayItems.push({ ...member, ring: group.ring });
                }
                continue;
            }
            const sample = group.members[0];
            displayItems.push({
                nodeKey: group.groupKey,
                typeKey: sample.typeKey,
                typeLabel: sample.typeLabel,
                label: `${group.members.length} ${sample.typeLabel || sample.typeKey}`,
                state: '',
                iconName: sample.iconName,
                colorToken: sample.colorToken,
                isExpanded: false,
                hasMoreNeighbors: false,
                isCluster: true,
                ring: group.ring,
                /** Not a real graph node key — needed so the relationship-context pass (computeBaseLayout) can find this card's parent, since parentByKey is keyed by real node keys only and never learns about synthetic cluster keys. */
                parentKey: group.parentKey,
                /** One representative member's key, so the relationship role/via-field can be resolved from an actual edge — every member shares this card's grouping typeKey, so one sample's role is representative of the whole group. */
                sampleMemberKey: sample.nodeKey
            });
            const parentNode = byKey.get(group.parentKey);
            if (parentNode) {
                clusterEdges.push({
                    edgeKey: group.groupKey + '::edge',
                    sourceNodeKey: group.parentKey,
                    targetNodeKey: group.groupKey,
                    typeKey: sample.typeKey,
                    displayLabel: `${group.members.length} × ${sample.typeLabel || sample.typeKey}`
                });
            }
        }
        return { displayItems, clusterEdges };
    }

    /**
     * Indexes every real, non-membership edge by its DISPLAY-resolved endpoint pair (both
     * directions), so a node's relationship to its BFS parent can be looked up in O(1) rather
     * than re-scanning `this.edges` per item. Also derives the relationship field's own API
     * name for a field-sourced edge (LOOKUP_TO/MASTER_DETAIL_TO) directly from the absorbed
     * field's own scanned identity — see resolveRelationshipContext for why this, not the
     * edge's own `relationshipName` attribute, is what the chip needs.
     */
    buildEdgeRoleIndex(nodeByKey, resolveDisplayKey) {
        const index = new Map();
        for (const edge of this.edges || []) {
            if (edge.isFieldMembership) {
                continue;
            }
            const resolvedSource = resolveDisplayKey(edge.sourceNodeKey);
            const resolvedTarget = resolveDisplayKey(edge.targetNodeKey);
            if (resolvedSource === resolvedTarget) {
                continue;
            }
            /**
             * A field-sourced relationship (LOOKUP_TO/MASTER_DETAIL_TO) resolves its source to
             * its owning object once absorbed — the raw source key that differs from the
             * resolved one IS the field, so its own secondaryKey ("Opportunity.AccountId") is
             * the real field API name, not a guess. edge.viaFieldApiName (the server-provided
             * `relationshipName` attribute, e.g. "Account") is a lower-priority fallback only —
             * it is a relationship name, not the field's own API name, and is used only when
             * the field node itself cannot be found (absorption did not happen for some reason).
             */
            let viaFieldApiName = null;
            if (resolvedSource !== edge.sourceNodeKey) {
                const fieldNode = nodeByKey.get(edge.sourceNodeKey);
                const apiNameSegments = fieldNode && fieldNode.secondaryKey ? fieldNode.secondaryKey.split('.') : null;
                viaFieldApiName = apiNameSegments ? apiNameSegments[apiNameSegments.length - 1] : null;
            }
            if (!viaFieldApiName && edge.viaFieldApiName) {
                viaFieldApiName = edge.viaFieldApiName;
            }
            const entry = {
                sourceKey: resolvedSource,
                targetKey: resolvedTarget,
                sourceRoleLabel: edge.sourceRoleLabel,
                targetRoleLabel: edge.targetRoleLabel,
                viaFieldApiName
            };
            index.set(resolvedSource + '::' + resolvedTarget, entry);
            index.set(resolvedTarget + '::' + resolvedSource, entry);
        }
        return index;
    }

    /**
     * The neighbour's role relative to one anchor (its BFS parent), read off the indexed edge —
     * mirrors presentationRegistry.js's resolveNeighbourRole exactly, but works from the
     * already-resolved role-label strings the container baked onto each edge, since the Canvas
     * itself never calls the registry (container/presentational split, GraphUI.md §3).
     */
    resolveRelationshipContext(nodeKey, parentKey, edgeRoleByPair) {
        const entry = edgeRoleByPair.get(nodeKey + '::' + parentKey);
        if (!entry) {
            return null;
        }
        const anchorIsSource = entry.sourceKey === parentKey;
        const role = (anchorIsSource ? entry.targetRoleLabel : entry.sourceRoleLabel) || 'Related To';
        return { role, viaFieldApiName: entry.viaFieldApiName };
    }

    handleNodeSelect(event) {
        if (this.dragMoved) {
            this.dragMoved = false;
            return;
        }
        const nodeKey = event.detail.nodeKey;
        if (nodeKey.startsWith(CLUSTER_PREFIX)) {
            this.toggleCluster(nodeKey);
            return;
        }
        this.dispatchEvent(new CustomEvent('select', { detail: { nodeKey } }));
    }

    handleNodeExpandToggle(event) {
        const nodeKey = event.detail.nodeKey;
        if (nodeKey.startsWith(CLUSTER_PREFIX)) {
            this.toggleCluster(nodeKey);
            return;
        }
        const node = (this.nodes || []).find((n) => n.nodeKey === nodeKey);
        if (node && node.isExpanded) {
            this.dispatchEvent(new CustomEvent('collapse', { detail: { nodeKey } }));
        } else {
            this.dispatchEvent(new CustomEvent('expand', { detail: { nodeKey } }));
        }
    }

    /** Purely a client-side rendering toggle (§26) — never calls the container, never touches the real visible node/edge set; the members it reveals were already fetched. */
    toggleCluster(groupKey) {
        const updated = new Set(this.expandedClusters);
        if (updated.has(groupKey)) {
            updated.delete(groupKey);
        } else {
            updated.add(groupKey);
        }
        this.expandedClusters = updated;
    }

    /**
     * Patches the grid pattern's fill and every edge's arrowhead marker to reference
     * whatever id LWC's synthetic shadow renderer actually assigned the <pattern>/<marker>
     * elements (see the class doc-comment's "Known platform quirk") — a template-level
     * fill="url(#oi-canvas-grid)"/marker-end="url(#oi-arrow)" can never track that suffix on
     * its own. Guarded per-element (skips elements whose attribute is already correct) so a
     * pure pan/zoom re-render — which recreates neither the pattern/marker nor any existing
     * edge <path> (all keyed, so LWC reuses the same DOM nodes) — never re-writes an
     * attribute that's already right.
     */
    syncSvgDefReferences() {
        const pattern = this.template.querySelector('[data-id="canvas-grid-pattern"]');
        const gridRect = this.template.querySelector('[data-id="canvas-grid-rect"]');
        if (pattern && gridRect) {
            const patternUrl = `url(#${pattern.id})`;
            if (gridRect.getAttribute('fill') !== patternUrl) {
                gridRect.setAttribute('fill', patternUrl);
            }
        }
        const marker = this.template.querySelector('[data-id="canvas-arrow-marker"]');
        if (marker) {
            /**
             * refX/refY cannot be written as template markup at all (a separate, harder LWC
             * limitation from the id-suffix one this method already exists for): the compiler
             * rejects any attribute name ending in an uppercase letter — ATTRIBUTE_NAME_MUST_
             * END_WITH_ALPHA_NUMERIC_CHARACTER (LWC1125) — before its SVG-camelCase allowance
             * ever gets a say, and refX/refY are two of the small handful of real SVG
             * attributes that end that way (targetX/Y, pointsAtX/Y/Z are the same shape).
             * markerWidth/markerHeight face no such restriction (they end in a lowercase
             * letter) and stay as ordinary template attributes above. These two are constant
             * for the marker's whole lifetime, so setting them once, guarded like every other
             * attribute this method patches, is simpler than any workaround that tries to
             * route them through the template.
             */
            if (marker.getAttribute('refX') !== '6') {
                marker.setAttribute('refX', '6');
            }
            if (marker.getAttribute('refY') !== '4') {
                marker.setAttribute('refY', '4');
            }
            const arrowUrl = `url(#${marker.id})`;
            this.template.querySelectorAll('[data-id="graph-edge-path"]').forEach((path) => {
                if (path.getAttribute('marker-end') !== arrowUrl) {
                    path.setAttribute('marker-end', arrowUrl);
                }
            });
        }
    }

    /** Cursor-anchored zoom (the point under the mouse stays fixed on screen) — the interaction users actually expect from a Google-Maps-style map, rather than always zooming toward a fixed center. */
    handleWheel(event) {
        event.preventDefault();
        this.cancelMomentum();
        const svg = this.template.querySelector('[data-id="canvas-svg"]');
        const rect = svg.getBoundingClientRect();
        const before = this.viewBoxRect(this.panX, this.panY, this.zoom);
        const svgX = before.x + ((event.clientX - rect.left) / rect.width) * before.width;
        const svgY = before.y + ((event.clientY - rect.top) / rect.height) * before.height;

        const delta = event.deltaY > 0 ? -0.12 : 0.12;
        const newZoom = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, this.zoom * (1 + delta)));
        this.applyZoomAnchoredAt(svgX, svgY, newZoom, (event.clientX - rect.left) / rect.width, (event.clientY - rect.top) / rect.height);
        this.dispatchEvent(new CustomEvent('viewportchange', { detail: { panX: this.panX, panY: this.panY, zoom: this.zoom } }));
    }

    /** Recomputes pan so that world point (svgX, svgY) continues to render at the same fractional screen position (fracX, fracY) after the zoom change — the anchoring math a smooth map zoom depends on. */
    applyZoomAnchoredAt(svgX, svgY, newZoom, fracX, fracY) {
        // Solve for panX/panY such that x + fracX*width === svgX (and the y equivalent), given viewBoxRect's own x/y formula.
        const newWidth = VIEW_WIDTH / newZoom;
        const newHeight = VIEW_HEIGHT / newZoom;
        const targetX = svgX - fracX * newWidth;
        const targetY = svgY - fracY * newHeight;
        this.panX = targetX + newWidth / 2 - VIEW_WIDTH / 2;
        this.panY = targetY + newHeight / 2 - VIEW_HEIGHT / 2;
        this.zoom = newZoom;
    }

    /** Double-click-to-zoom (a standard map interaction) — ignores double-clicks on a node/card itself (that's a drag/select target, not a "zoom here" gesture), only firing for the empty canvas backdrop. */
    handleDoubleClick(event) {
        if (event.target.closest('foreignObject')) {
            return;
        }
        event.preventDefault();
        this.cancelMomentum();
        const svg = this.template.querySelector('[data-id="canvas-svg"]');
        const rect = svg.getBoundingClientRect();
        const before = this.viewBoxRect(this.panX, this.panY, this.zoom);
        const svgX = before.x + ((event.clientX - rect.left) / rect.width) * before.width;
        const svgY = before.y + ((event.clientY - rect.top) / rect.height) * before.height;
        const fracX = (event.clientX - rect.left) / rect.width;
        const fracY = (event.clientY - rect.top) / rect.height;
        const targetZoom = Math.min(MAX_ZOOM, this.zoom + DOUBLE_CLICK_ZOOM_STEP);
        this.animateZoomAnchored(svgX, svgY, fracX, fracY, targetZoom);
    }

    /**
     * The animated counterpart to applyZoomAnchoredAt: re-derives panX/panY from scratch at
     * every intermediate zoom value of the eased interpolation (rather than interpolating
     * panX/panY directly, which would NOT keep the anchor point fixed on screen, since the
     * anchoring relationship between pan and zoom is not linear) — so the point under the
     * cursor stays visually pinned for the whole animation, not just at its start and end.
     */
    animateZoomAnchored(svgX, svgY, fracX, fracY, targetZoom) {
        if (this.zoomAnimationHandle) {
            cancelAnimationFrame(this.zoomAnimationHandle);
        }
        const startZoom = this.zoom;
        const startTime = Date.now();
        const step = () => {
            const elapsed = Date.now() - startTime;
            const t = Math.min(1, elapsed / ZOOM_ANIMATION_MS);
            const eased = 1 - (1 - t) * (1 - t);
            const currentZoom = startZoom + (targetZoom - startZoom) * eased;
            this.applyZoomAnchoredAt(svgX, svgY, currentZoom, fracX, fracY);
            if (t < 1) {
                this.zoomAnimationHandle = requestAnimationFrame(step);
            } else {
                this.zoomAnimationHandle = null;
                this.dispatchEvent(new CustomEvent('viewportchange', { detail: { panX: this.panX, panY: this.panY, zoom: this.zoom } }));
            }
        };
        this.zoomAnimationHandle = requestAnimationFrame(step);
    }

    handleZoomInClick() {
        this.cancelMomentum();
        this.animateZoomToCenter(Math.min(MAX_ZOOM, this.zoom + ZOOM_BUTTON_STEP));
    }

    handleZoomOutClick() {
        this.cancelMomentum();
        this.animateZoomToCenter(Math.max(MIN_ZOOM, this.zoom - ZOOM_BUTTON_STEP));
    }

    handleResetViewClick() {
        this.cancelMomentum();
        this.animateTo(0, 0, 1);
    }

    /** Fits the viewport to whatever is currently loaded (not the theoretical whole graph — this is a client-local view concern, per the class's own §17 framing) — the bounding box of every positioned item's actual footprint, not just center points, so a wide schema card at the edge is never clipped. */
    handleFitToScreenClick() {
        this.cancelMomentum();
        const positioned = this.positionedNodes;
        if (positioned.length === 0) {
            return;
        }
        const minX = Math.min(...positioned.map((n) => n.x));
        const maxX = Math.max(...positioned.map((n) => n.x + n.width));
        const minY = Math.min(...positioned.map((n) => n.y));
        const maxY = Math.max(...positioned.map((n) => n.y + n.height));
        const contentWidth = Math.max(maxX - minX, 1);
        const contentHeight = Math.max(maxY - minY, 1);
        const targetZoom = Math.min(
            MAX_ZOOM,
            Math.max(MIN_ZOOM, Math.min(VIEW_WIDTH / (contentWidth * FIT_TO_SCREEN_PADDING), VIEW_HEIGHT / (contentHeight * FIT_TO_SCREEN_PADDING)))
        );
        const targetPanX = (minX + maxX) / 2 - VIEW_WIDTH / 2;
        const targetPanY = (minY + maxY) / 2 - VIEW_HEIGHT / 2;
        this.animateTo(targetPanX, targetPanY, targetZoom);
    }

    /** Recenters on whatever is currently selected without changing zoom — "bring it back into view" rather than "zoom to it," since the user's current zoom level was itself a deliberate choice. */
    handleCenterOnSelectedClick() {
        this.cancelMomentum();
        const selected = this.positionedNodes.find((n) => n.nodeKey === this.selectedNodeKey);
        if (!selected) {
            return;
        }
        this.animateTo(selected.cx - VIEW_WIDTH / 2, selected.cy - VIEW_HEIGHT / 2, this.zoom);
    }

    /** Discards every manual node drag, snapping back to the pure computed radial layout — distinct from "Reset view," which only resets pan/zoom and leaves manually-dragged node positions alone. Reassigning manualOffsets (rather than mutating it) is what invalidates getLayout()'s memoized result — see getLayout()'s own doc comment. */
    handleResetLayoutClick() {
        this.manualOffsets = new Map();
    }

    /**
     * Button-triggered zoom stays anchored on whatever is currently at the viewport's
     * center — the natural "zoom toward what I'm looking at" behavior a map's own +/-
     * controls have. viewBoxRect's own formula makes a viewport's world-space center exactly
     * `panX + VIEW_WIDTH/2` regardless of zoom, so panX/panY themselves don't need to change
     * at all to keep that same point centered — only zoom does.
     */
    animateZoomToCenter(targetZoom) {
        this.animateTo(this.panX, this.panY, targetZoom);
    }

    animateTo(targetPanX, targetPanY, targetZoom) {
        if (this.zoomAnimationHandle) {
            cancelAnimationFrame(this.zoomAnimationHandle);
        }
        const startPanX = this.panX;
        const startPanY = this.panY;
        const startZoom = this.zoom;
        const startTime = Date.now();
        const step = () => {
            const elapsed = Date.now() - startTime;
            const t = Math.min(1, elapsed / ZOOM_ANIMATION_MS);
            const eased = 1 - (1 - t) * (1 - t);
            this.panX = startPanX + (targetPanX - startPanX) * eased;
            this.panY = startPanY + (targetPanY - startPanY) * eased;
            this.zoom = startZoom + (targetZoom - startZoom) * eased;
            if (t < 1) {
                this.zoomAnimationHandle = requestAnimationFrame(step);
            } else {
                this.zoomAnimationHandle = null;
                this.dispatchEvent(new CustomEvent('viewportchange', { detail: { panX: this.panX, panY: this.panY, zoom: this.zoom } }));
            }
        };
        this.zoomAnimationHandle = requestAnimationFrame(step);
    }

    /**
     * Path-to-centre highlighting (this sprint's explainability requirement): entering a node
     * focuses the path from it back to the centre; leaving clears the focus back to whatever is
     * selected (activeFocusNodeKey's own fallback), never to nothing while a selection exists —
     * the highlight the user was just shown should not vanish entirely the instant the pointer
     * drifts off the node.
     */
    handleNodeHoverStart(event) {
        this.hoveredNodeKey = event.currentTarget.dataset.nodeKey;
    }

    handleNodeHoverEnd() {
        this.hoveredNodeKey = null;
    }

    /** Starts a manual node drag (§17's "static re-layout" is a computed default; dragging is a user-driven override on top of it) — stops propagation so the canvas doesn't also start panning underneath it. */
    handleNodeDragStart(event) {
        event.stopPropagation();
        this.cancelMomentum();
        this.draggingNodeKey = event.currentTarget.dataset.nodeKey;
        this.dragMoved = false;
        this.lastPointer = { x: event.clientX, y: event.clientY };
    }

    handlePointerDown(event) {
        this.cancelMomentum();
        this.isPanning = true;
        this.lastPointer = { x: event.clientX, y: event.clientY };
        this.pointerHistory = [{ x: event.clientX, y: event.clientY, t: Date.now() }];
    }

    /**
     * Raw pointermove fires far more often than the display can repaint (easily 100+/sec on
     * a modern mouse) — reacting to every one with an immediate @track write would queue a
     * full re-render per event, most of which get thrown away unseen before the next paint.
     * This only accumulates the delta and schedules a single flush on the next animation
     * frame (see scheduleFrameFlush) — the same coalescing pattern behind every smooth
     * drag/pan implementation.
     */
    handlePointerMove(event) {
        if (!this.lastPointer) {
            return;
        }
        const rawDx = event.clientX - this.lastPointer.x;
        const rawDy = event.clientY - this.lastPointer.y;
        const dx = rawDx / this.zoom;
        const dy = rawDy / this.zoom;
        this.lastPointer = { x: event.clientX, y: event.clientY };

        if (this.draggingNodeKey) {
            // Click-vs-drag intent is a screen-space judgment — measured in raw pixels moved, never zoom-scaled world units, so the threshold means the same thing at any zoom level.
            if (Math.abs(rawDx) > DRAG_THRESHOLD_PX || Math.abs(rawDy) > DRAG_THRESHOLD_PX) {
                this.dragMoved = true;
            }
            this.pendingNodeDelta = this.pendingNodeDelta || { dx: 0, dy: 0 };
            this.pendingNodeDelta.dx += dx;
            this.pendingNodeDelta.dy += dy;
            this.scheduleFrameFlush();
            return;
        }
        if (!this.isPanning) {
            return;
        }
        this.pendingPanDelta = this.pendingPanDelta || { dx: 0, dy: 0 };
        this.pendingPanDelta.dx += dx;
        this.pendingPanDelta.dy += dy;
        this.scheduleFrameFlush();
        this.recordPointerHistory(event.clientX, event.clientY);
    }

    /** Keeps a short rolling window of recent raw pointer samples during a pan — the release velocity for momentum coasting (see maybeStartMomentum) needs a recent, real gesture speed, not the average of the whole drag from wherever it started. */
    recordPointerHistory(clientX, clientY) {
        const now = Date.now();
        this.pointerHistory.push({ x: clientX, y: clientY, t: now });
        while (this.pointerHistory.length > 1 && now - this.pointerHistory[0].t > POINTER_HISTORY_WINDOW_MS) {
            this.pointerHistory.shift();
        }
    }

    scheduleFrameFlush() {
        if (this.frameHandle) {
            return;
        }
        this.frameHandle = requestAnimationFrame(() => {
            this.frameHandle = null;
            this.flushPendingMovement();
        });
    }

    /** Applies whatever pan/drag delta has accumulated since the last flush, then clears it — called both from the once-per-frame scheduler and, synchronously, on pointerup so the final few pixels of a fast gesture are never dropped. */
    flushPendingMovement() {
        if (this.pendingPanDelta) {
            this.panX -= this.pendingPanDelta.dx;
            this.panY -= this.pendingPanDelta.dy;
            this.pendingPanDelta = null;
        }
        if (this.pendingNodeDelta && this.draggingNodeKey) {
            const updated = new Map(this.manualOffsets);
            const existing = updated.get(this.draggingNodeKey) || { dx: 0, dy: 0 };
            updated.set(this.draggingNodeKey, { dx: existing.dx + this.pendingNodeDelta.dx, dy: existing.dy + this.pendingNodeDelta.dy });
            this.manualOffsets = updated;
            this.pendingNodeDelta = null;
        }
    }

    handlePointerUp() {
        if (this.frameHandle) {
            cancelAnimationFrame(this.frameHandle);
            this.frameHandle = null;
        }
        this.flushPendingMovement();
        if (this.draggingNodeKey) {
            this.draggingNodeKey = null;
            this.lastPointer = null;
            return;
        }
        const wasPanning = this.isPanning;
        this.isPanning = false;
        this.lastPointer = null;
        if (wasPanning && this.maybeStartMomentum()) {
            return;
        }
        this.dispatchEvent(new CustomEvent('viewportchange', { detail: { panX: this.panX, panY: this.panY, zoom: this.zoom } }));
    }

    /**
     * A fast drag-release ("flick") keeps gliding under simulated friction instead of
     * stopping dead the instant the pointer lifts — the specific Google-Maps behavior users
     * mean by "glide." Returns true when a coast actually started (so the caller can skip
     * its own immediate viewportchange dispatch — startMomentum dispatches its own once the
     * coast settles).
     */
    maybeStartMomentum() {
        const history = this.pointerHistory;
        this.pointerHistory = [];
        if (history.length < 2) {
            return false;
        }
        const first = history[0];
        const last = history[history.length - 1];
        const dt = last.t - first.t;
        if (dt <= 0) {
            return false;
        }
        // Screen-space release velocity converted to world units, exactly like a live pan delta (see handlePointerMove) — so coasting at a given zoom covers screen distance consistently with however fast dragging itself already feels at that zoom.
        const worldVx = (last.x - first.x) / dt / this.zoom;
        const worldVy = (last.y - first.y) / dt / this.zoom;
        if (Math.hypot(worldVx, worldVy) < MOMENTUM_MIN_VELOCITY) {
            return false;
        }
        this.startMomentum(worldVx, worldVy);
        return true;
    }

    /** Decelerates a released flick to a clean, predictable stop at a constant rate (a simulated-friction "coast," not an exponential one that technically never quite reaches zero) — direction is fixed at release; only speed decays. */
    startMomentum(vx, vy) {
        this.cancelMomentum();
        const direction = Math.hypot(vx, vy) || 1;
        const dirX = vx / direction;
        const dirY = vy / direction;
        let speed = Math.hypot(vx, vy);
        let lastTime = Date.now();
        const step = () => {
            const now = Date.now();
            const dt = now - lastTime;
            lastTime = now;
            this.panX -= dirX * speed * dt;
            this.panY -= dirY * speed * dt;
            speed = Math.max(0, speed - MOMENTUM_DECELERATION * dt);
            if (speed <= 0) {
                this.momentumHandle = null;
                this.dispatchEvent(new CustomEvent('viewportchange', { detail: { panX: this.panX, panY: this.panY, zoom: this.zoom } }));
                return;
            }
            this.momentumHandle = requestAnimationFrame(step);
        };
        this.momentumHandle = requestAnimationFrame(step);
    }

    /** Interrupts an in-flight coast the instant any other interaction begins (a new pan/drag, a button/wheel/double-click zoom) — a momentum loop fighting a fresh, deliberate gesture for control of panX/panY would feel broken, not smooth. */
    cancelMomentum() {
        if (this.momentumHandle) {
            cancelAnimationFrame(this.momentumHandle);
            this.momentumHandle = null;
        }
    }
}

/** Standard axis-aligned-bounding-box overlap test between a positioned item's own footprint (x/y/width/height, already computed by placeItem) and the current virtualization window — a plain rectangle intersection, not a center-point check, so a wide schema card straddling the window's edge is never culled just because its center happens to fall outside it. */
function boxIntersectsWindow(item, window) {
    return item.x + item.width >= window.minX && item.x <= window.maxX && item.y + item.height >= window.minY && item.y <= window.maxY;
}

/** A cheap O(n) pass over already-computed base positions — never touches ring assignment or clustering, so dragging one node costs one array map, not a full re-layout. */
function applyManualOffsets(base, manualOffsets) {
    const positioned = base.positioned.map((item) => {
        const offset = manualOffsets.get(item.nodeKey);
        if (!offset) {
            return item;
        }
        const cx = item.cx + offset.dx;
        const cy = item.cy + offset.dy;
        return { ...item, cx, cy, x: cx - item.width / 2, y: cy - item.height / 2 };
    });
    return {
        positioned,
        clusterEdges: base.clusterEdges,
        fieldOwnerByFieldKey: base.fieldOwnerByFieldKey,
        treeEdgeKeys: base.treeEdgeKeys
    };
}

/** Mean direction of a set of angles via unit-vector sum (atan2 of summed sin/cos) — the
 * standard way to average angles correctly across the 0/2π wraparound, unlike a plain
 * arithmetic mean which breaks near that seam. Returns null for an empty set or one whose
 * directions cancel out exactly (e.g. two neighbors at exactly opposite angles) — callers must
 * treat null as "no clear target," not zero. */
function circularMean(angles) {
    if (!angles.length) {
        return null;
    }
    let sumX = 0;
    let sumY = 0;
    for (const angle of angles) {
        sumX += Math.cos(angle);
        sumY += Math.sin(angle);
    }
    if (Math.abs(sumX) < 1e-9 && Math.abs(sumY) < 1e-9) {
        return null;
    }
    return Math.atan2(sumY, sumX);
}

function normalizeAngle(angle) {
    const twoPi = 2 * Math.PI;
    let normalized = angle % twoPi;
    if (normalized < 0) {
        normalized += twoPi;
    }
    return normalized;
}

/** The v1 sequential arc-slicing formula, factored out so both the initial baseline
 * (computeBaseLayout's pass 2) and every relaxation sweep's re-slice (pass 3) share one
 * implementation instead of two copies that could drift apart. Mutates angleByKey in place;
 * always produces a non-overlapping angle for every item, in whatever order ringItems is
 * currently in — overlap-safety never depends on that order being any particular one. */
function assignSequentialRingAngles(ringItems, footprintByKey, angleByKey) {
    const footprints = ringItems.map((item) => footprintByKey.get(item.nodeKey));
    const totalSpan = footprints.reduce((sum, f) => sum + f.width + NODE_GAP, 0);
    let cursorAngle = -Math.PI / 2;
    ringItems.forEach((item, index) => {
        const footprint = footprints[index];
        const angleSlice = ((footprint.width + NODE_GAP) / totalSpan) * (2 * Math.PI);
        const angle = cursorAngle + angleSlice / 2;
        cursorAngle += angleSlice;
        angleByKey.set(item.nodeKey, angle);
    });
}

/** The barycenter crossing-reduction heuristic (see computeBaseLayout's Pass 3 doc comment).
 * Each item's sort key is the circular mean of its STRICTLY-INNER-ring neighbors' current
 * angles — real graph adjacency, filtered to ring(neighbor) < ring, never same-ring or outer
 * (that restriction is what makes the relaxation converge instead of oscillate — see the doc
 * comment). An item with no qualifying neighbor yet (only connected to the angle-less center,
 * or to same/outer-ring nodes) keeps its own current angle as the sort key, which reproduces
 * its existing relative order exactly — a stable no-op, never an arbitrary jump. */
function sortRingByBarycenter(ringItems, ring, angleByKey, ringOfKey, layoutAdjacency) {
    const scored = ringItems.map((item, originalIndex) => {
        const neighborAngles = (layoutAdjacency.get(item.nodeKey) || [])
            .filter((neighborKey) => (ringOfKey.has(neighborKey) ? ringOfKey.get(neighborKey) : Infinity) < ring)
            .map((neighborKey) => angleByKey.get(neighborKey))
            .filter((angle) => angle !== undefined);
        const mean = circularMean(neighborAngles);
        const sortAngle = normalizeAngle(mean !== null ? mean : angleByKey.get(item.nodeKey));
        return { item, originalIndex, sortAngle };
    });
    scored.sort((a, b) => a.sortAngle - b.sortAngle || a.originalIndex - b.originalIndex);
    return scored.map((entry) => entry.item);
}

/** The box a display item needs — a pill for a plain node/cluster, or a slightly larger schema-card for an Object node (header + subheader + field-count line — height is fixed either way, since the card no longer lists fields; see oiSchemaObjectCard.js). Width scales with the item's own label length within a min/max clamp (see the sizing constants above) instead of a single fixed constant, so a short label isn't stranded in an oversized box and a long one isn't truncated well before it needs to be. Never a hardcoded typeKey check: driven purely by the registry-resolved showFieldList flag already carried on the item. */
function itemFootprint(item) {
    if (!item.showFieldList) {
        const widestLine = longerOfTwoLines(item.label, item.secondaryKey);
        return { width: estimateLabelWidth(widestLine, NODE_LABEL_CHROME_PX, MIN_NODE_WIDTH, MAX_NODE_WIDTH), height: NODE_HEIGHT };
    }
    /**
     * Unlike the plain node above, a schema card's header (label) and subheader (secondaryKey)
     * are two structurally different rows with two different chrome budgets — the subheader
     * shares no icon/toggle/flex-gap space with anything (oiSchemaObjectCard.html/css). Sizing
     * off the label alone (as an earlier version did) meant a long API-name secondaryKey could
     * still get force-truncated even though the card had every reason to simply be wider.
     */
    const headerWidth = estimateLabelWidth(item.label, SCHEMA_CARD_LABEL_CHROME_PX, MIN_SCHEMA_CARD_WIDTH, MAX_SCHEMA_CARD_WIDTH);
    const subheaderWidth = item.secondaryKey
        ? estimateLabelWidth(item.secondaryKey, SCHEMA_CARD_SECONDARY_CHROME_PX, MIN_SCHEMA_CARD_WIDTH, MAX_SCHEMA_CARD_WIDTH)
        : MIN_SCHEMA_CARD_WIDTH;
    return { width: Math.max(headerWidth, subheaderWidth), height: SCHEMA_CARD_HEIGHT };
}

/** The box must fit whichever of the two stacked lines is longer — a record's secondaryKey ("Contact 003xx...") can easily outrun a short label ("Jo"), and the reverse is just as common, so width can never be derived from the primary label alone once a second line exists. */
function longerOfTwoLines(label, secondaryKey) {
    const labelText = label || '';
    const secondaryText = secondaryKey || '';
    return secondaryText.length > labelText.length ? secondaryText : labelText;
}

function estimateLabelWidth(label, chromePx, minWidth, maxWidth) {
    const estimated = (label ? label.length : 0) * AVG_CHAR_PX + chromePx;
    return Math.max(minWidth, Math.min(maxWidth, estimated));
}

/** A gentle quadratic curve through the midpoint, offset perpendicular to the source->target line — reads as a deliberate connection rather than a raw wireframe segment, and keeps overlapping radial edges visually distinguishable from one another. */
/** parallelOffset (px, signed) separates duplicate relationships sharing the same two endpoints — see buildParallelEdgeIndex's own doc comment for why this is necessary; zero for the common, non-duplicate case, so every existing single-edge curve is pixel-identical to before this parameter existed. */
function curvedPath(x1, y1, x2, y2, parallelOffset = 0) {
    const dx = x2 - x1;
    const dy = y2 - y1;
    const length = Math.hypot(dx, dy) || 1;
    const midX = (x1 + x2) / 2;
    const midY = (y1 + y2) / 2;
    const bow = Math.min(length * 0.12, 24) + parallelOffset;
    const offsetX = (-dy / length) * bow;
    const offsetY = (dx / length) * bow;
    return `M${x1},${y1} Q${midX + offsetX},${midY + offsetY} ${x2},${y2}`;
}

/**
 * Where an edge's visible label sits: the same midpoint+perpendicular-offset math curvedPath
 * uses for its control point (so the label tracks the curve's own bow, parallelOffset included),
 * pushed out a further fixed distance so the text sits beside the line rather than directly on
 * top of the stroke.
 */
function edgeLabelPosition(x1, y1, x2, y2, parallelOffset = 0) {
    const dx = x2 - x1;
    const dy = y2 - y1;
    const length = Math.hypot(dx, dy) || 1;
    const midX = (x1 + x2) / 2;
    const midY = (y1 + y2) / 2;
    const bow = Math.min(length * 0.12, 24) + EDGE_LABEL_OFFSET_PX + parallelOffset;
    return {
        x: midX + (-dy / length) * bow,
        y: midY + (dx / length) * bow
    };
}
