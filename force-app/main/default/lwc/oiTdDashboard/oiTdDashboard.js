import { LightningElement, api } from "lwc";
import getHealth from "@salesforce/apex/OI_TD_Controller.getHealth";
import getHealthHistory from "@salesforce/apex/OI_TD_Controller.getHealthHistory";
import getDiff from "@salesforce/apex/OI_TD_Controller.getDiff";
import getReportData from "@salesforce/apex/OI_TD_Controller.getReportData";
import {
  RISK_PILL,
  SCORE_STATUS,
  SEVERITY_HEX,
  SEVERITY_ORDER,
  XLSX_MIME,
  buildReportXlsx,
  downloadBase64,
  errorMessage,
  fmtDate,
  scoreColor,
  severityChipClass,
  statusOf,
  titleCase
} from "c/oiTdUtils";

const GAUGE_ARC_LENGTH = Math.PI * 80;
const RADIAN = Math.PI / 180;

// Donut geometry (reference: recharts Pie innerRadius 60, outerRadius 90, paddingAngle 2, label at +18).
const INNER_R = 60;
const OUTER_R = 90;
const PAD_ANGLE = 2;

// Trend chart geometry (reference: height 180, margin {top 8, right 16, left 0, bottom 0}, YAxis width 32).
const TREND_H = 180;
const T_TOP = 8;
const T_RIGHT = 16;
const T_LEFT = 32;
const T_XAXIS_H = 30;

function polar(r, angleDeg) {
  return {
    x: r * Math.cos(-angleDeg * RADIAN),
    y: r * Math.sin(-angleDeg * RADIAN)
  };
}

function sectorPath(start, end) {
  const large = Math.abs(end - start) > 180 ? 1 : 0;
  if (Math.abs(end - start) >= 359.999) {
    // full ring: two half arcs
    const o1 = polar(OUTER_R, 0);
    const o2 = polar(OUTER_R, 180);
    const i1 = polar(INNER_R, 0);
    const i2 = polar(INNER_R, 180);
    return (
      `M ${o1.x} ${o1.y} A ${OUTER_R} ${OUTER_R} 0 1 0 ${o2.x} ${o2.y} A ${OUTER_R} ${OUTER_R} 0 1 0 ${o1.x} ${o1.y} ` +
      `M ${i1.x} ${i1.y} A ${INNER_R} ${INNER_R} 0 1 1 ${i2.x} ${i2.y} A ${INNER_R} ${INNER_R} 0 1 1 ${i1.x} ${i1.y} Z`
    );
  }
  const os = polar(OUTER_R, start);
  const oe = polar(OUTER_R, end);
  const is = polar(INNER_R, end);
  const ie = polar(INNER_R, start);
  // angles grow counter-clockwise on screen => sweep-flag 0 on the outer arc
  return (
    `M ${os.x} ${os.y} A ${OUTER_R} ${OUTER_R} 0 ${large} 0 ${oe.x} ${oe.y} ` +
    `L ${is.x} ${is.y} A ${INNER_R} ${INNER_R} 0 ${large} 1 ${ie.x} ${ie.y} Z`
  );
}

