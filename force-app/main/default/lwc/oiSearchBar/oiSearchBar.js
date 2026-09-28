/**
 * Purpose: Search integration (GraphUI.md §8) — a container: calls OI_SearchController
 *          only, never resolves a result into the graph itself. Selecting a result emits
 *          `select`; the shell (oiGraphExplorer) issues its own, independent
 *          getGraphFragment/getNodeDetail call — the literal enforcement of "search and
 *          graph traversal remain separate concerns."
 * Responsibilities: Also scopes results to the parent's current Analyze mode
 *                    (typeKeyFilter) — client-side for a typed search (since
 *                    OI_SearchController.search has no type-filter parameter of its own),
 *                    server-side for the browse panel (OI_SearchController.browse does take
 *                    typeKey) — and resolves each result's raw typeKey to a human-readable
 *                    label via the already-loaded Presentation Type Registry, so a viewer
 *                    never has to read a raw "SalesforceMetadata.CustomObject"-shaped string.
 *                    On focus, with nothing typed yet, loads and shows a bounded alphabetical
 *                    "browse" list (cached per typeKeyFilter) so the box is never an empty
 *                    box — typing then instantly filters that same list client-side while the
 *                    existing debounced server search runs in the background and supersedes it
 *                    with the authoritative match once it resolves.
 * Limitations: Backed by OI_SearchController's minimal MVP search (see that class's own
 *              doc comment) — not the full, unbuilt SearchEngine.md epic. No ranking, no
 *              Record domain, no multi-domain result grouping. The browse panel is bounded
 *              (Max_Search_Results__c) and alphabetical only — it is a suggestion list, not a
 *              promise of exhaustiveness.
 */
import { LightningElement, api, track } from "lwc";
import search from "@salesforce/apex/OI_SearchController.search";
import browse from "@salesforce/apex/OI_SearchController.browse";
import { resolveNodeStyle } from "c/presentationRegistry";

const DEBOUNCE_MS = 300;
const PANEL_CLOSE_DELAY_MS = 150;

export default class OiSearchBar extends LightningElement {
  @api placeholderText = "Search objects, fields, classes...";
  @api typeKeyFilter = null;
  @api registry = null;

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

  /** An explicit, immediate trigger — never dependent on oninput/debounce timing, so search always has a deterministic, click-driven path. */
  handleSearchButtonClick() {
    clearTimeout(this.debounceTimer);
    this.runSearch();
  }

  /** Enter is the standard combobox behavior users expect: with suggestions already showing, commit the top one; otherwise run the search immediately rather than waiting on the debounce. */
  handleInputKeyDown(event) {
    if (event.key !== "Enter") {
      return;
    }
    event.preventDefault();
    clearTimeout(this.debounceTimer);
    if (this.hasResults) {
      this.selectResult(this.results[0]);
    } else {
      this.runSearch();
    }
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
      const rawResults = await search({ queryTerm: this.queryTerm });
      this.results = this.typeKeyFilter
        ? (rawResults || []).filter((r) => r.typeKey === this.typeKeyFilter)
        : rawResults;
    } catch (error) {
      this.results = [];
      this.errorMessage =
        (error && error.body && error.body.message) ||
        "Something went wrong searching. Please try again.";
    } finally {
      this.isSearching = false;
    }
  }

  /** Loads the bounded alphabetical browse list for the current typeKeyFilter, caching it so refocusing the same Analyze mode doesn't re-fetch. */
  async loadBrowseResults() {
    const cacheKey = this.typeKeyFilter || "__all__";
    if (this.browseCacheKey === cacheKey && this.browseResults.length > 0) {
      if (!this.hasQueryTerm) {
        this.results = this.browseResults;
      }
      return;
    }
    this.isSearching = true;
    this.errorMessage = null;
    try {
      this.browseResults =
        (await browse({ typeKey: this.typeKeyFilter })) || [];
      this.browseCacheKey = cacheKey;
      if (!this.hasQueryTerm) {
        this.results = this.browseResults;
      }
    } catch (error) {
      this.browseResults = [];
      this.errorMessage =
        (error && error.body && error.body.message) ||
        "Something went wrong loading suggestions. Please try again.";
    } finally {
      this.isSearching = false;
    }
  }

  /** Instant client-side substring filter of the already-loaded browse list — shown immediately on each keystroke, ahead of the debounced server search which then supersedes it with the authoritative result. */
  filterBrowseResults(term) {
    const lower = term.trim().toLowerCase();
    return (this.browseResults || []).filter(
      (node) =>
        (node.label || "").toLowerCase().includes(lower) ||
        (node.secondaryKey || "").toLowerCase().includes(lower)
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

  /** Enriches each raw result with a human-readable type label — never rendering the raw typeKey directly. */
  get displayResults() {
    return (this.results || []).map((result) => {
      const typeLabel =
        resolveNodeStyle(this.registry, result.typeKey).displayLabel ||
        result.typeKey;
      const words = (result.label || typeLabel).split(/\s+/).filter(Boolean);
      return {
        ...result,
        typeLabel,
        secondaryLabel: result.secondaryKey || result.nodeKey,
        initials: words
          .slice(0, 2)
          .map((word) => word[0])
          .join("")
          .toUpperCase()
      };
    });
  }

  handleResultClick(event) {
    const nodeKey = event.currentTarget.dataset.nodeKey;
    const result = (this.results || []).find((r) => r.nodeKey === nodeKey);
    this.selectResult(result || { nodeKey });
  }

  /** Closes the suggestion list and leaves the chosen label visible in the box — the only record of what's currently loaded besides the "Analyzing" pill elsewhere on the page, so it must not revert to the placeholder. */
  selectResult(result) {
    this.results = [];
    this.isPanelOpen = false;
    this.queryTerm = result.label || this.queryTerm;
    this.dispatchEvent(
      new CustomEvent("select", { detail: { nodeKey: result.nodeKey } })
    );
  }
}
