import { LightningElement, api } from "lwc";
import { SEVERITY_ORDER, STATUS_OPTIONS, sortBySeverity } from "c/oiTdUtils";

const ALL = "all";
const PAGE_SIZE = 20;

/**
 * Findings page (reference: pages/FindingsPage.tsx) — search + category/severity/status filters,
 * severity-sorted list, 20 per page. The shell owns the findings array and applies "findingchange".
 */
export default class OiTdFindings extends LightningElement {
  @api scanId;
  @api canManage = false;
  @api loading = false;
  _findings = [];
  _initialFilter;
  category = ALL;
  severity = ALL;
  status = ALL;
  search = "";
  page = 1;

  @api
  get findings() {
    return this._findings;
  }
  set findings(v) {
    this._findings = Array.isArray(v) ? v : [];
    const pc = this.pageCount;
    if (this.page > pc && pc > 0) this.page = pc;
  }

  @api
  get initialFilter() {
    return this._initialFilter;
  }
  set initialFilter(v) {
    this._initialFilter = v;
    if (v) {
      this.category = v.category || ALL;
      this.severity = v.severity || ALL;
      this.search = v.search || "";
      this.page = 1;
    }
  }

  get total() {
    return this._findings.length;
  }

  get countLabel() {
    return `${this.filtered.length} of ${this.total} issue${this.total === 1 ? "" : "s"}`;
  }

  get categoryOptions() {
    const cats = Array.from(
      new Set(this._findings.map((f) => f.category))
    ).sort();
    return [
      { value: ALL, label: "All categories", selected: this.category === ALL },
      ...cats.map((c) => ({
        value: c,
        label: String(c).replace("_", " "),
        selected: this.category === c
      }))
    ];
  }

  get severityOptions() {
    return [
      { value: ALL, label: "All severities", selected: this.severity === ALL },
      ...SEVERITY_ORDER.map((s) => ({
        value: s,
        label: s,
        selected: this.severity === s
      }))
    ];
  }

  get statusOptions() {
    return [
      { value: ALL, label: "All Status", selected: this.status === ALL },
      ...STATUS_OPTIONS.map((o) => ({
        ...o,
        selected: this.status === o.value
      }))
    ];
  }

  get filtered() {
    const q = this.search.trim().toLowerCase();
    const scoped = this._findings.filter(
      (f) =>
        (this.category === ALL || f.category === this.category) &&
        (this.severity === ALL || f.severity === this.severity) &&
        (this.status === ALL || f.status === this.status) &&
        (!q ||
          (f.title || "").toLowerCase().includes(q) ||
          (f.componentName || "").toLowerCase().includes(q))
    );
    return sortBySeverity(scoped);
  }

  get pageCount() {
    return Math.ceil(this.filtered.length / PAGE_SIZE);
  }

  get paged() {
    return this.filtered.slice(
      (this.page - 1) * PAGE_SIZE,
      this.page * PAGE_SIZE
    );
  }

  get isEmpty() {
    return this.filtered.length === 0;
  }

  get emptyText() {
    return this.total
      ? "No findings match these filters."
      : "No findings for this scan.";
  }

  get showPagination() {
    return this.pageCount > 1;
  }

  get prevDisabled() {
    return this.page <= 1;
  }

  get nextDisabled() {
    return this.page >= this.pageCount;
  }

  /** MUI Pagination layout: first, last, current ±1, with ellipses (boundaryCount 1, siblingCount 1). */
  get pageItems() {
    const count = this.pageCount;
    const page = this.page;
    const items = [];
    const push = (n) =>
      items.push({
        key: `p${n}`,
        page: n,
        isPage: true,
        cls: n === page ? "page-btn page-btn-active" : "page-btn"
      });
    if (count <= 7) {
      for (let i = 1; i <= count; i++) push(i);
      return items;
    }
    const start = Math.max(Math.min(page - 1, count - 4), 3);
    const end = Math.min(Math.max(page + 1, 5), count - 2);
    push(1);
    if (start > 3) items.push({ key: "e1", isPage: false });
    else push(2);
    for (let i = start; i <= end; i++) push(i);
    if (end < count - 2) items.push({ key: "e2", isPage: false });
    else push(count - 1);
    push(count);
    return items;
  }

  handleSearch(event) {
    this.search = event.target.value;
    this.page = 1;
  }

  handleCategory(event) {
    this.category = event.target.value;
    this.page = 1;
  }

  handleSeverity(event) {
    this.severity = event.target.value;
    this.page = 1;
  }

  handleStatus(event) {
    this.status = event.target.value;
    this.page = 1;
  }

  goTo(n) {
    this.page = n;
    const top = this.template.querySelector(".page");
    if (top && top.scrollIntoView) top.scrollIntoView({ block: "start" });
  }

  handlePage(event) {
    this.goTo(Number(event.currentTarget.dataset.page));
  }

  handlePrev() {
    if (this.page > 1) this.goTo(this.page - 1);
  }

  handleNext() {
    if (this.page < this.pageCount) this.goTo(this.page + 1);
  }
}