/** d3 curveMonotoneX (the recharts "monotone" line). */
function monotonePath(pts) {
  const n = pts.length;
  if (n === 0) return "";
  if (n === 1) return `M ${pts[0].x} ${pts[0].y}`;
  if (n === 2) return `M ${pts[0].x} ${pts[0].y} L ${pts[1].x} ${pts[1].y}`;
  const sign = (v) => (v < 0 ? -1 : 1);
  const slope3 = (p0, p1, p2) => {
    const h0 = p1.x - p0.x;
    const h1 = p2.x - p1.x;
    const s0 = (p1.y - p0.y) / (h0 || (h1 < 0 && -0));
    const s1 = (p2.y - p1.y) / (h1 || (h0 < 0 && -0));
    const p = (s0 * h1 + s1 * h0) / (h0 + h1);
    return (
      (sign(s0) + sign(s1)) *
        Math.min(Math.abs(s0), Math.abs(s1), 0.5 * Math.abs(p)) || 0
    );
  };
  const slope2 = (p0, p1, t) => {
    const h = p1.x - p0.x;
    return h ? ((3 * (p1.y - p0.y)) / h - t) / 2 : t;
  };
  const tangents = new Array(n);
  for (let i = 1; i < n - 1; i++)
    tangents[i] = slope3(pts[i - 1], pts[i], pts[i + 1]);
  tangents[0] = slope2(pts[0], pts[1], tangents[1]);
  tangents[n - 1] = slope2(pts[n - 2], pts[n - 1], tangents[n - 2]);
  let d = `M ${pts[0].x} ${pts[0].y}`;
  for (let i = 0; i < n - 1; i++) {
    const p0 = pts[i];
    const p1 = pts[i + 1];
    const dx = (p1.x - p0.x) / 3;
    d += ` C ${p0.x + dx} ${p0.y + dx * tangents[i]} ${p1.x - dx} ${p1.y - dx * tangents[i + 1]} ${p1.x} ${p1.y}`;
  }
  return d;
}

/**
 * Dashboard (reference: pages/DashboardPage.tsx) — health gauge, severity donut, since-last-scan diff,
 * health trend, category scores and the Export Report menu. Charts are hand-rolled SVG equivalents of
 * the reference's recharts output.
 */
export default class OiTdDashboard extends LightningElement {
  @api findingsLoading = false;
  _scanId;
  _findings = [];
  health;
  healthLoading = true;
  history = [];
  diff;
  diffExpanded = null;
  exportOpen = false;
  exporting = false;
  trendWidth = 600;
  pieTip;
  trendHover = null;
  _ro;

  @api
  get scanId() {
    return this._scanId;
  }
  set scanId(v) {
    const changed = v !== this._scanId;
    this._scanId = v;
    if (changed && v) this.load();
  }

  @api
  get findings() {
    return this._findings;
  }
  set findings(v) {
    this._findings = Array.isArray(v) ? v : [];
  }

  load() {
    const scanId = this._scanId;
    this.healthLoading = true;
    this.diff = undefined;
    this.diffExpanded = null;
    getHealth({ scanId })
      .then((h) => {
        if (scanId === this._scanId) this.health = h;
      })
      .catch(() => {
        if (scanId === this._scanId) this.health = undefined;
      })
      .finally(() => {
        if (scanId === this._scanId) this.healthLoading = false;
      });
    getHealthHistory()
      .then((h) => {
        this.history = h || [];
      })
      .catch(() => {
        this.history = [];
      });
    getDiff({ scanId })
      .then((d) => {
        if (scanId === this._scanId) this.diff = d;
      })
      .catch(() => {
        this.diff = undefined;
      });
  }

  renderedCallback() {
    const box = this.template.querySelector(".trend-box");
    if (box && !this._ro && typeof ResizeObserver !== "undefined") {
      this._ro = new ResizeObserver((entries) => {
        const w = Math.round(entries[0].contentRect.width);
        if (w > 0 && w !== this.trendWidth) this.trendWidth = w;
      });
      this._ro.observe(box);
    } else if (!box && this._ro) {
      this._ro.disconnect();
      this._ro = undefined;
    }
  }

  disconnectedCallback() {
    if (this._ro) this._ro.disconnect();
    this._ro = undefined;
  }

  // ------------------------------------------------------------------ state

  get isLoading() {
    return this.healthLoading || this.findingsLoading;
  }

  get noHealth() {
    return !this.health || !this.health.categoryScores;
  }

  get overall() {
    return this.health ? this.health.overall : 0;
  }

  get openFindings() {
    return this._findings.filter(
      (f) => f.status !== "resolved" && f.status !== "wont_fix"
    );
  }

