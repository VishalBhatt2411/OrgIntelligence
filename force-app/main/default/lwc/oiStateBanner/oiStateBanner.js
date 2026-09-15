/**
 * Purpose: The platform's single loading/empty/error vocabulary, for every surface — Graph
 *          Explorer, Hierarchy Manager and Org Health alike. Renders exactly the five states
 *          `OrgHealthVisualDesignSpecification.md` §6 defines: true zero / coverage incomplete /
 *          not yet run / not obtainable / request failed.
 * Responsibilities: Map a `state` key to its glyph, colour variant and accessibility role;
 *                   render the caller's own title/message inside that shell; offer Retry only
 *                   where retrying is meaningful.
 * Dependencies: c/oiDesignTokens (via the stylesheet).
 * Limitations: Deliberately carries no copy of its own beyond the Retry label — the caller owns
 *              the wording, because only the caller knows what was being loaded.
 *
 * This generalizes the former `oiHealthStateBanner`, which was Org Health-only while the graph and
 * hierarchy surfaces hand-rolled the same job five different ways — 14 distinct CSS class names
 * for "error", 7 for "empty" and 5 loading wrappers, per ADR-0028 §7. The name is surface-neutral
 * because the component is.
 *
 * Two rules this component exists to make structural rather than conventional:
 *
 *   1. **A loading state is not one of these five.** Loading is transient and unknown; these five
 *      are settled findings about real data. Rendering a banner while loading presents a pending
 *      request as a conclusion, which is what the Org Health sections previously did. Use
 *      `c/oiSkeleton` for loading and this component only once the answer is known.
 *   2. **"Not obtainable" is never styled as a retryable error.** It is a structural fact — a
 *      metric this org's API version does not expose — so it gets no Retry affordance no matter
 *      how the caller configures it.
 */
import { LightningElement, api } from "lwc";

/**
 * `retryable` is a property of the STATE, not of the caller. Only a failed request can be usefully
 * retried: re-requesting a true zero, an unscanned region, a queued run, or a metric the platform
 * does not expose would either change nothing or need a different action entirely (a scan, an
 * upgrade), which the caller surfaces in its own message.
 */
const STATE_META = {
  "true-zero": { icon: "✓", variant: "success", retryable: false },
  "coverage-incomplete": { icon: "◐", variant: "warning", retryable: false },
  "not-yet-run": { icon: "◷", variant: "neutral", retryable: false },
  "not-obtainable": { icon: "＿", variant: "neutral", retryable: false },
  error: { icon: "!", variant: "critical", retryable: true }
};
const DEFAULT_STATE = "not-yet-run";

export default class OiStateBanner extends LightningElement {
  @api state = DEFAULT_STATE;
  @api title;
  @api message;
  /** error state only — lets a user quote this run when reporting a problem, per the state contract's "sanitized message + correlation id" requirement. */
  @api correlationId;

  get meta() {
    return STATE_META[this.state] || STATE_META[DEFAULT_STATE];
  }

  get icon() {
    return this.meta.icon;
  }

  get iconClass() {
    return `oi-state-banner-icon oi-state-banner_${this.meta.variant}`;
  }

  get isRetryable() {
    return this.meta.retryable;
  }

  get hasCorrelationId() {
    return this.isRetryable && !!this.correlationId;
  }

  /**
   * A failure interrupts what the user asked for and must be announced; the other four states
   * are ambient descriptions of data that is already on screen, so they are polite. The
   * hand-rolled patterns this component replaces used role="alert" for errors, and losing that
   * on consolidation would be a silent accessibility regression.
   */
  get ariaRole() {
    return this.isRetryable ? "alert" : "status";
  }

  handleRetry() {
    this.dispatchEvent(new CustomEvent("retry"));
  }
}
