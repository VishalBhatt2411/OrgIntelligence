/**
 * Purpose: Org Health's section tab strip (OrgHealthVisualDesignSpecification.md) — a custom
 *          role="tablist" control, matching oiGraphExplorer's existing mode-switch pattern
 *          rather than lightning-tabset (ADR-0026 plan §1).
 * Responsibilities: Render one tab per caller-supplied section and emit `select` with the
 *                    chosen sectionKey. Never fetches or owns section data itself.
 */
import { LightningElement, api } from "lwc";

/*
 * Normalized onto the ADR-0028 --oi-color-severity-* family. The SLDS severity families this map
 * previously used do not carry traffic-light semantics in this org (measured, ADR-0028 Context):
 * success-1 is a dark teal #056764, warning-1 a brown #8c4b02, error-1 a magenta #b60554 — so the
 * tab dots rendered teal/brown/magenta rather than the green/amber/red their literal fallbacks
 * intended, and the teal collided with the graph canvas's master-detail color.
 *
 * The unscored fallback was --slds-g-color-on-surface-3 with a muted-grey #8892a0 fallback, but
 * that token is SLDS 2's STRONGEST text tier (#03234d): unscored sections rendered the darkest,
 * most prominent dot on the strip. It now resolves through --oi-color-severity-none.
 *
 * Resolution works because oiHealthSectionNav.css imports c/oiDesignTokens and declares these on
 * its own :host, and the dot lives in this component's shadow root.
 */
const SEVERITY_DOT_VAR = {
  Good: "var(--oi-color-severity-good)",
  Warning: "var(--oi-color-severity-warning)",
  Critical: "var(--oi-color-severity-critical)"
};

export default class OiHealthSectionNav extends LightningElement {
  /** Array of { sectionKey, displayLabel, severityKey }. severityKey is null for unscored/not-yet-implemented sections, which renders a neutral dot. */
  @api sections = [];
  @api activeSectionKey;

  get renderedSections() {
    return (this.sections || []).map((section) => {
      const isActive = section.sectionKey === this.activeSectionKey;
      return {
        ...section,
        isActive,
        tabClass: isActive
          ? "oi-health-nav-tab oi-health-nav-tab_active"
          : "oi-health-nav-tab",
        dotStyle: `background: ${SEVERITY_DOT_VAR[section.severityKey] || "var(--oi-color-severity-none)"};`
      };
    });
  }

  handleSelect(event) {
    const sectionKey = event.currentTarget.dataset.sectionKey;
    this.dispatchEvent(new CustomEvent("select", { detail: { sectionKey } }));
  }
}