  get categoryData() {
    if (!this.health || !this.health.categoryScores) return [];
    const open = this.openFindings;
    return Object.entries(this.health.categoryScores)
      .map(([category, score]) => ({
        category: titleCase(category),
        rawCategory: category,
        score,
        openCount: open.filter((f) => f.category === category).length
      }))
      .sort((a, b) => a.score - b.score);
  }

  // ------------------------------------------------------------------ health card

  get pill() {
    const p = RISK_PILL[statusOf(this.overall)];
    return { label: p.label, style: `background: ${p.bg}; color: ${p.fg};` };
  }

  get gaugeColor() {
    return scoreColor(this.overall);
  }

  get gaugeDash() {
    return `${(this.overall / 100) * GAUGE_ARC_LENGTH} ${GAUGE_ARC_LENGTH}`;
  }

  get outOfText() {
    const h = this.history;
    const prior = h && h.length >= 2 ? h[h.length - 2].overall : null;
    if (prior == null) return "out of 100";
    const delta = this.overall - prior;
    let t;
    if (delta === 0) t = "no change";
    else if (delta > 0) t = `up ${delta} point${delta === 1 ? "" : "s"}`;
    else t = `down ${-delta} point${delta === -1 ? "" : "s"}`;
    return `out of 100 · ${t}`;
  }

  get weakest() {
    const c = this.categoryData;
    return c.length ? `${c[0].category} · ${c[0].score}` : null;
  }

  get strongest() {
    const c = this.categoryData;
    if (c.length < 2) return null;
    const s = c[c.length - 1];
    return `${s.category} · ${s.score}`;
  }

  // ------------------------------------------------------------------ severity donut

  get severityData() {
    const open = this.openFindings;
    return SEVERITY_ORDER.map((severity) => ({
      name: severity,
      value: open.filter((f) => f.severity === severity).length
    })).filter((d) => d.value > 0);
  }

  get hasSeverity() {
    return this.severityData.length > 0;
  }

  get openCount() {
    return this.openFindings.length;
  }

  get severityLegend() {
    return this.severityData.map((d) => ({
      ...d,
      dotStyle: `background: ${SEVERITY_HEX[d.name]};`
    }));
  }

  get slices() {
    const data = this.severityData;
    const total = data.reduce((n, d) => n + d.value, 0);
    if (!total) return [];
    const pad = data.length > 1 ? PAD_ANGLE : 0;
    const available = 360 - pad * data.length;
    let angle = 0;
    return data.map((d) => {
      const sweep = (d.value / total) * available;
      const start = angle;
      const end = angle + sweep;
      angle = end + pad;
      const mid = (start + end) / 2;
      const l1 = polar(OUTER_R, mid);
      const l2 = polar(OUTER_R + 20, mid);
      const lp = polar(OUTER_R + 18, mid);
      return {
        name: d.name,
        value: d.value,
        path: sectorPath(start, end),
        fill: SEVERITY_HEX[d.name],
        line: `M ${l1.x} ${l1.y} L ${l2.x} ${l2.y}`,
        lx: lp.x,
        ly: lp.y,
        anchor: lp.x > 0 ? "start" : "end"
      };
    });
  }

  get showPieTip() {
    return Boolean(this.pieTip);
  }

  get pieTipStyle() {
    return this.pieTip
      ? `left: ${this.pieTip.x + 10}px; top: ${this.pieTip.y + 10}px;`
      : "";
  }

  get pieTipText() {
    return this.pieTip ? `${this.pieTip.name} : ${this.pieTip.value}` : "";
  }

  get pieTipColor() {
    return this.pieTip ? `color: ${SEVERITY_HEX[this.pieTip.name]};` : "";
  }

