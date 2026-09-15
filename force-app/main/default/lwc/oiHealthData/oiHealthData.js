/**
 * Purpose: Org Health's Data Health detail container (ADR-0026 Phase 5, Tier 3 — async,
 *          persisted). The only Org Health section with a real 4-state run-status UX
 *          (not-yet-run / queued-processing / completed / failed) instead of a plain
 *          loading spinner, and the only section with a user-triggered "Recompute" action.
 *          Also wired to the unified finding model (ADR-0027): unlike the Tier-2 live
 *          sections, there is no separate "Sync findings" button here — recomputeDataHealth is
 *          the one write action, and OI_DataHealthComputeBatchable's own finish() already syncs
 *          findings as part of that same bounded async run, so this container only needs to
 *          load and display them.
 * Responsibilities: Call OI_OrgHealthController.getDataHealthDetail, render the correct state
 *                    from the DTO's runStatus, and poll while a run is Queued/Processing —
 *                    never inventing a result for a run that hasn't finished. The last known
 *                    good result (if any) stays visible underneath an in-progress or failed
 *                    banner rather than being replaced by a blank loading state, so a
 *                    recompute never costs the user their last real answer. Never computes a
 *                    score or severity itself. Separately loads this section's findings and
 *                    resolves a clicked breakdown row to the finding(s) for that object, opening
 *                    oiHealthFindingDrawer with the result.
 * Dependencies: OI_OrgHealthController.getDataHealthDetail, OI_OrgHealthController.
 *               recomputeDataHealth, OI_OrgHealthController.getDataHealthFindings, the
 *               OI_Run_Org_Health_Compute custom permission, oiHealthScoreRing, oiHealthKpiTile,
 *               oiHealthFormulaDisclosure, oiHealthBreakdownList, oiHealthHeatmapGrid,
 *               oiHealthFindingDrawer, oiStateBanner, oiSkeleton.
 * Limitations: A breakdown row maps to a finding by Component_Key__c (the object API name),
 *              which this component only knows as the row's own key — a row with no matching
 *              finding (e.g. before the first scan has ever run) shows a short inline note
 *              instead of opening an empty drawer or fabricating one.
 */
import { LightningElement } from "lwc";
import getDataHealthDetail from "@salesforce/apex/OI_OrgHealthController.getDataHealthDetail";
import recomputeDataHealth from "@salesforce/apex/OI_OrgHealthController.recomputeDataHealth";
import getDataHealthFindings from "@salesforce/apex/OI_OrgHealthController.getDataHealthFindings";
import hasRunOrgHealthCompute from "@salesforce/customPermission/OI_Run_Org_Health_Compute";

const POLL_INTERVAL_MS = 5000;
const IN_PROGRESS_STATUSES = new Set(["Queued", "Processing"]);
const FAILED_STATUSES = new Set(["Failed", "Aborted"]);

export default class OiHealthData extends LightningElement {
  isLoading = true;
  loadError;
  detail;
  isRecomputing = false;
  findings = [];
  selectedFinding;
  selectionNote;

  pollTimer;

  connectedCallback() {
    this.load();
  }

  disconnectedCallback() {
    this.stopPolling();
  }

  async load() {
    this.isLoading = true;
    this.loadError = undefined;
    try {
      const [detail, findings] = await Promise.all([
        getDataHealthDetail(),
        getDataHealthFindings()
      ]);
      this.detail = detail;
      this.findings = findings;
      this.syncPolling();
    } catch (error) {
      this.loadError =
        (error && error.body && error.body.message) ||
        "Something went wrong loading Data Health.";
      this.stopPolling();
    } finally {
      this.isLoading = false;
    }
  }

  syncPolling() {
    if (this.isInProgress && !this.pollTimer) {
      // eslint-disable-next-line @lwc/lwc/no-async-operation -- polling an in-progress async compute run is intrinsic here; cleared in stopPolling/disconnectedCallback.
      this.pollTimer = setInterval(() => this.load(), POLL_INTERVAL_MS);
    } else if (!this.isInProgress && this.pollTimer) {
      this.stopPolling();
    }
  }

  stopPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = undefined;
    }
  }

  get canRunCompute() {
    return hasRunOrgHealthCompute;
  }

  get hasError() {
    return !!this.loadError;
  }

  /** A real computation has completed at least once — computedAt is only ever set by buildSnapshotFromSignals, never by the honest "not yet run" placeholder DTO. */
  get hasResult() {
    return (
      !this.isLoading &&
      !this.hasError &&
      !!this.detail &&
      !!this.detail.computedAt
    );
  }

  get isInProgress() {
    return !!this.detail && IN_PROGRESS_STATUSES.has(this.detail.runStatus);
  }

  get isFailedRun() {
    return (
      !this.isLoading &&
      !this.hasError &&
      !!this.detail &&
      FAILED_STATUSES.has(this.detail.runStatus)
    );
  }

  get showInProgressBanner() {
    return !this.isLoading && !this.hasError && this.isInProgress;
  }

  get showNotYetRunPrompt() {
    return (
      !this.isLoading &&
      !this.hasError &&
      !this.hasResult &&
      !this.isInProgress &&
      !this.isFailedRun
    );
  }

  get computedAtLabel() {
    return this.detail && this.detail.computedAt
      ? `Computed ${new Date(this.detail.computedAt).toLocaleString()}`
      : "";
  }

  get inProgressMessage() {
    return this.detail && this.detail.runStatus === "Processing"
      ? "Sampling scoped objects now — this can take a few minutes."
      : "Scan queued and waiting to start.";
  }

  get recomputeButtonLabel() {
    if (this.isRecomputing) {
      return "Starting scan…";
    }
    if (this.isInProgress) {
      return "Scan in progress…";
    }
    return this.hasResult ? "Recompute" : "Run Data Health Scan";
  }

  get isRecomputeDisabled() {
    return this.isRecomputing || this.isInProgress;
  }

  get hasSelectedFinding() {
    return !!this.selectedFinding;
  }

  get formulaComponents() {
    return this.detail
      ? this.detail.formulaComponents.map((c) => ({
          label: c.label,
          detail: c.value
        }))
      : [];
  }

  get breakdownRows() {
    if (!this.detail) {
      return [];
    }
    return this.detail.breakdownRows.map((row) => ({
      key: row.key,
      primaryLabel: row.primaryLabel,
      metricValues: row.metricValues,
      severityKey: row.severityKey,
      severityLabel: row.severityLabel
    }));
  }

  get heatmapRows() {
    if (!this.detail) {
      return [];
    }
    return this.detail.heatmapRows.map((row) => ({
      rowLabel: row.rowLabel,
      cells: row.cells
    }));
  }

  handleRetry() {
    this.load();
  }

  /** An object can have more than one open finding (e.g. both StaleRecords and Completeness) — the most severe, most recently detected one is what a click should surface first. */
  handleRowSelect(event) {
    const componentKey = event.detail.key;
    const matches = this.findings.filter(
      (finding) => finding.componentKey === componentKey
    );
    if (matches.length === 0) {
      this.selectionNote =
        "No finding is on file for this object yet. Run a scan to compute one if it still breaches a rule.";
      this.selectedFinding = undefined;
      return;
    }
    this.selectionNote = undefined;
    this.selectedFinding = matches.sort(
      (a, b) => new Date(b.lastDetected) - new Date(a.lastDetected)
    )[0];
  }

  handleDrawerClose() {
    this.selectedFinding = undefined;
  }

  handleDrawerRelatedSelect(event) {
    this.selectedFinding = event.detail.finding;
    this.selectionNote = undefined;
  }

  async handleDrawerSaved() {
    this.findings = await getDataHealthFindings();
    if (this.selectedFinding) {
      this.selectedFinding =
        this.findings.find(
          (finding) => finding.id === this.selectedFinding.id
        ) || this.selectedFinding;
    }
  }

  async handleRecompute() {
    if (this.isRecomputeDisabled) {
      return;
    }
    this.isRecomputing = true;
    try {
      await recomputeDataHealth();
      await this.load();
    } catch (error) {
      this.loadError =
        (error && error.body && error.body.message) ||
        "Something went wrong starting the Data Health scan.";
    } finally {
      this.isRecomputing = false;
    }
  }
}
