/**
 * Purpose: Org Health's severity pill (OrgHealthVisualDesignSpecification.md) — renders one
 *          of the three CMDT-governed severities, or a neutral "facts only" / "not scanned"
 *          badge for sections that carry no score (ADR-0026 §0.3/§0.5).
 * Responsibilities: Pure presentation of a resolved severityKey + label. Never resolves a
 *                    score to a severity itself — that is OI_HealthSeverityService's job,
 *                    server-side, so every consumer of a severity agrees.
 */
import { LightningElement, api } from "lwc";

const SEVERITY_CLASS = {
  Good: "oi-health-severity-badge oi-health-severity-badge_good",
  Warning: "oi-health-severity-badge oi-health-severity-badge_warning",
  Critical: "oi-health-severity-badge oi-health-severity-badge_critical"
};

export default class OiHealthSeverityBadge extends LightningElement {
  @api severityKey;
  @api label;
  /** When true (no severityKey and no score for this section by design, e.g. Automation/Security Health), renders the dashed "Facts only" pill instead of a colored severity pill. */
  @api factsOnly = false;

  get isRecognizedSeverity() {
    return !!SEVERITY_CLASS[this.severityKey];
  }

  get badgeClass() {
    return (
      SEVERITY_CLASS[this.severityKey] ||
      "oi-health-severity-badge oi-health-severity-badge_neutral"
    );
  }

  get displayLabel() {
    return this.label || this.severityKey || "Unknown";
  }
}
