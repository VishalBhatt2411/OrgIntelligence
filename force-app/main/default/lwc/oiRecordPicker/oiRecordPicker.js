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
 *                    second lookup just to echo a name back to the user. Also mirrors
 *                    oiSearchBar's click-to-browse panel: on focus, with nothing typed yet,
 *                    loads and shows a bounded alphabetical record list (cached per
 *                    objectApiName) so the box is never an empty box; typing then instantly
 *                    filters that same list client-side while the existing debounced server
 *                    search runs in the background and supersedes it with the authoritative
 *                    match once it resolves.
 * Dependencies: OI_RecordSearchController.
 * Limitations: type="search" lightning-input only ever fires a `change` event, never
 *              `input`, on the real platform (confirmed empirically fixing oiSearchBar's
 *              own identical bug) — bound to onchange here from the start, not oninput. The
 *              browse panel is bounded and alphabetical only, not a promise of exhaustiveness.
 */
import { LightningElement, api, track } from "lwc";
import searchRecords from "@salesforce/apex/OI_RecordSearchController.searchRecords";
import browseRecords from "@salesforce/apex/OI_RecordSearchController.browseRecords";

const DEBOUNCE_MS = 300;
const PANEL_CLOSE_DELAY_MS = 150;

export default class OiRecordPicker extends LightningElement {
  @api objectApiName;
  @api placeholderText = "Search records...";

  @track results = [];
  @track isSearching = false;
  @track errorMessage = null;
  queryTerm = "";
  debounceTimer;
  browseResults = [];
  isPanelOpen = false;
  browseCacheKey;

  /** Typing implies the box is focused and its panel should be open — covers callers (and tests) that drive input changes without a separate focus event. */
  handleInputChange(event) {
    this.queryTerm = event.target.value;
    this.isPanelOpen = true;
    this.results = this.hasQueryTerm
      ? this.filterBrowseResults(this.queryTerm)
      : this.browseResults;
    clearTimeout(this.debounceTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- debounce is intrinsic to search-as-you-type; no timer-free alternative exists for this.
    this.debounceTimer = setTimeout(() => this.runSearch(), DEBOUNCE_MS);
  }

  /** Opens the panel and, with nothing typed yet, loads the alphabetical browse list — so clicking into an empty box is never a dead end. */
  handleFocus() {
    this.isPanelOpen = true;
    if (!this.hasQueryTerm) {
      this.loadBrowseResults();
    }
  }

  /** Delayed so a result button's click (which also blurs the input) still registers before the panel disappears. */
  handleBlur() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- a brief delay lets an option's click register before the panel closes on blur; no timer-free alternative exists for this standard combobox pattern.
    setTimeout(() => {
      this.isPanelOpen = false;
    }, PANEL_CLOSE_DELAY_MS);
  }

  /** An explicit, immediate trigger — never dependent on onchange/debounce timing. */
  handleSearchButtonClick() {
    clearTimeout(this.debounceTimer);
    this.runSearch();
  }

  async runSearch() {
    if (!this.hasQueryTerm) {
      this.results = this.browseResults;
      this.errorMessage = null;
      return;
    }
    this.isSearching = true;
    this.errorMessage = null;
    try {
      this.results = await searchRecords({
        objectApiName: this.objectApiName,
        queryTerm: this.queryTerm
      });
    } catch (error) {
      this.results = [];
      this.errorMessage =
        (error && error.body && error.body.message) ||
        "Something went wrong searching records. Please try again.";
    } finally {
      this.isSearching = false;
    }
  }

  /** Loads the bounded alphabetical browse list for the current objectApiName, caching it so refocusing the same object doesn't re-fetch. */
  async loadBrowseResults() {
    if (!this.objectApiName) {
      return;
    }
    if (
      this.browseCacheKey === this.objectApiName &&
      this.browseResults.length > 0
    ) {
      if (!this.hasQueryTerm) {
        this.results = this.browseResults;
      }
      return;
    }
    this.isSearching = true;
    this.errorMessage = null;
    try {
      this.browseResults =
        (await browseRecords({ objectApiName: this.objectApiName })) || [];
      this.browseCacheKey = this.objectApiName;
      if (!this.hasQueryTerm) {
        this.results = this.browseResults;
      }
    } catch (error) {
      this.browseResults = [];
      this.errorMessage =
        (error && error.body && error.body.message) ||
        "Something went wrong loading records. Please try again.";
    } finally {
      this.isSearching = false;
    }
  }

  /** Instant client-side substring filter of the already-loaded browse list — shown immediately on each keystroke, ahead of the debounced server search which then supersedes it with the authoritative result. */
  filterBrowseResults(term) {
    const lower = term.trim().toLowerCase();
    return (this.browseResults || []).filter((record) =>
      (record.label || "").toLowerCase().includes(lower)
    );
  }

  get hasQueryTerm() {
    return !!(this.queryTerm && this.queryTerm.trim().length > 0);
  }

  /** The browse list (blank query) only shows while the panel is open (focused); a typed search's results show regardless, matching the prior, already-tested behavior. */
  get hasResults() {
    if (this.hasQueryTerm) {
      return this.results && this.results.length > 0;
    }
    return this.isPanelOpen && this.results && this.results.length > 0;
  }

  get hasError() {
    return !!this.errorMessage;
  }

  get displayResults() {
    return (this.results || []).map((result) => ({
      ...result,
      initials: (result.label || this.objectApiName || "R")
        .split(/\s+/)
        .filter(Boolean)
        .slice(0, 2)
        .map((word) => word[0])
        .join("")
        .toUpperCase()
    }));
  }

  handleResultClick(event) {
    const recordId = event.currentTarget.dataset.recordId;
    const result = (this.results || []).find(
      (candidate) => candidate.recordId === recordId
    );
    this.results = [];
    this.isPanelOpen = false;
    this.queryTerm = "";
    this.dispatchEvent(
      new CustomEvent("select", {
        detail: { recordId, label: result ? result.label : null }
      })
    );
  }
}
