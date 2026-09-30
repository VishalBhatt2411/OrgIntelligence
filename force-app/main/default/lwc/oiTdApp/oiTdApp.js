import { LightningElement } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import FONTS from "@salesforce/resourceUrl/OI_TD_Fonts";
import getAppContext from "@salesforce/apex/OI_TD_Controller.getAppContext";
import getSchedule from "@salesforce/apex/OI_TD_Controller.getSchedule";
import updateSchedule from "@salesforce/apex/OI_TD_Controller.updateSchedule";
import getScans from "@salesforce/apex/OI_TD_Controller.getScans";
import startScan from "@salesforce/apex/OI_TD_Controller.startScan";
import getFindings from "@salesforce/apex/OI_TD_Controller.getFindings";
import getComponents from "@salesforce/apex/OI_TD_Controller.getComponents";
import {
  abbreviateCount,
  errorMessage,
  fmtDateTime,
  parseComponents,
  severityChipClass,
  totalComponentCount
} from "c/oiTdUtils";

const POLL_MS = 3000;
const TOAST_MS = 4000;
const PAGE_TITLE = {
  dashboard: "Dashboard",
  findings: "Findings",
  components: "Components",
  history: "Scan History"
};
const FREQUENCIES = [
  { value: "off", label: "Off" },
  { value: "daily", label: "Daily" },
  { value: "weekly", label: "Weekly" },
  { value: "monthly", label: "Monthly" }
];

/**
 * Tech Debt shell — the Salesforce port of the reference app's App.tsx: dark sidebar with the
 * Monitor/Workspace nav, sticky top bar with breadcrumb, global search and Run Scan, the scanning
 * screen, the old-scan banner and the four pages. The app lives inside the org it scans, so the
 * reference app's connected-org menu (org info, logout) is not carried over; Scan Schedule is a
 * Workspace nav item instead. Scans run asynchronously (Batch), so the shell polls getScans while
 * the latest scan is running. Only a scan started from this tab blocks it with the scanning screen
 * (like the reference app's pending Run Scan request); a scheduled scan or one started elsewhere
 * shows a progress banner instead.
 */
export default class OiTdApp extends LightningElement {
  ctx = {
    canRunScan: false,
    canManageFindings: false,
    canManageSettings: false
  };
  tab = "dashboard";
  scans = [];
  scansLoading = true;
  viewedScanId = null;
  starting = false;

  findings = [];
  findingsLoading = false;
  findingsScanId = null;
  usage;
  componentsLoading = false;
  componentsScanId = null;

  findingsFilter;
  componentsSearch;

  drawerOpen = false;
  scheduleOpen = false;
  schedule;
  scheduleSaving = false;

  searchQuery = "";
  searchOpen = false;

  toast;
  _toastTimer;
  _pollTimer;
  _watchingScanId = null;
  _startedScanId = null;
  _keyHandler;

  // ------------------------------------------------------------------ lifecycle