  handleSliceMove(event) {
    const wrap = this.template.querySelector(".donut-box");
    if (!wrap) return;
    const r = wrap.getBoundingClientRect();
    const name = event.currentTarget.dataset.name;
    const d = this.severityData.find((s) => s.name === name);
    this.pieTip = {
      name,
      value: d ? d.value : 0,
      x: event.clientX - r.left,
      y: event.clientY - r.top
    };
  }

  handleSliceLeave() {
    this.pieTip = undefined;
  }

  handleSeverityNav(event) {
    this.navigate({ severity: event.currentTarget.dataset.name });
  }

  // ------------------------------------------------------------------ diff

  get hasDiff() {
    return Boolean(this.diff && this.diff.previousScanId);
  }

  get newCount() {
    return this.diff ? (this.diff.newFindings || []).length : 0;
  }

  get resolvedCount() {
    return this.diff ? (this.diff.resolvedFindings || []).length : 0;
  }

  get newChipLabel() {
    return `+${this.newCount} new`;
  }

  get resolvedChipLabel() {
    return `−${this.resolvedCount} resolved`;
  }

  get newChipClass() {
    return `chip chip-medium chip-clickable ${this.newCount > 0 ? "chip-error" : "chip-default"}`;
  }

  get resolvedChipClass() {
    return `chip chip-medium chip-clickable ${this.resolvedCount > 0 ? "chip-success" : "chip-default"}`;
  }

  get diffList() {
    if (!this.diff || !this.diffExpanded) return [];
    const list =
      this.diffExpanded === "new"
        ? this.diff.newFindings
        : this.diff.resolvedFindings;
    return (list || []).map((f) => ({
      id: f.id,
      title: f.title,
      severity: f.severity,
      chipClass: `${severityChipClass(f.severity)} shrink0`
    }));
  }

  get showDiffList() {
    return this.diffList.length > 0;
  }

  toggleNew() {
    this.diffExpanded = this.diffExpanded === "new" ? null : "new";
  }

  toggleResolved() {
    this.diffExpanded = this.diffExpanded === "resolved" ? null : "resolved";
  }

  // ------------------------------------------------------------------ trend

  get showTrend() {
    return (this.history || []).length > 1;
  }

  get trendViewBox() {
    return `0 0 ${this.trendWidth} ${TREND_H}`;
  }

  get trendPoints() {
    const h = this.history || [];
    const w = this.trendWidth;
    const x0 = T_LEFT;
    const x1 = w - T_RIGHT;
    const y0 = T_TOP;
    const y1 = TREND_H - T_XAXIS_H;
    const step = h.length > 1 ? (x1 - x0) / (h.length - 1) : 0;
    return h.map((p, i) => ({
      key: `${p.scanId}-${i}`,
      x: x0 + step * i,
      y: y1 - (Math.max(0, Math.min(100, p.overall)) / 100) * (y1 - y0),
      overall: p.overall,
      date: fmtDate(p.startedAt)
    }));
  }

  get trendPath() {
    return monotonePath(this.trendPoints);
  }

  get trendColor() {
    return scoreColor(this.overall);
  }

  get yTicks() {
    const y0 = T_TOP;
    const y1 = TREND_H - T_XAXIS_H;
    return [0, 25, 50, 75, 100].map((v) => {
      const y = y1 - (v / 100) * (y1 - y0);
      return {
        v,
        y,
        x1: T_LEFT,
        x2: this.trendWidth - T_RIGHT,
        tx: T_LEFT - 8
      };
    });
  }

  get xAxis() {
    const y = TREND_H - T_XAXIS_H;
    return { x1: T_LEFT, x2: this.trendWidth - T_RIGHT, y };
  }

