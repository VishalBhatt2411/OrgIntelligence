/**
 * Purpose: The loading placeholder `OrgHealthVisualDesignSpecification.md` §3.4 lists among the
 *          required shared primitives and which no component had ever implemented.
 * Responsibilities: Render N neutral placeholder bars, or a card-shaped block, sized to roughly
 *                   the content they stand in for, and announce "loading" to assistive tech once.
 * Dependencies: c/oiDesignTokens (via the stylesheet).
 * Limitations: A shape, not a progress indicator — it cannot express how far along a request is.
 *              For an operation with a known duration or a cancel affordance, use a spinner or a
 *              real progress control instead.
 *
 * Why this exists rather than a spinner or a banner:
 *   - Before this, the Org Health sections rendered a five-state *banner* while loading, with
 *     `state="not-yet-run"` and a "Loading …" title. That presents a pending request as a settled
 *     finding, and "not yet run" is a real, different condition (a scan that has never executed) —
 *     collapsing the two is exactly what ADR-0028 §7 and the state contract forbid.
 *   - The graph and hierarchy surfaces instead used bare `lightning-spinner`s at three different
 *     sizes with five different wrappers. A spinner in a content region also causes layout to jump
 *     when real content replaces it; a skeleton reserves the space.
 */
import { LightningElement, api } from "lwc";

const DEFAULT_LINES = 3;
const MAX_LINES = 12;

/**
 * Widths taper so a block of bars reads as prose rather than a table, and the pattern is fixed
 * rather than random: a skeleton that reshuffles on every re-render draws the eye to the loading
 * state instead of away from it.
 */
const LINE_WIDTHS = ["92%", "78%", "85%", "64%", "88%", "72%"];

export default class OiSkeleton extends LightningElement {
  /** How many placeholder bars to draw. Match it to the content being awaited. */
  @api lines = DEFAULT_LINES;
  /** Draws the bars inside a card surface, for a region that will resolve into a card. */
  @api card = false;
  /** Announced once while loading. Say what is loading, not merely that something is. */
  @api label = "Loading";

  get lineItems() {
    const requested = Number(this.lines);
    const count = Number.isFinite(requested)
      ? Math.min(Math.max(Math.trunc(requested), 1), MAX_LINES)
      : DEFAULT_LINES;
    return Array.from({ length: count }, (_, index) => ({
      key: `skeleton-line-${index}`,
      style: `width: ${LINE_WIDTHS[index % LINE_WIDTHS.length]};`
    }));
  }

  get containerClass() {
    return this.card ? "oi-skeleton oi-skeleton_card" : "oi-skeleton";
  }
}
