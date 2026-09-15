/**
 * Purpose: The Remediation Management workspace (ADR-0027 lifecycle extension — "a shared
 *          remediation workspace, explicitly on this package's roadmap") — the one place an
 *          administrator triages every open Org Health finding across all five scored domains
 *          in a single sortable, filterable, exportable queue, instead of visiting each
 *          section's own detail container separately.
 * Responsibilities: Load the cross-section summary and one page of the finding queue
 *                    (OI_OrgHealthController.getRemediationSummary/getRemediationQueue), apply
 *                    filter/sort/page changes by re-querying (never filtering a stale client-side
 *                    list), and host the shared oiHealthFindingDrawer for row-click triage —
 *                    mirroring every section container's own drawer-hosting contract (ADR-0027)
 *                    so the drawer behaves identically here and inside a single section.
 * Dependencies: OI_OrgHealthController.getRemediationSummary/getRemediationQueue/
 *               exportRemediationQueue, oiHealthFindingDrawer (and its exported STATUS_OPTIONS),
 *               oiHealthSeverityBadge, oiStateBanner, oiSkeleton, lightning-dual-listbox,
 *               lightning-record-picker (both native base components — no custom picker built).
 * Limitations: Section and severity filter options are a fixed list matching this package's
 *              current five scored Health domains (the same set oiOrgHealthDashboard's own
 *              IMPLEMENTED_DETAIL_SECTION_KEYS names) — not sourced from org metadata, since
 *              these domains are inherent to the package's code, not something an org
 *              configures. The CSV export re-queries every matching row server-side
 *              (OI_OrgHealthFindingRepository.getFindingsForExport, capped at 2000 rows, the
 *              platform's own OFFSET ceiling) rather than exporting only the current page.
 */
import { LightningElement } from "lwc";
import getRemediationQueue from "@salesforce/apex/OI_OrgHealthController.getRemediationQueue";
import getRemediationSummary from "@salesforce/apex/OI_OrgHealthController.getRemediationSummary";
import exportRemediationQueue from "@salesforce/apex/OI_OrgHealthController.exportRemediationQueue";
import { STATUS_OPTIONS } from "c/oiHealthFindingDrawer";

const SECTION_OPTIONS = [
  { label: "Metadata Health", value: "MetadataHealth" },
  { label: "Automation Health", value: "AutomationHealth" },
  { label: "Code Health", value: "CodeHealth" },
  { label: "Security Health", value: "SecurityHealth" },
  { label: "Data Health", value: "DataHealth" }
];

const SEVERITY_OPTIONS = [
  { label: "Critical", value: "Critical" },
  { label: "Warning", value: "Warning" },
  { label: "Good", value: "Good" }
];

const SORT_COLUMNS = [
  { field: "severity", label: "Severity" },
  { field: "title", label: "Finding" },
  { field: "status", label: "Status" },
  { field: "dueDate", label: "Due date" },
  { field: "lastDetected", label: "Last detected" },
  { field: "score", label: "Score" }
];

const PAGE_SIZE = 25;
const CSV_FILE_NAME = "org-health-remediation-queue.csv";

export default class OiHealthRemediation extends LightningElement {
  isLoading = true;
  loadError;
  summary;
  queryResult;
  selectedFinding;
  isExporting = false;
  exportError;

  sectionKeys = [];
  severityKeys = [];
  statuses = [];
  ownerId;
  searchText = "";
  onlyExpiringRiskAcceptance = false;
  onlyOverdue = false;
  sortField = "severity";
  sortDirection = "ASC";
  pageNumber = 1;

  sectionOptions = SECTION_OPTIONS;
  severityOptions = SEVERITY_OPTIONS;
  statusOptions = STATUS_OPTIONS;

  connectedCallback() {
    this.loadAll();
  }

  async loadAll() {
    this.isLoading = true;
    this.loadError = undefined;
    try {
      const [summary, queryResult] = await Promise.all([
        getRemediationSummary(),
        getRemediationQueue(this.buildFilter())
      ]);
      this.summary = summary;
      this.queryResult = queryResult;
    } catch (error) {
      this.loadError =
        (error && error.body && error.body.message) ||
        "Something went wrong loading the Remediation workspace.";
    } finally {
      this.isLoading = false;
    }
  }

