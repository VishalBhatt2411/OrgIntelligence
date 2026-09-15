/**
 * Purpose: A short, plain-English glossary panel for one Org Health detail view — the terms
 *          a section's own charts and columns use (e.g. "degree", "signal heatmap") are
 *          domain jargon to a first-time reader, and this is the one place that spells them
 *          out instead of leaving the reader to infer them from a column header.
 * Responsibilities: Render a caller-supplied list of { term, definition } pairs under a fixed
 *                    heading. Purely presentational — content is owned by the section that
 *                    composes this (each section's own vocabulary differs), never invented or
 *                    computed here.
 * Dependencies: None.
 * Limitations: Definitions are static copy, not sourced from OI_Org_Health_Metric_Config__mdt —
 *              a threshold NUMBER is already shown next to each affected row; this panel exists
 *              to explain what the term itself means, not to repeat that configured number.
 */
import { LightningElement, api } from "lwc";

export default class OiHealthGlossary extends LightningElement {
  @api title = "Terms used on this page";
  /** Array of { term, definition }. */
  @api terms = [];

  get hasTerms() {
    return this.terms && this.terms.length > 0;
  }

  get displayTerms() {
    return this.terms.map((entry) => ({ ...entry, key: entry.term }));
  }
}
