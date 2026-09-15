/**
 * Purpose: Org Health's "How this score is calculated" disclosure (ProductSpecs.md's "any
 *          score must expose its formula" rule, ADR-0026) — a collapsible, always-available
 *          formula explainer for every scored section detail view.
 * Responsibilities: Render a summary line plus a list of weighted formula components. Purely
 *                    presentational — the formula text/weights come from
 *                    OI_Org_Health_Metric_Config__mdt via the caller, never hardcoded here.
 */
import { LightningElement, api } from "lwc";

export default class OiHealthFormulaDisclosure extends LightningElement {
  @api summary;
  /** Array of { label, detail } — e.g. { label: 'High field count — objects with ≥ 60 fields', detail: '(weight 35%)' }. */
  @api components = [];
  @api isOpenByDefault = false;
}
