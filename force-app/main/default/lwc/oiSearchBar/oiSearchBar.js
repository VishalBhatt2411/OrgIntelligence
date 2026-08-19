/**
 * Purpose: Search integration (GraphUI.md §8) — a container: calls OI_SearchController
 *          only, never resolves a result into the graph itself. Selecting a result emits
 *          `select`; the shell (oiGraphExplorer) issues its own, independent
 *          getGraphFragment/getNodeDetail call — the literal enforcement of "search and
 *          graph traversal remain separate concerns."
 * Responsibilities: Also scopes results to the parent's current Analyze mode
 *                    (typeKeyFilter) — client-side, since OI_SearchController has no
 *                    type-filter parameter of its own — and resolves each result's raw
 *                    typeKey to a human-readable label via the already-loaded Presentation
 *                    Type Registry, so a viewer never has to read a raw
 *                    "SalesforceMetadata.CustomObject"-shaped string.
 * Limitations: Backed by OI_SearchController's minimal MVP search (see that class's own
 *              doc comment) — not the full, unbuilt SearchEngine.md epic. No ranking, no
 *              Record domain, no multi-domain result grouping.
 */
import { LightningElement, api, track } from 'lwc';
import search from '@salesforce/apex/OI_SearchController.search';
import { resolveNodeStyle } from 'c/presentationRegistry';

const DEBOUNCE_MS = 300;

export default class OiSearchBar extends LightningElement {
    @api placeholderText = 'Search objects, fields, classes...';
    @api typeKeyFilter = null;
    @api registry = null;

    @track results = [];
    @track isSearching = false;
    @track errorMessage = null;
    queryTerm = '';
    debounceTimer;

    handleInputChange(event) {
        this.queryTerm = event.target.value;
        clearTimeout(this.debounceTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation -- debounce is intrinsic to search-as-you-type; no timer-free alternative exists for this.
        this.debounceTimer = setTimeout(() => this.runSearch(), DEBOUNCE_MS);
    }

    /** An explicit, immediate trigger — never dependent on oninput/debounce timing, so search always has a deterministic, click-driven path. */
    handleSearchButtonClick() {
        clearTimeout(this.debounceTimer);
        this.runSearch();
    }

    async runSearch() {
        if (!this.queryTerm || this.queryTerm.trim().length === 0) {
            this.results = [];
            this.errorMessage = null;
            return;
        }
        this.isSearching = true;
        this.errorMessage = null;
        try {
            const rawResults = await search({ queryTerm: this.queryTerm });
            this.results = this.typeKeyFilter ? (rawResults || []).filter((r) => r.typeKey === this.typeKeyFilter) : rawResults;
        } catch (error) {
            this.results = [];
            this.errorMessage = (error && error.body && error.body.message) || 'Something went wrong searching. Please try again.';
        } finally {
            this.isSearching = false;
        }
    }

    get hasResults() {
        return this.results && this.results.length > 0;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    /** Enriches each raw result with a human-readable type label — never rendering the raw typeKey directly. */
    get displayResults() {
        return (this.results || []).map((result) => ({
            ...result,
            typeLabel: resolveNodeStyle(this.registry, result.typeKey).displayLabel || result.typeKey
        }));
    }

    handleResultClick(event) {
        const nodeKey = event.currentTarget.dataset.nodeKey;
        this.results = [];
        this.queryTerm = '';
        this.dispatchEvent(new CustomEvent('select', { detail: { nodeKey } }));
    }
}
