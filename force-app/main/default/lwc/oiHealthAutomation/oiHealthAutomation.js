/**
 * Purpose: Org Health's Automation Health detail container (ADR-0026 Phase 3, Tier 2 — live,
 *          bounded). Facts-only (Is_Scored__c = false, §0.3) — no score ring, no formula
 *          disclosure; a "Facts only" badge replaces the score ring, matching the landing
 *          grid's own facts-only card treatment. Also the second section (after Metadata Health)
 *          wired to the unified finding model (ADR-0027) — its breakdown rows open a real
 *          finding drawer instead of being a dead end.
 * Responsibilities: Call OI_OrgHealthController.getAutomationHealthDetail, and shape the DTO
 *                    for the shared KPI-tile/breakdown/heatmap primitives — never computing a
 *                    score or severity itself. Separately loads this section's findings and
 *                    resolves a clicked breakdown row to the finding(s) for that component,
 *                    opening oiHealthFindingDrawer with the result. Owns the "Sync findings"
 *                    write action, mirroring oiHealthMetadata's own container-level ownership.
 * Dependencies: OI_OrgHealthController.getAutomationHealthDetail,
 *               OI_OrgHealthController.getAutomationHealthFindings,
 *               OI_OrgHealthController.syncAutomationHealthFindings, the
 *               OI_Run_Org_Health_Compute custom permission, oiHealthSeverityBadge,
 *               oiHealthKpiTile, oiHealthBreakdownList, oiHealthHeatmapGrid,
 *               oiHealthFindingDrawer, oiStateBanner, oiSkeleton.
 * Limitations: A breakdown row maps to a finding by Component_Key__c, which this component only
 *              knows as the row's own key — a row with no matching finding (e.g. a clean
 *              component, or before the first sync has ever run) shows a short inline note
 *              instead of opening an empty drawer or fabricating one.
 */
import { LightningElement } from "lwc";
import getAutomationHealthDetail from "@salesforce/apex/OI_OrgHealthController.getAutomationHealthDetail";
import getAutomationHealthFindings from "@salesforce/apex/OI_OrgHealthController.getAutomationHealthFindings";
import syncAutomationHealthFindings from "@salesforce/apex/OI_OrgHealthController.syncAutomationHealthFindings";
import hasRunOrgHealthCompute from "@salesforce/customPermission/OI_Run_Org_Health_Compute";

export default class OiHealthAutomation extends LightningElement {
  isLoading = true;
  loadError;
  detail;
  findings = [];
  isSyncing = false;
  syncError;
  selectedFinding;
  selectionNote;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.isLoading = true;
    this.loadError = undefined;
    try {
      const [detail, findings] = await Promise.all([
        getAutomationHealthDetail(),
        getAutomationHealthFindings()
      ]);
      this.detail = detail;
      this.findings = findings;
    } catch (error) {
      this.loadError =
        (error && error.body && error.body.message) ||
        "Something went wrong loading Automation Health.";
    } finally {
      this.isLoading = false;
    }
  }

  get canRunCompute() {
    return hasRunOrgHealthCompute;
  }

  get syncButtonLabel() {
    return this.isSyncing ? "Syncing findings…" : "Sync findings";
  }

  get hasError() {
    return !!this.loadError;
  }

  get hasDetail() {
    return !this.isLoading && !this.hasError && !!this.detail;
  }

  get hasSelectedFinding() {
    return !!this.selectedFinding;
  }

  get computedAtLabel() {
    return this.detail && this.detail.computedAt
      ? `Computed ${new Date(this.detail.computedAt).toLocaleString()}`
      : "";
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

  /** A component can have more than one open finding (e.g. both HighDependency and DependencyCycle) — the most severe, most recently detected one is what a click should surface first. */
  handleRowSelect(event) {
    const componentKey = event.detail.key;
    const matches = this.findings.filter(
      (finding) => finding.componentKey === componentKey
    );
    if (matches.length === 0) {
      this.selectionNote =
        'No finding is on file for this component yet. Run "Sync findings" to compute one if this component still breaches a rule.';
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
    this.findings = await getAutomationHealthFindings();
    if (this.selectedFinding) {
      this.selectedFinding =
        this.findings.find(
          (finding) => finding.id === this.selectedFinding.id
        ) || this.selectedFinding;
    }
  }

  async handleSync() {
    if (this.isSyncing) {
      return;
    }
    this.isSyncing = true;
    this.syncError = undefined;
    try {
      await syncAutomationHealthFindings();
      await this.load();
    } catch (error) {
      this.syncError =
        (error && error.body && error.body.message) ||
        "Something went wrong syncing Automation Health findings.";
    } finally {
      this.isSyncing = false;
    }
  }
}
