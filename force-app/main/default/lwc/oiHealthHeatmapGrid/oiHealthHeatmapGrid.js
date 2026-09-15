/**
 * Purpose: Org Health's signal heatmap (OrgHealthVisualDesignSpecification.md) — a compact
 *          companion to oiHealthBreakdownList, showing the same rows' per-metric severity as
 *          colored cells rather than a table row.
 * Responsibilities: Render a caller-supplied grid of { rowLabel, cells: [{key, value,
 *                    severityKey}] }. Column labels and cell severities are entirely
 *                    caller-driven — this component never computes a threshold itself.
 */
import { LightningElement, api } from "lwc";

const CELL_CLASS = {
  Good: "oi-health-heat-cell oi-health-heat-cell_good",
  Warning: "oi-health-heat-cell oi-health-heat-cell_warning",
  Critical: "oi-health-heat-cell oi-health-heat-cell_critical"
};

function withCellClass(cell) {
  return {
    ...cell,
    cellClass: CELL_CLASS[cell.severityKey] || "oi-health-heat-cell"
  };
}

export default class OiHealthHeatmapGrid extends LightningElement {
  @api title;
  @api columnLabels = [];
  _rows = [];

  @api
  get rows() {
    return this._rows;
  }
  set rows(value) {
    this._rows = (value || []).map((row) => ({
      ...row,
      cells: (row.cells || []).map(withCellClass)
    }));
  }

  get gridStyle() {
    return `grid-template-columns: 1fr repeat(${this.columnLabels.length}, 2.6rem);`;
  }
}
