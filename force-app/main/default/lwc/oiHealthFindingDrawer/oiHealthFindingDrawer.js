/**
 * Purpose: The one reusable detail surface for the unified Org Health finding model (ADR-0027) —
 *          opened from a breakdown row or the Remediation Management workspace's queue, it shows
 *          the evidence/explanation/remediation/score behind a finding and lets an authorized
 *          user triage it (status, owner, due date, notes, compensating control, risk-acceptance
 *          expiry, false-positive justification), plus its related findings, audit history, and
 *          a jump to the affected graph component — matching oiIntelligenceDrilldown's role as a
 *          shared, generic overlay owned by no single section.
 * Responsibilities: Render one OI_OrgHealthFindingDTO honestly (never inventing a value the DTO
 *                    did not provide), apply an explicit triage edit via
 *                    OI_OrgHealthController.updateFindingStatus, and load two secondary panels
 *                    on demand (related findings, audit history) that degrade to an honest inline
 *                    message rather than blocking the primary content if either fails.
 * Dependencies: OI_OrgHealthController.updateFindingStatus/getRelatedFindings/
 *               getFindingComponentNavigation/getFindingHistory, the OI_Manage_Finding_Workflow
 *               custom permission, c/oiHealthSeverityBadge, c/oiHealthFormulaDisclosure,
 *               c/metadataNavigation, lightning/navigation, lightning-record-picker (native User
 *               lookup — no custom Apex search endpoint needed).
 * Limitations: Whether the running user may edit is resolved client-side from the custom
 *              permission for instant, flicker-free UI; the save action is re-checked
 *              server-side regardless (this client-side check is a UX convenience, never the
 *              security boundary). Related findings/history are read via cacheable Apex, so a
 *              save's effect on either may briefly lag until the next fetch (loadHistory is
 *              re-run right after a successful save; related findings are not, since a status
 *              edit never changes which findings are related).
 */
import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import updateFindingStatus from "@salesforce/apex/OI_OrgHealthController.updateFindingStatus";
import getRelatedFindings from "@salesforce/apex/OI_OrgHealthController.getRelatedFindings";
import getFindingComponentNavigation from "@salesforce/apex/OI_OrgHealthController.getFindingComponentNavigation";
import getFindingHistory from "@salesforce/apex/OI_OrgHealthController.getFindingHistory";
import hasManageFindingWorkflow from "@salesforce/customPermission/OI_Manage_Finding_Workflow";
import { navigateToTarget } from "c/metadataNavigation";

/** Exported so the Remediation workspace's status filter can offer the identical set without duplicating it. */
export const STATUS_OPTIONS = [
  { label: "Open", value: "Open" },
  { label: "Acknowledged", value: "Acknowledged" },
  { label: "In Progress", value: "In Progress" },
  { label: "Risk Accepted", value: "Risk Accepted" },
  { label: "Resolved", value: "Resolved" },
  { label: "False Positive", value: "False Positive" }
];