  get xTicks() {
    const pts = this.trendPoints;
    const y = TREND_H - T_XAXIS_H;
    // recharts "preserveEnd": drop labels that would collide (≈ 80px per label)
    const minGap = 80;
    const keep = new Array(pts.length).fill(false);
    let lastX = Infinity;
    for (let i = pts.length - 1; i >= 0; i--) {
      if (lastX - pts[i].x >= minGap || i === pts.length - 1) {
        keep[i] = true;
        lastX = pts[i].x;
      }
    }
    return pts
      .map((p, i) => ({
        key: p.key,
        x: p.x,
        y1: y,
        y2: y + 6,
        ty: y + 8,
        label: p.date,
        keep: keep[i]
      }))
      .filter((t) => t.keep);
  }

  get hoverPoint() {
    return this.trendHover != null ? this.trendPoints[this.trendHover] : null;
  }

  get showTrendTip() {
    return Boolean(this.hoverPoint);
  }

  get trendCursor() {
    const p = this.hoverPoint;
    return p ? { x: p.x, y1: T_TOP, y2: TREND_H - T_XAXIS_H } : null;
  }

  get trendTipStyle() {
    const p = this.hoverPoint;
    if (!p) return "";
    const flip = p.x + 140 > this.trendWidth;
    return flip
      ? `right: ${this.trendWidth - p.x + 10}px; top: ${p.y}px;`
      : `left: ${p.x + 10}px; top: ${p.y}px;`;
  }

  get trendTipValue() {
    const p = this.hoverPoint;
    return p ? `${p.overall} / 100` : "";
  }

  get trendTipDate() {
    const p = this.hoverPoint;
    return p ? p.date : "";
  }

  handleTrendMove(event) {
    const svg = event.currentTarget;
    const r = svg.getBoundingClientRect();
    const x = ((event.clientX - r.left) / r.width) * this.trendWidth;
    const pts = this.trendPoints;
    if (!pts.length || x < T_LEFT - 4 || x > this.trendWidth - T_RIGHT + 4) {
      this.trendHover = null;
      return;
    }
    let best = 0;
    for (let i = 1; i < pts.length; i++)
      if (Math.abs(pts[i].x - x) < Math.abs(pts[best].x - x)) best = i;
    this.trendHover = best;
  }

  handleTrendLeave() {
    this.trendHover = null;
  }

  // ------------------------------------------------------------------ category scores

  get categoryLegend() {
    return [
      { key: "good", label: "Healthy (≥75)" },
      { key: "warning", label: "Needs attention (50–74)" },
      { key: "critical", label: "Critical (<50)" }
    ].map((s) => ({ ...s, dotStyle: `background: ${SCORE_STATUS[s.key]};` }));
  }

  get categoryRows() {
    return this.categoryData.map((c, i) => ({
      ...c,
      rowClass: i === 0 ? "cat-row" : "cat-row cat-row-border",
      barStyle: `width: ${Math.max(c.score, 0.6)}%; background: ${scoreColor(c.score)};`
    }));
  }

  handleCategoryNav(event) {
    this.navigate({ category: event.currentTarget.dataset.category });
  }

  navigate(filter) {
    this.dispatchEvent(new CustomEvent("navigatefindings", { detail: filter }));
  }

  // ------------------------------------------------------------------ export

  toggleExport() {
    this.exportOpen = !this.exportOpen;
  }

  closeExport() {
    this.exportOpen = false;
  }

  handlePdf() {
    this.exportOpen = false;
    window.open(
      `/apex/OI_TD_Report?scanId=${encodeURIComponent(this._scanId)}`,
      "_blank"
    );
  }

  handleExcel() {
    this.exportOpen = false;
    this.exporting = true;
    getReportData({ scanId: this._scanId })
      .then((report) => {
        downloadBase64(
          "tech-debt-report.xlsx",
          XLSX_MIME,
          buildReportXlsx(report)
        );
      })
      .catch((e) => {
        this.dispatchEvent(
          new CustomEvent("toast", {
            detail: {
              message: errorMessage(e) || "Export failed",
              variant: "error"
            },
            bubbles: true,
            composed: true
          })
        );
      })
      .finally(() => {
        this.exporting = false;
      });
  }
}
