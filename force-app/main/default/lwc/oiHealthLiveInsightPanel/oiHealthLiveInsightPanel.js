/**
 * Purpose: The live, always-available detail view for one breakdown/KPI-drill-down row that
 *          has no persisted OI_Org_Health_Finding__c yet — what a user sees today clicking a
 *          "needs attention" row before anyone has run "Sync findings" for this section.
 *          Previously that click showed a single dead-end sentence ("No finding is on file for
 *          this component yet"); this shows the same live evidence the row's own severity
 *          badge was already computed from, plus a jump to the affected component, so a click
 *          is never a dead end.
 * Responsibilities: Render one caller-supplied breakdown row (label, severity, metric values,
 *                    explanation) and resolve "Open object" via
 *                    OI_OrgHealthController.getFindingComponentNavigation using the row's own
 *                    key as the componentKey — the same Apex method oiHealthFindingDrawer uses,
 *                    reused here because it already works for ANY graph component key, not only
 *                    ones with a persisted finding. Never calls updateFindingStatus, related
 *                    findings, or history — there is no finding record yet to attach any of
 *                    those to; a `sync` event lets the container offer that as a next step.
 * Dependencies: OI_OrgHealthController.getFindingComponentNavigation, c/metadataNavigation,
 *               lightning/navigation, c/oiHealthSeverityBadge, c/oiStateBanner.
 * Limitations: Read-only. Triage, history, and related findings all require a persisted finding
 *              record and belong to oiHealthFindingDrawer once one exists.
 */
import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getFindingComponentNavigation from "@salesforce/apex/OI_OrgHealthController.getFindingComponentNavigation";
import { navigateToTarget } from "c/metadataNavigation";

export default class OiHealthLiveInsightPanel extends NavigationMixin(
  LightningElement
) {
  /** { key, primaryLabel, metricValues: [{key,value}], severityKey, severityLabel, explanation }. */
  @api row;
  /** Column labels lining up positionally with row.metricValues, e.g. ['Fields', 'Degree']. */
  @api metricColumnLabels = [];
  /** Shown in the header eyebrow, e.g. "Metadata Health". */
  @api sectionLabel;
  /** Whether the running user may trigger a sync — hides the CTA entirely rather than showing a button that will just fail permission. */
  @api canSync = false;
  @api isSyncing = false;

  navigationError;
  navigationState = "error";

  get hasRow() {
    return !!this.row;
  }

  get metricRows() {
    if (!this.row) {
      return [];
    }
    return (this.row.metricValues || []).map((metric, index) => ({
      key: metric.key || index,
      label: this.metricColumnLabels[index] || metric.key,
      value: metric.value
    }));
  }

  get hasMetricRows() {
    return this.metricRows.length > 0;
  }

  get syncButtonLabel() {
    return this.isSyncing ? "Syncing findings…" : "Sync findings to track this";
  }

  handleClose() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  handleKeyDown(event) {
    if (event.key === "Escape") {
      this.handleClose();
    }
  }

  handleSync() {
    this.dispatchEvent(new CustomEvent("sync"));
  }

  async handleOpenComponent() {
    this.navigationError = undefined;
    this.navigationState = "error";
    if (!this.row || !this.row.key) {
      this.navigationState = "not-obtainable";
      this.navigationError =
        "This row is not tied to a specific graph component, so there is nothing to open.";
      return;
    }
    try {
      const target = await getFindingComponentNavigation({
        componentKey: this.row.key
      });
      const result = navigateToTarget(this, target);
      if (result.message) {
        this.navigationError = result.message;
      }
    } catch (error) {
      this.navigationError =
        (error && error.body && error.body.message) ||
        "Something went wrong opening this component.";
    }
  }
}