  connectedCallback() {
    loadStyle(this, FONTS).catch(() => {});
    getAppContext()
      .then((ctx) => {
        this.ctx = ctx;
      })
      .catch((e) => this.showToast(errorMessage(e), "error"));
    this.refreshScans();
    this._keyHandler = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key && e.key.toLowerCase() === "k") {
        e.preventDefault();
        const input = this.template.querySelector(".gs-input");
        if (input) input.focus();
      }
    };
    window.addEventListener("keydown", this._keyHandler);
  }

  disconnectedCallback() {
    window.removeEventListener("keydown", this._keyHandler);
    clearTimeout(this._pollTimer);
    clearTimeout(this._toastTimer);
  }

  // ------------------------------------------------------------------ scans

  refreshScans() {
    return getScans()
      .then((rows) => {
        this.scans = rows || [];
        this.scansLoading = false;
        this.afterScansLoaded();
      })
      .catch((e) => {
        this.scansLoading = false;
        this.showToast(errorMessage(e), "error");
      });
  }

  afterScansLoaded() {
    const latest = this.scans[0];
    clearTimeout(this._pollTimer);
    if (latest && latest.status === "running") {
      this._watchingScanId = latest.id;
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      this._pollTimer = setTimeout(() => this.refreshScans(), POLL_MS);
    } else if (
      this._watchingScanId &&
      latest &&
      latest.id === this._watchingScanId
    ) {
      this._watchingScanId = null;
      const startedHere = latest.id === this._startedScanId;
      if (latest.status === "completed") {
        // A scan run from this tab jumps to its results; a background one leaves the view alone.
        if (startedHere) this.viewedScanId = null;
        this.showToast("Scan complete", "success");
      } else {
        this.showToast(
          latest.error ? "Scan failed: " + latest.error : "Scan failed",
          "error"
        );
      }
    }
    if (!latest || latest.status !== "running") this._startedScanId = null;
    this.loadScanData();
  }

  get latestScan() {
    return this.scans.length ? this.scans[0] : null;
  }

  get latestCompleted() {
    return this.scans.find((s) => s.status === "completed") || null;
  }

  get activeScanId() {
    if (this.viewedScanId) return this.viewedScanId;
    const lc = this.latestCompleted;
    return lc ? lc.id : null;
  }

  get isScanning() {
    return this.starting || this.latestRunning;
  }

  get latestRunning() {
    return !!this.latestScan && this.latestScan.status === "running";
  }

  loadScanData() {
    const scanId = this.activeScanId;
    if (!scanId) {
      this.findings = [];
      this.usage = undefined;
      this.findingsScanId = null;
      this.componentsScanId = null;
      return;
    }
    if (this.findingsScanId !== scanId) {
      this.findingsScanId = scanId;
      this.findingsLoading = true;
      getFindings({ scanId })
        .then((rows) => {
          if (this.findingsScanId === scanId) this.findings = rows || [];
        })
        .catch((e) => this.showToast(errorMessage(e), "error"))
        .finally(() => {
          if (this.findingsScanId === scanId) this.findingsLoading = false;
        });
    }
    if (this.componentsScanId !== scanId) {
      this.componentsScanId = scanId;
      this.componentsLoading = true;
      getComponents({ scanId })
        .then((json) => {
          if (this.componentsScanId === scanId)
            this.usage = json ? parseComponents(json) : undefined;
        })
        .catch(() => {
          if (this.componentsScanId === scanId) this.usage = undefined;
        })
        .finally(() => {
          if (this.componentsScanId === scanId) this.componentsLoading = false;
        });
    }
  }

  handleRunScan() {
    if (this.runDisabled) return;
    this.starting = true;
    startScan()
      .then((scanId) => {
        this._watchingScanId = scanId;
        this._startedScanId = scanId;
        return this.refreshScans();
      })
      .catch((e) => this.showToast(errorMessage(e) || "Scan failed", "error"))
      .finally(() => {
        this.starting = false;
      });
  }

  get runDisabled() {
    return !this.ctx.canRunScan || this.isScanning;
  }

  get scanningStage() {
    const s = this.latestScan;
    return (s && s.status === "running" && s.currentStage) || "Starting scan…";
  }

  // ------------------------------------------------------------------ view state

  get showScanning() {
    return (
      this.starting ||
      (this.latestRunning && this.latestScan.id === this._startedScanId)
    );
  }
  get showBackgroundScan() {
    return this.latestRunning && !this.showScanning;
  }
  get backgroundScanText() {
    const s = this.latestScan;
    const kind = s.triggeredBy === "scheduled" ? "A scheduled scan" : "A scan";
    const stage = s.currentStage ? " (" + s.currentStage + ")" : "";
    return (
      kind + " is running" + stage + ". Results will refresh when it finishes."
    );
  }
  get showFailedBanner() {
    const s = this.latestScan;
    return (
      !this.showScanning && !this.scansLoading && !!s && s.status === "failed"
    );
  }
  get failedText() {
    const s = this.latestScan;
    let text =
      "The latest scan (" +
      fmtDateTime(s.startedAt) +
      ") failed" +
      (s.error ? ": " + s.error : ".");
    const lc = this.latestCompleted;
    if (lc) text += " Showing results from " + fmtDateTime(lc.startedAt) + ".";
    return text;
  }
  get showFailedHistoryLink() {
    return !this.isHistory;
  }
  handleOpenHistory() {
    this.selectTab("history");
  }
  get showInitialLoading() {
    return !this.showScanning && this.scansLoading;
  }
  get showNoScans() {
    return !this.showScanning && !this.scansLoading && !this.activeScanId;
  }
  get showPages() {
    return !this.showScanning && !this.scansLoading && !!this.activeScanId;
  }
  get showOldBanner() {
    const lc = this.latestCompleted;
    return (
      this.showPages &&
      !!this.viewedScanId &&
      (!lc || lc.id !== this.viewedScanId)
    );
  }
  get viewedScanLabel() {
    const s = this.scans.find((x) => x.id === this.viewedScanId);
    return s ? fmtDateTime(s.startedAt) : "";
  }

  get isDashboard() {
    return this.tab === "dashboard";
  }
  get isFindings() {
    return this.tab === "findings";
  }
  get isComponents() {
    return this.tab === "components";
  }
  get isHistory() {
    return this.tab === "history";
  }
  get pageTitle() {
    return PAGE_TITLE[this.tab];
  }

  get monitorItems() {
    const count = totalComponentCount(this.usage);
    const items = [
      { key: "dashboard", label: "Dashboard", count: null },
      {
        key: "findings",
        label: "Findings",
        count: this.activeScanId ? this.findings.length : null
      },
      {
        key: "components",
        label: "Components",
        count: count != null ? abbreviateCount(count) : null
      }
    ];
    return items.map((i) => this.decorateNav(i));
  }

  get workspaceItems() {
    return [
      this.decorateNav({ key: "history", label: "Scan history", count: null }),
      this.decorateNav({ key: "schedule", label: "Scan schedule", count: null })
    ];
  }

  decorateNav(i) {
    const selected = i.key === this.tab;
    return {
      ...i,
      hasCount: i.count !== null && i.count !== undefined,
      itemClass: selected ? "nav-item nav-item-selected" : "nav-item",
      dotClass: selected ? "nav-dot nav-dot-selected" : "nav-dot"
    };
  }

  handleNav(event) {
    const key = event.currentTarget.dataset.key;
    this.drawerOpen = false;
    if (key === "schedule") {
      this.handleSchedule();
      return;
    }
    this.selectTab(key);
  }

  selectTab(key) {
    if (key !== this.tab) {
      if (key === "findings") this.findingsFilter = {};
      if (key === "components") this.componentsSearch = undefined;
    }
    this.tab = key;
    this.scrollTop();
  }

  scrollTop() {
    const main = this.template.querySelector(".main");
    if (main) main.scrollTop = 0;
  }

  handleNavigateFindings(event) {
    this.findingsFilter = { ...(event.detail || {}) };
    this.tab = "findings";
    this.scrollTop();
  }

  handleViewScan(event) {
    const scanId = event.detail && event.detail.scanId;
    const lc = this.latestCompleted;
    this.viewedScanId = lc && lc.id === scanId ? null : scanId;
    this.tab = "dashboard";
    this.loadScanData();
    this.scrollTop();
  }

  handleBackToLatest() {
    this.viewedScanId = null;
    this.loadScanData();
  }

  handleFindingChange(event) {
    const updated = event.detail;
    if (!updated || !updated.id) return;
    this.findings = this.findings.map((f) => {
      return f.id === updated.id ? { ...f, ...updated } : f;
    });
  }

  handleChildToast(event) {
    const d = event.detail || {};
    this.showToast(d.message, d.variant || "success");
  }

  // ------------------------------------------------------------------ drawer (mobile)

  openDrawer() {
    this.drawerOpen = true;
  }
  closeDrawer() {
    this.drawerOpen = false;
  }
  get sidebarClass() {
    return this.drawerOpen ? "sidebar sidebar-open" : "sidebar";
  }

  // ------------------------------------------------------------------ schedule dialog

  handleSchedule() {
    this.scheduleOpen = true;
    getSchedule()
      .then((s) => {
        this.schedule = s;
      })
      .catch((e) => this.showToast(errorMessage(e), "error"));
  }
  closeSchedule() {
    this.scheduleOpen = false;
  }
  get currentFrequency() {
    return (this.schedule && this.schedule.scheduleFrequency) || "off";
  }
  get frequencyButtons() {
    const current = this.currentFrequency;
    const disabled = !this.ctx.canManageSettings || this.scheduleSaving;
    return FREQUENCIES.map((f) => ({
      ...f,
      disabled,
      // The filled style alone marks the active frequency; aria-pressed gives screen readers the same state.
      pressed: f.value === current ? "true" : "false",
      btnClass:
        f.value === current
          ? "btn btn-small btn-contained"
          : "btn btn-small btn-outlined"
    }));
  }
  get showNextScan() {
    return (
      this.currentFrequency !== "off" &&
      this.schedule &&
      this.schedule.nextScanAt
    );
  }
  get nextScanLabel() {
    return "Next scan: " + fmtDateTime(this.schedule.nextScanAt);
  }
  handleFrequency(event) {
    const frequency = event.currentTarget.dataset.value;
    if (frequency === this.currentFrequency) return;
    this.scheduleSaving = true;
    updateSchedule({ frequency })
      .then((s) => {
        this.schedule = s;
        this.showToast("Schedule updated", "success");
      })
      .catch(() => this.showToast("Couldn't update schedule", "error"))
      .finally(() => {
        this.scheduleSaving = false;
      });
  }

  stop(event) {
    event.stopPropagation();
  }

  // ------------------------------------------------------------------ global search

  handleSearchInput(event) {
    this.searchQuery = event.target.value;
    this.searchOpen = true;
  }
  handleSearchFocus() {
    this.searchOpen = true;
  }
  handleSearchBlur() {
    // Delay so a mousedown on a result registers before the dropdown closes.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      this.searchOpen = false;
    }, 150);
  }
  handleSearchKey(event) {
    if (event.key === "Escape") {
      this.resetSearch();
    }
  }

  get trimmedQuery() {
    return this.searchQuery.trim().toLowerCase();
  }
  get searchFindings() {
    const q = this.trimmedQuery;
    if (!q) return [];
    return this.findings
      .filter(
        (f) =>
          (f.title || "").toLowerCase().includes(q) ||
          (f.componentName || "").toLowerCase().includes(q)
      )
      .slice(0, 5)
      .map((f) => ({ ...f, chipClass: severityChipClass(f.severity) }));
  }
  get searchObjects() {
    const q = this.trimmedQuery;
    if (!q || !this.usage) return [];
    return this.usage.objects
      .filter(
        (o) =>
          o.apiName.toLowerCase().includes(q) ||
          o.label.toLowerCase().includes(q)
      )
      .slice(0, 5);
  }
  get showSearchDropdown() {
    return this.searchOpen && !!this.trimmedQuery;
  }
  get hasSearchFindings() {
    return this.searchFindings.length > 0;
  }
  get hasSearchObjects() {
    return this.searchObjects.length > 0;
  }
  get noSearchResults() {
    return !this.hasSearchFindings && !this.hasSearchObjects;
  }
  get noResultsText() {
    return 'No results for "' + this.searchQuery.trim() + '"';
  }

  pickFinding(event) {
    event.preventDefault();
    const f = this.findings.find(
      (x) => x.id === event.currentTarget.dataset.id
    );
    this.resetSearch();
    if (f) {
      this.findingsFilter = { search: f.title };
      this.tab = "findings";
      this.scrollTop();
    }
  }
  pickObject(event) {
    event.preventDefault();
    const apiName = event.currentTarget.dataset.api;
    this.resetSearch();
    this.componentsSearch = apiName;
    this.tab = "components";
    this.scrollTop();
  }
  resetSearch() {
    this.searchQuery = "";
    this.searchOpen = false;
    const input = this.template.querySelector(".gs-input");
    if (input) {
      input.value = "";
      input.blur();
    }
  }

  // ------------------------------------------------------------------ toast

  showToast(message, variant) {
    if (!message) return;
    clearTimeout(this._toastTimer);
    this.toast = { message, variant: variant || "success" };
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._toastTimer = setTimeout(() => {
      this.toast = undefined;
    }, TOAST_MS);
  }
  closeToast() {
    clearTimeout(this._toastTimer);
    this.toast = undefined;
  }
  get toastClass() {
    return "toast toast-" + (this.toast ? this.toast.variant : "success");
  }
}
