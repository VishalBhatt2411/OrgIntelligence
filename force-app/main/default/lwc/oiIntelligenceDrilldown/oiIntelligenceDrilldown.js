/**
 * Purpose: The one reusable drill-down surface behind every count in the Intelligence panel —
 *          "Outgoing — Has Field 52" becomes a real, searchable, navigable list of those 52.
 * Responsibilities: Fetch a bounded page of connection rows for a (node, direction, relationship)
 *                    selection, render them as a structured table with search/sort/load-more, and
 *                    navigate when a row is opened. Owns no knowledge of any specific metadata
 *                    type.
 * Dependencies: OI_GraphController.getNodeConnections, OI_GraphController.getNavigationTarget,
 *               c/metadataNavigation.
 *
 * Generic by construction: this component is parameterised by (nodeKey, direction, edgeTypeKey)
 * and renders whatever rows Apex returns, with column visibility driven by whether the data
 * actually carries those values. There is deliberately no `if (category === 'Fields')` anywhere —
 * fields, objects, triggers, flows, permission sets and Apex classes all flow through this same
 * path, so a new metadata type needs no new modal (the user's explicit requirement: no one-off
 * modal code per metric).
 *
 * Search and sort scope — stated honestly rather than implied:
 *  - SEARCH is server-side. It re-queries with the term, so it searches the WHOLE selection, not
 *    just loaded rows, and the header reports a filtered total.
 *  - SORT is client-side over the rows currently loaded. Ordering server-side by neighbour label
 *    is not possible while paging by edge key (the label lives on a different object than the one
 *    being paged), and pretending otherwise would silently mis-order large sets. The UI therefore
 *    says "sorted within loaded results" whenever more rows remain.
 */
import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getNodeConnections from '@salesforce/apex/OI_GraphController.getNodeConnections';
import getNavigationTarget from '@salesforce/apex/OI_GraphController.getNavigationTarget';
import { navigateToTarget } from 'c/metadataNavigation';

const PAGE_SIZE = 100;
/** Debounce for the search box — long enough to avoid a round-trip per keystroke, short enough to feel immediate. */
const SEARCH_DEBOUNCE_MS = 300;

export default class OiIntelligenceDrilldown extends NavigationMixin(LightningElement) {
    /** What the drill-down is anchored to, and which slice of its connections to show. */
    @api nodeKey;
    @api direction;
    @api edgeTypeKey;
    /** Display context for the header — supplied by the opener so this component never has to re-resolve labels. */
    @api anchorLabel;
    @api relationshipLabel;

    @track rows = [];
    totalCount = 0;
    hasMore = false;
    isFiltered = false;
    unavailableReason = null;
    nextCursor = null;
    isLoading = false;
    isLoadingMore = false;
    errorMessage = null;
    searchTerm = '';
    sortField = 'label';
    sortAscending = true;
    actionMessage = null;

    searchTimeout;
    requestId = 0;

    connectedCallback() {
        this.loadFirstPage();
    }

    disconnectedCallback() {
        /** A pending debounce must not fire into a torn-down component — it would resolve against stale state and log an unhandled error. */
        clearTimeout(this.searchTimeout);
    }

    async loadFirstPage() {
        const requestId = ++this.requestId;
        this.isLoading = true;
        this.errorMessage = null;
        this.actionMessage = null;
        try {
            const page = await getNodeConnections({
                nodeKey: this.nodeKey,
                direction: this.direction,
                edgeTypeKey: this.edgeTypeKey,
                pageSize: PAGE_SIZE,
                cursor: null,
                searchTerm: this.searchTerm || null
            });
            if (requestId !== this.requestId) {
                return;
            }
            this.applyPage(page, false);
        } catch (error) {
            if (requestId !== this.requestId) {
                return;
            }
            this.rows = [];
            this.errorMessage = this.extractError(error);
        } finally {
            if (requestId === this.requestId) {
                this.isLoading = false;
            }
        }
    }

    async handleLoadMore() {
        if (!this.hasMore || this.isLoadingMore) {
            return;
        }
        const requestId = this.requestId;
        this.isLoadingMore = true;
        try {
            const page = await getNodeConnections({
                nodeKey: this.nodeKey,
                direction: this.direction,
                edgeTypeKey: this.edgeTypeKey,
                pageSize: PAGE_SIZE,
                cursor: this.nextCursor,
                searchTerm: this.searchTerm || null
            });
            /** A search or a re-open that happened mid-flight invalidates this page — appending it would mix two different result sets into one table. */
            if (requestId !== this.requestId) {
                return;
            }
            this.applyPage(page, true);
        } catch (error) {
            this.errorMessage = this.extractError(error);
        } finally {
            this.isLoadingMore = false;
        }
    }

