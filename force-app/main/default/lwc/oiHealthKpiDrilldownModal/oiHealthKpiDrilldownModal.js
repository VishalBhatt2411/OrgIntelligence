/**
 * Purpose: The full object list behind one Metadata Health KPI tile (e.g. "High field-count
 *          objects: 12") — the drill-down a click on that tile opens, since the aggregate count
 *          never corresponds 1:1 with the breakdown table's own top-8 rows.
 * Responsibilities: Own the loading/error states for OI_OrgHealthController.getMetadataHealthKpiDrilldown
 *                    and render the result via the same oiHealthBreakdownList used everywhere else,
 *                    with clickable rows re-emitted upward as rowselect so the container resolves
 *                    row clicks exactly the way it already does for the main breakdown table.
 * Dependencies: OI_OrgHealthController.getMetadataHealthKpiDrilldown, c/oiHealthBreakdownList,
 *               c/oiSkeleton, c/oiStateBanner.
 * Limitations: Read-only. Does not cache across metricKey changes — a new metricKey triggers a
 *              fresh Apex call, which is correct since each KPI tile's list is independent.
 */
import { LightningElement, api } from "lwc";
import getMetadataHealthKpiDrilldown from "@salesforce/apex/OI_OrgHealthController.getMetadataHealthKpiDrilldown";

export default class OiHealthKpiDrilldownModal extends LightningElement {
  _metricKey;

  @api
  get metricKey() {
    return this._metricKey;
  }

  set metricKey(value) {
    this._metricKey = value;
    if (value) {
      this.load(value);
    }
  }

  isLoading = false;
  loadError;
  drilldown;

  async load(metricKey) {
    this.isLoading = true;
    this.loadError = undefined;
    this.drilldown = undefined;
    try {
      this.drilldown = await getMetadataHealthKpiDrilldown({ metricKey });
    } catch (error) {
      this.loadError =
        (error && error.body && error.body.message) ||
        "Something went wrong loading this list.";
    } finally {
      this.isLoading = false;
    }
  }

  get hasError() {
    return !!this.loadError;
  }

  get hasDrilldown() {
    return !this.isLoading && !this.hasError && !!this.drilldown;
  }

  get title() {
    return this.drilldown ? this.drilldown.title : "";
  }

  get rows() {
    return this.drilldown ? this.drilldown.rows : [];
  }

  handleRetry() {
    this.load(this._metricKey);
  }

  handleClose() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  handleKeyDown(event) {
    if (event.key === "Escape") {
      this.handleClose();
    }
  }

  handleRowSelect(event) {
    this.dispatchEvent(new CustomEvent("rowselect", { detail: event.detail }));
  }
}