export default class OiHealthFindingDrawer extends NavigationMixin(
  LightningElement
) {
  _finding;
  draft = {};
  isSaving = false;
  saveError;
  saveMessage;
  navigationError;
  /**
   * Which of the five canonical states the navigation message is. A finding with no
   * componentKey has nothing to open — permanently, not transiently — so it is
   * `not-obtainable`, and the banner must not offer a Retry that re-runs the same guard
   * and produces the same message. A lookup or navigation failure is a real `error`.
   */
  navigationState = "error";
  relatedFindings = [];
  relatedFindingsError;
  history = [];
  historyError;

  @api
  get finding() {
    return this._finding;
  }

  set finding(value) {
    const isNewRecord =
      !this._finding || !value || this._finding.id !== value.id;
    this._finding = value;
    if (isNewRecord && value) {
      this.resetDraft(value);
      this.loadRelatedFindings();
      this.loadHistory();
    }
  }

  resetDraft(finding) {
    this.draft = {
      status: finding.status,
      notes: finding.notes || "",
      dueDate: finding.dueDate || null,
      ownerId: finding.ownerId || null,
      compensatingControl: finding.compensatingControl || "",
      riskAcceptanceExpiry: finding.riskAcceptanceExpiry || null,
      falsePositiveJustification: finding.falsePositiveJustification || ""
    };
    this.saveError = undefined;
    this.saveMessage = undefined;
    this.navigationError = undefined;
    this.navigationState = "error";
  }

  async loadRelatedFindings() {
    this.relatedFindingsError = undefined;
    try {
      this.relatedFindings = this.finding.componentKey
        ? await getRelatedFindings({
            componentKey: this.finding.componentKey,
            excludeFindingId: this.finding.id
          })
        : [];
    } catch (error) {
      this.relatedFindings = [];
      this.relatedFindingsError =
        (error && error.body && error.body.message) ||
        "Could not load related findings.";
    }
  }

  async loadHistory() {
    this.historyError = undefined;
    try {
      this.history = await getFindingHistory({ findingId: this.finding.id });
    } catch (error) {
      this.history = [];
      this.historyError =
        (error && error.body && error.body.message) ||
        "Could not load this finding’s history.";
    }
  }

  statusOptions = STATUS_OPTIONS;

  get hasFinding() {
    return !!this.finding;
  }

  get canManage() {
    return hasManageFindingWorkflow;
  }

  get isSaveDisabled() {
    return this.isSaving;
  }

  get saveButtonLabel() {
    return this.isSaving ? "Saving…" : "Save";
  }

  get hasEvidence() {
    return !!(
      this.finding &&
      (this.finding.measuredValue || this.finding.expectedValue)
    );
  }

  get firstDetectedLabel() {
    return this.finding && this.finding.firstDetected
      ? new Date(this.finding.firstDetected).toLocaleString()
      : "—";
  }

  get lastDetectedLabel() {
    return this.finding && this.finding.lastDetected
      ? new Date(this.finding.lastDetected).toLocaleString()
      : "—";
  }

  get ownerName() {
    return (this.finding && this.finding.ownerName) || "Unassigned";
  }

  get hasScore() {
    return (
      !!this.finding &&
      this.finding.score !== null &&
      this.finding.score !== undefined
    );
  }

  get scoreLabel() {
    return this.hasScore
      ? `Severity score: ${this.finding.score} / 100 (higher = more severe)`
      : null;
  }

  get scoreContributorRows() {
    if (
      !this.finding ||
      !this.finding.scoreContributors ||
      !this.finding.scoreContributors.length
    ) {
      return [];
    }
    return this.finding.scoreContributors.map((contributor) => ({
      label: contributor.label,
      detail: this.formatContributorDetail(contributor)
    }));
  }

  formatContributorDetail(contributor) {
    const parts = [
      `${contributor.contribution} pts`,
      `magnitude ${contributor.magnitude}`,
      `confidence ${contributor.confidence}`
    ];
    if (contributor.hasCompensatingControl) {
      parts.push("compensating control applied");
    }
    if (contributor.wasCorrelatedOut) {
      parts.push("correlated out");
    }
    return `(${parts.join(", ")})`;
  }

  get hasScoreContributors() {
    return this.scoreContributorRows.length > 0;
  }

  get resolvedDateLabel() {
    return this.finding && this.finding.resolvedDate
      ? new Date(this.finding.resolvedDate).toLocaleString()
      : null;
  }

  get showResolvedDate() {
    return (
      this.finding &&
      this.finding.status === "Resolved" &&
      !!this.resolvedDateLabel
    );
  }

  get showRiskAcceptanceInfo() {
    return (
      this.finding &&
      this.finding.status === "Risk Accepted" &&
      !!this.finding.riskAcceptanceExpiry
    );
  }

  get riskAcceptanceExpiryBadgeClass() {
    return this.finding && this.finding.isRiskAcceptanceExpired
      ? "oi-finding-drawer-risk-expired"
      : "";
  }

  get showFalsePositiveJustification() {
    return (
      this.finding &&
      this.finding.status === "False Positive" &&
      !!this.finding.falsePositiveJustification
    );
  }

  get showRiskAcceptanceExpiryField() {
    return this.draft.status === "Risk Accepted";
  }

  get showFalsePositiveJustificationField() {
    return this.draft.status === "False Positive";
  }

  get hasRelatedFindings() {
    return this.relatedFindings && this.relatedFindings.length > 0;
  }

  get hasHistory() {
    return this.history && this.history.length > 0;
  }

  /**
   * A failed lookup leaves the local list empty, which is not the same finding as a confirmed
   * zero. These guards keep the "true zero" banner off screen while the error banner is showing,
   * so the drawer never claims to know something it does not.
   */
  get showNoRelatedFindings() {
    return !this.hasRelatedFindings && !this.relatedFindingsError;
  }

  get showNoHistory() {
    return !this.hasHistory && !this.historyError;
  }

  get relatedFindingRows() {
    return (this.relatedFindings || []).map((related) => ({
      ...related,
      key: related.id
    }));
  }

  get historyRows() {
    return (this.history || []).map((entry, index) => ({
      ...entry,
      key: index,
      changedDateLabel: entry.changedDate
        ? new Date(entry.changedDate).toLocaleString()
        : "—",
      oldValueLabel: entry.oldValue == null ? "—" : entry.oldValue,
      newValueLabel: entry.newValue == null ? "—" : entry.newValue
    }));
  }

  handleFieldChange(event) {
    const field = event.target.dataset.field;
    this.draft = { ...this.draft, [field]: event.target.value };
  }

  handleOwnerChange(event) {
    this.draft = { ...this.draft, ownerId: event.detail.recordId || null };
  }

  async handleSave() {
    if (this.isSaveDisabled || !this.finding) {
      return;
    }
    this.isSaving = true;
    this.saveError = undefined;
    this.saveMessage = undefined;
    try {
      await updateFindingStatus({
        findingId: this.finding.id,
        status: this.draft.status,
        notes: this.draft.notes,
        dueDate: this.draft.dueDate || null,
        ownerId: this.draft.ownerId || null,
        compensatingControl: this.draft.compensatingControl,
        riskAcceptanceExpiry: this.draft.riskAcceptanceExpiry || null,
        falsePositiveJustification:
          this.draft.falsePositiveJustification || null
      });
      this.saveMessage = "Saved.";
      this.dispatchEvent(
        new CustomEvent("saved", { detail: { findingId: this.finding.id } })
      );
      await this.loadHistory();
    } catch (error) {
      this.saveError =
        (error && error.body && error.body.message) ||
        "Something went wrong saving this finding.";
    } finally {
      this.isSaving = false;
    }
  }

  handleClose() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  /** Retry for the related-findings error banner — scoped to that lookup, per the state contract. */
  handleRetryRelatedFindings() {
    this.loadRelatedFindings();
  }

  /** Retry for the history error banner — scoped to that lookup, per the state contract. */
  handleRetryHistory() {
    this.loadHistory();
  }

  handleRelatedFindingSelect(event) {
    const selectedId = event.currentTarget.dataset.findingId;
    const selected = (this.relatedFindings || []).find(
      (related) => related.id === selectedId
    );
    if (selected) {
      this.dispatchEvent(
        new CustomEvent("relatedselect", { detail: { finding: selected } })
      );
    }
  }

  async handleOpenComponent() {
    this.navigationError = undefined;
    this.navigationState = "error";
    if (!this.finding || !this.finding.componentKey) {
      this.navigationState = "not-obtainable";
      this.navigationError =
        "This finding is not tied to a specific graph component, so there is nothing to open.";
      return;
    }
    try {
      const target = await getFindingComponentNavigation({
        componentKey: this.finding.componentKey
      });
      const result = navigateToTarget(this, target);
      if (!result.navigated) {
        this.navigationError = result.message;
      }
    } catch (error) {
      this.navigationError =
        (error && error.body && error.body.message) ||
        "Something went wrong opening this component.";
    }
  }

  /** A missing component is a stated absence, not a failure, so it gets its own heading. */
  get navigationTitle() {
    return this.navigationState === "not-obtainable"
      ? "No affected component to open"
      : "Couldn't open the affected component";
  }

  /** Escape closes the dialog — expected of any modal, and the minimum for keyboard users who cannot reach the close button by pointer. */
  handleKeyDown(event) {
    if (event.key === "Escape") {
      this.handleClose();
    }
  }
}
