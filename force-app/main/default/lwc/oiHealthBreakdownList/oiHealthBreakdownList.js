/**
 * Purpose: Org Health's ranked breakdown table (OrgHealthVisualDesignSpecification.md) — the
 *          "Objects needing attention" style panel used by scored detail views to show the
 *          real rows behind a score, each with its own severity.
 * Responsibilities: Render a title/coverage caption and a table of caller-supplied rows.
 *                    Column headers are configurable so this one component serves every
 *                    section's breakdown, not just Metadata Health's. When clickable is set,
 *                    a row selection is surfaced as a rowselect event carrying the row's key
 *                    (and, for a caller that needs it without a second lookup, the row's own
 *                    data) — this component never resolves what a row click means (e.g. which
 *                    finding it maps to); that is the container's job (ADR-0027).
 */
import { LightningElement, api } from "lwc";

export default class OiHealthBreakdownList extends LightningElement {
  @api title;
  @api coverageCaption;
  /** Array of { key } — one non-severity column label per entry, e.g. ['Fields', 'Degree']. */
  @api metricColumnLabels = [];
  /**
   * Array of row objects: { key, primaryLabel, metricValues: [{key, value}], severityKey,
   * severityLabel }. metricValues must line up 1:1 with metricColumnLabels.
   */
  @api rows = [];
  /** When true, each row is a button that dispatches rowselect on click — opt-in so sections without a drill-down target render a plain table. */
  @api clickable = false;

  get hasRows() {
    return this.rows && this.rows.length > 0;
  }

  get displayRows() {
    return this.rows.map((row) => ({
      ...row,
      rowClass: this.clickable ? "oi-health-breakdown-row_clickable" : ""
    }));
  }

  handleRowClick(event) {
    if (!this.clickable) {
      return;
    }
    const key = event.currentTarget.dataset.key;
    const row = this.rows.find((candidate) => candidate.key === key);
    this.dispatchEvent(new CustomEvent("rowselect", { detail: { key, row } }));
  }
}