  async loadQueue() {
    this.isLoading = true;
    this.loadError = undefined;
    try {
      this.queryResult = await getRemediationQueue(this.buildFilter());
    } catch (error) {
      this.loadError =
        (error && error.body && error.body.message) ||
        "Something went wrong loading the Remediation queue.";
    } finally {
      this.isLoading = false;
    }
  }

  buildFilter() {
    return {
      sectionKeys: this.sectionKeys.length ? this.sectionKeys : null,
      severityKeys: this.severityKeys.length ? this.severityKeys : null,
      statuses: this.statuses.length ? this.statuses : null,
      ownerId: this.ownerId || null,
      searchText: this.searchText || null,
      onlyExpiringRiskAcceptance: this.onlyExpiringRiskAcceptance,
      onlyOverdue: this.onlyOverdue,
      sortField: this.sortField,
      sortDirection: this.sortDirection,
      pageNumber: this.pageNumber,
      pageSize: PAGE_SIZE
    };
  }

  get hasError() {
    return !!this.loadError;
  }

  get hasData() {
    return !this.isLoading && !this.hasError && !!this.queryResult;
  }

  get hasSelectedFinding() {
    return !!this.selectedFinding;
  }

  get summaryTiles() {
    if (!this.summary) {
      return [];
    }
    return [
      { label: "Open findings", value: String(this.summary.totalOpenFindings) },
      { label: "Overdue", value: String(this.summary.overdueCount) },
      {
        label: "Risk acceptance expiring soon",
        value: String(this.summary.expiringRiskAcceptanceCount)
      }
    ];
  }

  get severityBreakdown() {
    return (this.summary && this.summary.countBySeverity) || [];
  }

  get statusBreakdown() {
    return (this.summary && this.summary.countByStatus) || [];
  }

  get sectionBreakdown() {
    return (this.summary && this.summary.countBySection) || [];
  }

