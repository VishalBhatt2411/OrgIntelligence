import { LightningElement, api } from "lwc";
import explainComponent from "@salesforce/apex/OI_TD_Controller.explainComponent";
import getComponentAccess from "@salesforce/apex/OI_TD_Controller.getComponentAccess";
import { describeRefs, deleteRiskFor, RISK_COLOR } from "c/oiTdUtils";

/**
 * One component row with usage chip, Setup link and an expandable impact analysis
 * (reference: ComponentsPage.tsx UsageRow + RefList + AccessList + ExplainWithAi).
 * Field rows pass accessObject/accessField and load profile/permission-set access live on expand.
 */
export default class OiTdUsageRow extends LightningElement {
  @api name;
  @api scanId;
  @api linkType;
  @api linkName;
  @api badgeLabel;
  @api badgeActive = false;
  @api accessObject;
  @api accessField;

  _usedIn = [];
  _references = [];
  open = false;
  access = [];
  accessLoaded = false;
  explanation;
  explaining = false;
  explainError = false;

  @api
  get usedIn() {
    return this._usedIn;
  }
  set usedIn(v) {
    this._usedIn = v || [];
  }

  @api
  get references() {
    return this._references;
  }
  set references(v) {
    this._references = v || [];
  }

  get used() {
    return this._usedIn.length > 0;
  }

  get usedLabel() {
    return `Used (${this._usedIn.length})`;
  }

  get hasBadge() {
    return !!this.badgeLabel;
  }

  get badgeClass() {
    return this.badgeActive ? "chip chip-used" : "chip chip-outlined";
  }

  get risk() {
    return deleteRiskFor(this._usedIn);
  }

  get riskLabel() {
    return this.risk.label;
  }

  get detailStyle() {
    return `border-left-color: ${RISK_COLOR[this.risk.level]};`;
  }

  get safeToDelete() {
    return this._usedIn.length === 0 && this._references.length === 0;
  }

  get usedInText() {
    return describeRefs(this._usedIn);
  }

  get referencesText() {
    return describeRefs(this._references);
  }

  get hasAccess() {
    return this.access.length > 0;
  }

  get accessText() {
    return this.access
      .map((a) => `${a.name} (${a.type} — ${a.level})`)
      .join(", ");
  }

  get explainLabel() {
    return this.explaining ? "Asking AI…" : "Explain with AI";
  }

  handleToggle() {
    this.open = !this.open;
    if (!this.open) {
      // The reference unmounts ExplainWithAi on collapse, discarding its answer.
      this.explanation = undefined;
      this.explainError = false;
      return;
    }
    if (this.accessObject && !this.accessLoaded) {
      this.accessLoaded = true;
      getComponentAccess({
        objectName: this.accessObject,
        fieldName: this.accessField || null
      })
        .then((rows) => {
          this.access = rows || [];
        })
        .catch(() => {
          this.access = [];
          this.accessLoaded = false;
        });
    }
  }

  async handleExplain() {
    this.explaining = true;
    this.explainError = false;
    try {
      this.explanation = await explainComponent({
        scanId: this.scanId,
        type: this.linkType,
        name: this.linkName
      });
    } catch {
      this.explainError = true;
    } finally {
      this.explaining = false;
    }
  }
}
