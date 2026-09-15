/**
 * Purpose: Org Health's score ring (OrgHealthVisualDesignSpecification.md) — the one visual
 *          every scored section shares, presentational only.
 * Responsibilities: Draw an SVG progress ring for a 0-100 score, colored by severityKey. When
 *                    score is null (not yet scanned / not scored), render the dashed
 *                    "not available" track instead of guessing a value.
 * Dependencies: none — severityKey is resolved by the caller (OI_HealthSeverityService),
 *               never re-derived here, so the ring and any severity badge next to it can
 *               never disagree.
 */
import { LightningElement, api } from "lwc";

const RADIUS = 16;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

/* Severity resolves through the ADR-0028 severity tokens, never the SLDS success/warning/error
 * families: measured in this org they are teal (#056764), brown (#8c4b02) and magenta (#b60554),
 * so the ring lost its traffic-light semantic. The token values carry the intended
 * green/amber/red and follow a future dark theme via light-dark(). */
const SEVERITY_COLOR_VAR = {
  Good: "var(--oi-color-severity-good)",
  Warning: "var(--oi-color-severity-warning)",
  Critical: "var(--oi-color-severity-critical)"
};

export default class OiHealthScoreRing extends LightningElement {
  @api score;
  @api severityKey;
  @api size = "default";

  get hasScore() {
    return this.score !== null && this.score !== undefined;
  }

  get wrapClass() {
    return this.size === "lg"
      ? "oi-health-ring-wrap oi-health-ring-wrap_lg"
      : "oi-health-ring-wrap";
  }

  get displayValue() {
    return this.hasScore ? Math.round(this.score) : "—";
  }

  get ringColor() {
    return (
      SEVERITY_COLOR_VAR[this.severityKey] || "var(--oi-color-severity-none)"
    );
  }

  get valueCircleStyle() {
    return `stroke: ${this.ringColor};`;
  }

  get dashArray() {
    return this.hasScore ? String(CIRCUMFERENCE.toFixed(1)) : "3 4";
  }

  get dashOffset() {
    if (!this.hasScore) {
      return "0";
    }
    const clamped = Math.max(0, Math.min(100, this.score));
    return (CIRCUMFERENCE * (1 - clamped / 100)).toFixed(1);
  }

  get valueCircleClass() {
    return this.hasScore
      ? "oi-health-ring-value"
      : "oi-health-ring-value oi-health-ring-value_empty";
  }

  get numClass() {
    return this.hasScore
      ? "oi-health-ring-num num"
      : "oi-health-ring-num oi-health-ring-num_empty";
  }

  get ariaLabel() {
    return this.hasScore
      ? `Score ${Math.round(this.score)} of 100`
      : "Score not available";
  }
}