  get rows() {
    if (!this.queryResult) {
      return [];
    }
    return this.queryResult.findings.map((finding) => ({
      ...finding,
      dueDateLabel: finding.dueDate || "—",
      lastDetectedLabel: finding.lastDetected
        ? new Date(finding.lastDetected).toLocaleDateString()
        : "—"
    }));
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get pageSummaryLabel() {
    if (!this.queryResult || this.queryResult.totalCount === 0) {
      return "No findings match this filter.";
    }
    const start =
      (this.queryResult.pageNumber - 1) * this.queryResult.pageSize + 1;
    const end = Math.min(
      this.queryResult.pageNumber * this.queryResult.pageSize,
      this.queryResult.totalCount
    );
    return `Rows ${start}-${end} of ${this.queryResult.totalCount}`;
  }

  get isFirstPage() {
    return !this.queryResult || this.queryResult.pageNumber <= 1;
  }

  get isLastPage() {
    return (
      !this.queryResult ||
      this.queryResult.pageNumber >= this.queryResult.totalPages
    );
  }

  get sortableColumns() {
    return SORT_COLUMNS.map((column) => {
      const isActive = this.sortField === column.field;
      return {
        ...column,
        headerClass: isActive
          ? "oi-remediation-th oi-remediation-th_active"
          : "oi-remediation-th",
        ariaSort: isActive
          ? this.sortDirection === "ASC"
            ? "ascending"
            : "descending"
          : "none",
        indicator: isActive ? (this.sortDirection === "ASC" ? "▲" : "▼") : ""
      };
    });
  }

  get exportButtonLabel() {
    return this.isExporting ? "Exporting…" : "Export CSV";
  }

  handleSectionFilterChange(event) {
    this.sectionKeys = event.detail.value;
    this.applyFilterChange();
  }

  handleSeverityFilterChange(event) {
    this.severityKeys = event.detail.value;
    this.applyFilterChange();
  }

  handleStatusFilterChange(event) {
    this.statuses = event.detail.value;
    this.applyFilterChange();
  }

  handleOwnerFilterChange(event) {
    this.ownerId = event.detail.recordId || null;
    this.applyFilterChange();
  }

  handleSearchChange(event) {
    this.searchText = event.target.value;
    this.applyFilterChange();
  }

  handleExpiringToggle(event) {
    this.onlyExpiringRiskAcceptance = event.target.checked;
    this.applyFilterChange();
  }

  handleOverdueToggle(event) {
    this.onlyOverdue = event.target.checked;
    this.applyFilterChange();
  }

  applyFilterChange() {
    this.pageNumber = 1;
    this.loadQueue();
  }

  handleClearFilters() {
    this.sectionKeys = [];
    this.severityKeys = [];
    this.statuses = [];
    this.ownerId = undefined;
    this.searchText = "";
    this.onlyExpiringRiskAcceptance = false;
    this.onlyOverdue = false;
    this.applyFilterChange();
  }

  handleSortColumnClick(event) {
    const field = event.currentTarget.dataset.field;
    if (this.sortField === field) {
      this.sortDirection = this.sortDirection === "ASC" ? "DESC" : "ASC";
    } else {
      this.sortField = field;
      this.sortDirection = "ASC";
    }
    this.pageNumber = 1;
    this.loadQueue();
  }

  handleRowSelect(event) {
    const findingId = event.currentTarget.dataset.findingId;
    this.selectedFinding = this.queryResult.findings.find(
      (finding) => finding.id === findingId
    );
  }

  handlePrevPage() {
    if (this.isFirstPage) {
      return;
    }
    this.pageNumber -= 1;
    this.loadQueue();
  }

  handleNextPage() {
    if (this.isLastPage) {
      return;
    }
    this.pageNumber += 1;
    this.loadQueue();
  }

  handleRetry() {
    this.loadAll();
  }

  handleDrawerClose() {
    this.selectedFinding = undefined;
  }

  async handleDrawerSaved() {
    await this.loadAll();
    if (this.selectedFinding) {
      this.selectedFinding =
        this.queryResult.findings.find(
          (finding) => finding.id === this.selectedFinding.id
        ) || undefined;
    }
  }

  handleDrawerRelatedSelect(event) {
    this.selectedFinding = event.detail.finding;
  }

  async handleExport() {
    if (this.isExporting) {
      return;
    }
    this.isExporting = true;
    this.exportError = undefined;
    try {
      const findings = await exportRemediationQueue(this.buildFilter());
      this.downloadCsv(findings);
    } catch (error) {
      this.exportError =
        (error && error.body && error.body.message) ||
        "Something went wrong exporting the Remediation queue.";
    } finally {
      this.isExporting = false;
    }
  }

  downloadCsv(findings) {
    const header = [
      "Title",
      "Section",
      "Severity",
      "Status",
      "Owner",
      "Due Date",
      "First Detected",
      "Last Detected",
      "Score"
    ];
    const rows = findings.map((finding) => [
      finding.title,
      finding.sectionKey,
      finding.severityKey,
      finding.status,
      finding.ownerName || "",
      finding.dueDate || "",
      finding.firstDetected || "",
      finding.lastDetected || "",
      finding.score != null ? String(finding.score) : ""
    ]);
    const csvContent = [header, ...rows]
      .map((row) => row.map(escapeCsvValue).join(","))
      .join("\r\n");
    const blob = new Blob([csvContent], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = CSV_FILE_NAME;
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
    URL.revokeObjectURL(url);
  }
}

/** Excel/Sheets treats a leading =, +, -, or @ as a formula — a title or owner name starting with one would otherwise execute as a formula for whoever opens the export (OWASP CSV Injection). Prefixing a single quote neutralizes it while leaving the visible text unchanged in every spreadsheet application. */
const CSV_FORMULA_TRIGGER_CHARS = ["=", "+", "-", "@"];

function escapeCsvValue(value) {
  let stringValue = value == null ? "" : String(value);
  if (stringValue && CSV_FORMULA_TRIGGER_CHARS.includes(stringValue[0])) {
    stringValue = `'${stringValue}`;
  }
  if (/[",\r\n]/.test(stringValue)) {
    return `"${stringValue.replace(/"/g, '""')}"`;
  }
  return stringValue;
}
