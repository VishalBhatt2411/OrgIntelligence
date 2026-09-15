/**
 * Purpose: Org Health's Metadata Health detail container (ADR-0026 Phase 2, Tier 2 — live,
 *          bounded). The pixel-fidelity-bound exemplar detail view
 *          (OrgHealthVisualDesignSpecification.md §3.3), and the first section wired to the
 *          unified finding model (ADR-0027) — its breakdown rows open a real finding drawer
 *          instead of being a dead end.
 * Responsibilities: Call OI_OrgHealthController.getMetadataHealthDetail, and shape the DTO
 *                    for the shared score-ring/formula-disclosure/breakdown/heatmap
 *                    primitives — never computing a score or severity itself. Separately loads
 *                    this section's findings and resolves a clicked breakdown row to the
 *                    finding(s) for that component, opening oiHealthFindingDrawer with the
 *                    result — or, when no finding has ever been synced for that component,
 *                    oiHealthLiveInsightPanel with the row's own live evidence, so a click is
 *                    never a dead end. A KPI tile click opens oiHealthKpiDrilldownModal with
 *                    that tile's full object list, since the aggregate count on a tile never
 *                    corresponds 1:1 with the breakdown table's own top-8 rows. Owns the
 *                    "Sync findings" write action (compute + persist), mirroring oiHealthData's
 *                    own container-level ownership of its write action.
 * Dependencies: OI_OrgHealthController.getMetadataHealthDetail,
 *               OI_OrgHealthController.getMetadataHealthFindings,
 *               OI_OrgHealthController.syncMetadataHealthFindings, the
 *               OI_Run_Org_Health_Compute custom permission, oiHealthScoreRing, oiHealthKpiTile,
 *               oiHealthFormulaDisclosure, oiHealthBreakdownList, oiHealthHeatmapGrid,
 *               oiHealthFindingDrawer, oiHealthLiveInsightPanel, oiHealthKpiDrilldownModal,
 *               oiHealthGlossary, oiStateBanner, oiSkeleton.
 * Limitations: A breakdown row maps to a finding by Component_Key__c, which this component
 *              only knows as the row's own key.
 */
import { LightningElement } from "lwc";
import getMetadataHealthDetail from "@salesforce/apex/OI_OrgHealthController.getMetadataHealthDetail";
import getMetadataHealthFindings from "@salesforce/apex/OI_OrgHealthController.getMetadataHealthFindings";
import syncMetadataHealthFindings from "@salesforce/apex/OI_OrgHealthController.syncMetadataHealthFindings";
import hasRunOrgHealthCompute from "@salesforce/customPermission/OI_Run_Org_Health_Compute";

const GLOSSARY_TERMS = [
  {
    term: "Degree",
    definition:
      "How many other objects hold an incoming lookup or master-detail relationship pointing at this one."
  },
  {
    term: "Signal heatmap",
    definition:
      "The same objects and signals as the table on the left, laid out as a grid and colored by severity so patterns stand out at a glance."
  },
  {
    term: "High field-count object",
    definition:
      "An object whose custom field count is at or above this org's configured threshold — more fields generally means more surface area to maintain and more risk when changing the object."
  },
  {
    term: "High-degree object",
    definition:
      "An object many other objects reference. Changing it is more likely to have a wide, hard-to-predict impact."
  },
  {
    term: "No incoming references detected",
    definition:
      "Nothing found during this scan points to this object yet. This is a signal to check, not proof the object is unused."
  },
  {
    term: "Coverage",
    definition:
      "How much of the org this score is actually based on — a partial scan should be read with that in mind."
  }
];

export default class OiHealthMetadata extends LightningElement {
  isLoading = true;
  loadError;
  detail;
  findings = [];
  isSyncing = false;
  syncError;
  selectedFinding;
  liveInsightRow;
  selectedMetricKey;
  glossaryTerms = GLOSSARY_TERMS;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.isLoading = true;
    this.loadError = undefined;
    try {
      const [detail, findings] = await Promise.all([
        getMetadataHealthDetail(),
        getMetadataHealthFindings()
      ]);
      this.detail = detail;
      this.findings = findings;
    } catch (error) {
      this.loadError =
        (error && error.body && error.body.message) ||
        "Something went wrong loading Metadata Health.";
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

  get hasLiveInsightRow() {
    return !!this.liveInsightRow;
  }

  get hasDrilldownModal() {
    return !!this.selectedMetricKey;
  }

  get computedAtLabel() {
    return this.detail && this.detail.computedAt
      ? `Computed ${new Date(this.detail.computedAt).toLocaleString()}`
      : "";
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
      severityLabel: row.severityLabel,
      explanation: row.explanation
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

  /** A component can have more than one open finding (e.g. both HighFieldCount and HighDegree) — the most severe, most recently detected one is what a click should surface first. */
  handleRowSelect(event) {
    const { key: componentKey, row } = event.detail;
    this.selectedMetricKey = undefined;
    const matches = this.findings.filter(
      (finding) => finding.componentKey === componentKey
    );
    if (matches.length === 0) {
      this.selectedFinding = undefined;
      this.liveInsightRow =
        row ||
        this.breakdownRows.find((candidate) => candidate.key === componentKey);
      return;
    }
    this.liveInsightRow = undefined;
    this.selectedFinding = matches.sort(
      (a, b) => new Date(b.lastDetected) - new Date(a.lastDetected)
    )[0];
  }

  handleDrawerClose() {
    this.selectedFinding = undefined;
  }

  handleDrawerRelatedSelect(event) {
    this.selectedFinding = event.detail.finding;
    this.liveInsightRow = undefined;
  }

  handleKpiTileSelect(event) {
    this.selectedMetricKey = event.detail.metricKey;
  }

  handleDrilldownClose() {
    this.selectedMetricKey = undefined;
  }

  handleLiveInsightClose() {
    this.liveInsightRow = undefined;
  }

  handleLiveInsightSync() {
    this.handleSync();
  }

  async handleDrawerSaved() {
    this.findings = await getMetadataHealthFindings();
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
      await syncMetadataHealthFindings();
      await this.load();
    } catch (error) {
      this.syncError =
        (error && error.body && error.body.message) ||
        "Something went wrong syncing Metadata Health findings.";
    } finally {
      this.isSyncing = false;
    }
  }
}
