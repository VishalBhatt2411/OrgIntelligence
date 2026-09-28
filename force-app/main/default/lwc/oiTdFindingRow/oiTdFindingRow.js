import { LightningElement, api } from "lwc";
import updateFindingStatus from "@salesforce/apex/OI_TD_Controller.updateFindingStatus";
import assignFinding from "@salesforce/apex/OI_TD_Controller.assignFinding";
import explainFinding from "@salesforce/apex/OI_TD_Controller.explainFinding";
import {
  SEVERITY_HEX,
  STATUS_LABEL,
  STATUS_OPTIONS,
  severityChipClass
} from "c/oiTdUtils";

/**
 * One finding card (reference: FindingRow / StatusSelect / AssigneeField in pages/FindingsPage.tsx).
 * Mutations bubble a "findingchange" event with the updated FindingDTO and a "toast" event.
 */
export default class OiTdFindingRow extends LightningElement {
  @api scanId;
  @api canManage = false;
  _finding;
  assignee = "";
  expanded = false;
  statusSaving = false;
  explaining = false;

  @api
  get finding() {
    return this._finding;
  }
  set finding(v) {
    const prevAssignee = this._finding ? this._finding.assignedTo : undefined;
    this._finding = v;
    if (!v || v.assignedTo !== prevAssignee || this.assignee === undefined) {
      this.assignee = (v && v.assignedTo) || "";
    }
  }

  get paperStyle() {
    const f = this._finding || {};
    const color = SEVERITY_HEX[f.severity] || "var(--td-divider)";
    const opacity =
      f.status === "resolved" || f.status === "wont_fix" ? 0.6 : 1;
    return `border-left: 4px solid ${color}; opacity: ${opacity};`;
  }

  get chipClass() {
    return severityChipClass(this._finding && this._finding.severity);
  }

  get statusOptions() {
    const current = this._finding && this._finding.status;
    return STATUS_OPTIONS.map((o) => ({ ...o, selected: o.value === current }));
  }

  get statusDisabled() {
    return this.statusSaving || !this.canManage;
  }

  get assigneeDisabled() {
    return !this.canManage;
  }

  get toggleLabel() {
    return this.expanded ? "Hide" : "Details";
  }

  get hasRecommendation() {
    const f = this._finding || {};
    return Boolean(f.aiExplanation || f.aiRecommendation);
  }

  get explainDisabled() {
    return this.explaining || !this.canManage;
  }

  stop(event) {
    event.stopPropagation();
  }

  toggle() {
    this.expanded = !this.expanded;
  }

  toast(message, variant = "success") {
    this.dispatchEvent(
      new CustomEvent("toast", {
        detail: { message, variant },
        bubbles: true,
        composed: true
      })
    );
  }

  changed(dto) {
    this.dispatchEvent(
      new CustomEvent("findingchange", {
        detail: dto,
        bubbles: true,
        composed: true
      })
    );
  }

  handleStatusChange(event) {
    const status = event.target.value;
    this.statusSaving = true;
    updateFindingStatus({ findingId: this._finding.id, status })
      .then((dto) => {
        this.changed(dto);
        this.toast(`Marked as ${STATUS_LABEL[status]}`);
      })
      .catch(() => {
        event.target.value = this._finding.status;
        this.toast("Couldn't update status", "error");
      })
      .finally(() => {
        this.statusSaving = false;
      });
  }

  handleAssigneeInput(event) {
    this.assignee = event.target.value;
  }

  handleAssigneeBlur() {
    const value = this.assignee;
    if (value === ((this._finding && this._finding.assignedTo) || "")) return;
    assignFinding({ findingId: this._finding.id, assignedTo: value })
      .then((dto) => {
        this.changed(dto);
        this.toast("Assignee updated");
      })
      .catch(() => this.toast("Couldn't update assignee", "error"));
  }

  handleExplain() {
    this.explaining = true;
    explainFinding({ findingId: this._finding.id })
      .then((dto) => this.changed(dto))
      .catch(() => this.toast("AI explanation failed", "error"))
      .finally(() => {
        this.explaining = false;
      });
  }
}