    applyPage(page, append) {
        const incoming = (page.rows || []).map((row, index) => ({
            ...row,
            /** A stable per-row key for the template. Edge keys are not returned (they are internal), and labels can repeat, so position within the accumulated list is the reliable identity. */
            rowKey: `${append ? this.rows.length + index : index}-${row.nodeKey}`
        }));
        this.rows = append ? [...this.rows, ...incoming] : incoming;
        this.totalCount = page.totalCount;
        this.hasMore = page.hasMore;
        this.nextCursor = page.nextCursor;
        this.isFiltered = page.isFiltered;
        this.unavailableReason = page.unavailableReason || null;
    }

    handleSearchChange(event) {
        const value = event.target.value;
        clearTimeout(this.searchTimeout);
        this.searchTimeout = setTimeout(() => {
            this.searchTerm = value;
            /** A new search is a new result set, so paging restarts rather than continuing from a cursor into different data. */
            this.nextCursor = null;
            this.loadFirstPage();
        }, SEARCH_DEBOUNCE_MS);
    }

    handleSort(event) {
        const field = event.currentTarget.dataset.field;
        if (this.sortField === field) {
            this.sortAscending = !this.sortAscending;
        } else {
            this.sortField = field;
            this.sortAscending = true;
        }
    }

    /** Sorted view of the loaded rows. Nulls always sort last regardless of direction — a blank cell is absence of information, not a value that should lead the table. */
    get sortedRows() {
        const field = this.sortField;
        const factor = this.sortAscending ? 1 : -1;
        return [...this.rows].sort((a, b) => {
            const left = a[field];
            const right = b[field];
            if (left === right) {
                return 0;
            }
            if (left === null || left === undefined) {
                return 1;
            }
            if (right === null || right === undefined) {
                return -1;
            }
            return String(left).localeCompare(String(right)) * factor;
        });
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get isEmpty() {
        return !this.isLoading && !this.errorMessage && !this.unavailableReason && this.rows.length === 0;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get isUnavailable() {
        return !!this.unavailableReason;
    }

    get headerTitle() {
        return this.anchorLabel || 'Connections';
    }

    get headerSubtitle() {
        const relationship = this.relationshipLabel || 'Connections';
        const directionWord = this.direction === 'incoming' ? 'Incoming' : 'Outgoing';
        return `${directionWord} · ${relationship}`;
    }

    /** States the count honestly, including whether it is filtered and whether the table holds everything. */
    get resultSummary() {
        if (this.isLoading) {
            return 'Loading…';
        }
        const noun = this.totalCount === 1 ? 'result' : 'results';
        const base = this.isFiltered ? `${this.totalCount} matching ${noun}` : `${this.totalCount} ${noun}`;
        if (this.rows.length < this.totalCount) {
            return `${base} · showing ${this.rows.length}`;
        }
        return base;
    }

    /** Only claim table-wide sorting when the table actually holds the whole set — otherwise say what the sort really covers. */
    get sortScopeNote() {
        return this.hasMore ? 'Sorting applies to the results loaded so far.' : null;
    }

    get emptyStateMessage() {
        return this.isFiltered ? 'No results match your search.' : 'No connections of this type were found in the scanned data.';
    }

    /** Columns whose data is genuinely present, so a table of Apex classes does not render three permanently-empty field columns. */
    get showDataTypeColumn() {
        return this.rows.some((row) => !!row.dataType);
    }

    get showReferencedObjectColumn() {
        return this.rows.some((row) => !!row.referencedObject);
    }

    async handleRowOpen(event) {
        event.stopPropagation();
        const rowKey = event.currentTarget.dataset.rowKey;
        const row = this.rows.find((candidate) => candidate.rowKey === rowKey);
        if (!row) {
            return;
        }
        this.actionMessage = null;
        try {
            const target = await getNavigationTarget({ typeKey: row.typeKey, apiName: row.apiName });
            const result = navigateToTarget(this, target);
            /** Both outcomes are communicated: an unsupported destination explains itself, and a caveated one says where it actually landed. Silence would read as a broken click. */
            if (result.message) {
                this.actionMessage = result.message;
            }
        } catch (error) {
            this.actionMessage = this.extractError(error);
        }
    }

    /** Selecting a row re-centres the graph instead of leaving Salesforce — the in-product counterpart to "open in Setup". */
    handleRowSelect(event) {
        const rowKey = event.currentTarget.dataset.rowKey;
        const row = this.rows.find((candidate) => candidate.rowKey === rowKey);
        if (row) {
            this.dispatchEvent(new CustomEvent('nodeselect', { detail: { nodeKey: row.nodeKey } }));
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    /** Escape closes the dialog — expected of any modal, and the minimum for keyboard users who cannot reach the close button by pointer. */
    handleKeyDown(event) {
        if (event.key === 'Escape') {
            this.handleClose();
        }
    }

    extractError(error) {
        return (error && error.body && error.body.message) || 'Something went wrong loading these results.';
    }
}
