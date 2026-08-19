/**
 * Purpose: Record search scoped to one already-chosen object (Record Analysis, ADR-0021)
 *          — a container: calls OI_RecordSearchController only, never resolves a result
 *          into the graph itself, mirroring oiSearchBar's own established separation
 *          (selecting a result emits `select`; the shell issues its own, independent
 *          getRecordFragment call).
 * Responsibilities: Debounced-as-you-type search plus an explicit, immediate Search button
 *                    path, identical interaction contract to oiSearchBar. `select` carries both
 *                    `recordId` and `label` (the clicked result's own resolved label) so a
 *                    consumer that only needs to display what was picked — e.g.
 *                    oiHierarchyManager's relationship-assignment form — never has to issue a
 *                    second lookup just to echo a name back to the user.
 * Dependencies: OI_RecordSearchController.
 * Limitations: type="search" lightning-input only ever fires a `change` event, never
 *              `input`, on the real platform (confirmed empirically fixing oiSearchBar's
 *              own identical bug) — bound to onchange here from the start, not oninput.
 */
import { LightningElement, api, track } from 'lwc';
import searchRecords from '@salesforce/apex/OI_RecordSearchController.searchRecords';

const DEBOUNCE_MS = 300;

export default class OiRecordPicker extends LightningElement {
    @api objectApiName;
    @api placeholderText = 'Search records...';

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

    /** An explicit, immediate trigger — never dependent on onchange/debounce timing. */
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
            this.results = await searchRecords({ objectApiName: this.objectApiName, queryTerm: this.queryTerm });
        } catch (error) {
            this.results = [];
            this.errorMessage = (error && error.body && error.body.message) || 'Something went wrong searching records. Please try again.';
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

    handleResultClick(event) {
        const recordId = event.currentTarget.dataset.recordId;
        const result = this.results.find((candidate) => candidate.recordId === recordId);
        this.results = [];
        this.queryTerm = '';
        this.dispatchEvent(new CustomEvent('select', { detail: { recordId, label: result ? result.label : null } }));
    }
}
