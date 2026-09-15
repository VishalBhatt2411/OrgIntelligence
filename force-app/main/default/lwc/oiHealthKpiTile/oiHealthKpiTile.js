/**
 * Purpose: Org Health's small stat tile (OrgHealthVisualDesignSpecification.md) — the KPI
 *          strip on the landing grid and every section detail's headline row.
 * Responsibilities: Render one label/value pair. Presentational only — the caller decides
 *                    what the value string already looks like (formatting, units). Optionally
 *                    interactive: when the caller supplies a metricKey, the tile becomes a
 *                    button that dispatches `select` with that key on click/Enter/Space, so a
 *                    container can open the full object list the aggregate number summarizes
 *                    (e.g. "12 high field-count objects" -> the 12 objects themselves). A tile
 *                    with no metricKey renders exactly as before — this is purely additive so
 *                    every existing non-interactive consumer is unaffected.
 */
import { LightningElement, api } from "lwc";

export default class OiHealthKpiTile extends LightningElement {
  @api label;
  @api value;
  /** When set, this tile is interactive and `select` carries this value. */
  @api metricKey;

  get isClickable() {
    return !!this.metricKey;
  }

  get tileClass() {
    return this.isClickable
      ? "oi-health-kpi-tile oi-health-kpi-tile_clickable"
      : "oi-health-kpi-tile";
  }

  get role() {
    return this.isClickable ? "button" : null;
  }

  get tabIndex() {
    return this.isClickable ? "0" : null;
  }

  handleClick() {
    if (!this.isClickable) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("select", { detail: { metricKey: this.metricKey } })
    );
  }

  handleKeyDown(event) {
    if (!this.isClickable) {
      return;
    }
    if (
      event.key === "Enter" ||
      event.key === " " ||
      event.key === "Spacebar"
    ) {
      event.preventDefault();
      this.handleClick();
    }
  }
}
