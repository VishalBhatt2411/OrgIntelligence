import { LightningElement, api } from "lwc";
import { fmtDateTime, fmtTime, scoreColor, titleCase } from "c/oiTdUtils";

const STATUS_CHIP = {
  completed: "chip-success",
  running: "chip-warning",
  failed: "chip-error"
};

// Section keys whose titleCase form would misspell an acronym.
const SECTION_LABELS = { lwc: "LWC" };

function sectionLabel(key) {
  return SECTION_LABELS[key] || titleCase(key);
}

function partialInfo(failedSections) {
  const failed = failedSections || [];
  if (failed.length === 0) return { partial: false };
  const errors = [...new Set(failed.map((f) => f.error).filter(Boolean))];
  return {
    partial: true,
    partialText: `Partial scan: couldn't read ${failed
      .map((f) => sectionLabel(f.category))
      .join(", ")}`,
    partialTitle: errors.join(" | ")
  };
}

/**
 * Scan History page (reference: pages/ScanHistoryPage.tsx). Scores come from ScanDTO.overall of
 * completed scans (the reference joins health-history the same way). A completed scan whose
 * ScanDTO.failedSections is non-empty is flagged Partial, naming the skipped sections, because its
 * score was computed without them. Dispatches "viewscan".
 */
export default class OiTdScanHistory extends LightningElement {
  @api scans = [];
  @api activeScanId;
  @api loading = false;

  get isEmpty() {
    return !this.scans || this.scans.length === 0;
  }

  get rows() {
    const list = this.scans || [];
    return list.map((scan, i) => {
      const score =
        scan.status === "completed" && scan.overall != null
          ? scan.overall
          : null;
      let cls = "scan-row";
      if (i === list.length - 1) cls += " scan-row-last";
      if (scan.id === this.activeScanId) cls += " scan-row-active";
      return {
        id: scan.id,
        cls,
        started: fmtDateTime(scan.startedAt),
        finished: scan.finishedAt
          ? `Finished ${fmtTime(scan.finishedAt)}`
          : "In progress",
        hasScore: score != null,
        score,
        scoreStyle: score != null ? `color: ${scoreColor(score)};` : "",
        status: scan.status,
        ...partialInfo(scan.failedSections),
        chipClass: `chip capitalize status-chip ${STATUS_CHIP[scan.status] || "chip-default"}`
      };
    });
  }

  handleView(event) {
    this.dispatchEvent(
      new CustomEvent("viewscan", {
        detail: { scanId: event.currentTarget.dataset.id }
      })
    );
  }
}
