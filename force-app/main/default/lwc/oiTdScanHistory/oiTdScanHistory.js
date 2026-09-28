import { LightningElement, api } from "lwc";
import { fmtDateTime, fmtTime, scoreColor } from "c/oiTdUtils";

const STATUS_CHIP = {
  completed: "chip-success",
  running: "chip-warning",
  failed: "chip-error"
};

/**
 * Scan History page (reference: pages/ScanHistoryPage.tsx). Scores come from ScanDTO.overall of
 * completed scans (the reference joins health-history the same way). Dispatches "viewscan".
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
