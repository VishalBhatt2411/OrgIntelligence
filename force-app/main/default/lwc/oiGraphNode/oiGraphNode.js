/**
 * Purpose: One instance per currently-rendered node (GraphUI.md §5) — presentational only,
 *          never calls Apex, never touches the Presentation Type Registry itself (the
 *          container resolves icon/color before passing them down as already-resolved
 *          props, per §5's own stated rationale).
 * Responsibilities: Render one node; emit select/expandtoggle. Real DOM per node gives
 *                    native focus/tab-order/ARIA for free (§28). Resolves the registry's
 *                    semantic colorToken (e.g. "brand", "success" — an SLDS-style category
 *                    name, not a literal CSS color) to an actual color for its accent
 *                    stripe, since a raw token name is not valid CSS on its own.
 */
import { LightningElement, api } from "lwc";

/**
 * SLDS-style semantic categories the Presentation Type Registry's Color_Token__c is documented
 * to use (DataModel.md §4.1) — an unrecognized token (a future registry value this component
 * has never seen) falls back to neutral gray, never a broken style.
 *
 * Each value now resolves an ADR-0028 platform token rather than an SLDS hook chosen per entry.
 * That fixes two things the previous map got wrong:
 *   - `success`/`warning`/`error` bound to --slds-g-color-success-1 / -warning-1 / -error-1, which
 *     ADR-0028's live audit measured as a dark teal (#056764), a brown (#8c4b02) and a magenta
 *     (#b60554) in this org — not the green/amber/red their literal fallbacks intended, and the
 *     teal collides with the master-detail relationship colour on the same canvas. The severity
 *     family carries those intents correctly.
 *   - `neutral` bound to --slds-g-color-border-2, SLDS 2's STRONG border (#5c5c5c), while asking
 *     for the muted #706e6b. --oi-color-text-muted is that tier.
 * The identical map in oiSchemaObjectCard.js is updated to exactly these values. Extracting a
 * shared JS module is deliberately out of scope here; consistency is the goal.
 *
 * Nesting a token inside another custom property (`--oi-node-accent`, consumed by
 * oiGraphNode.css) is ordinary, fully supported CSS custom-property resolution — the --oi-*
 * tokens are declared on this component's own :host by the imported token module, so they are in
 * scope for the inline style this getter produces.
 */
const COLOR_TOKEN_HEX = {
  brand: "var(--oi-color-accent)",
  success: "var(--oi-color-severity-good)",
  warning: "var(--oi-color-severity-warning)",
  error: "var(--oi-color-severity-critical)",
  neutral: "var(--oi-color-text-muted)"
};
const DEFAULT_COLOR_HEX = COLOR_TOKEN_HEX.neutral;

export default class OiGraphNode extends LightningElement {
  @api nodeKey;
  @api typeKey;
  @api label;
  @api secondaryKey;
  @api state;
  @api iconName = "standard:custom";
  @api colorToken = "neutral";
  @api isSelected = false;
  @api isExpanded = false;
  @api hasMoreNeighbors = false;
  @api isCluster = false;
  /** Human type name from the registry ("Apex Trigger"), never the raw typeKey. */
  @api typeLabel;
  /**
   * Why this node is on screen, in the user's language: the role it plays relative to whatever
   * it hangs off ("Field Of", "Executes On"), plus what it relates to. Supplied by the Canvas,
   * which owns the graph topology — a node cannot know its own context.
   */
  @api relationshipRole;
  @api relationshipContext;
  /** Hops from the centre. 1 means a direct neighbour; anything higher needs its distance stated, or a far node reads as if it were directly related. */
  @api hopDistance;
  /** True when this node is on the currently-highlighted path back to the centre. */
  @api isOnActivePath = false;
  /** True when something else is highlighted and this node is not part of it — rendered de-emphasised rather than hidden. */
  @api isDimmed = false;

  get nodeClass() {
    return (
      "oi-graph-node" +
      (this.isSelected ? " is-selected" : "") +
      (this.isCluster ? " is-cluster" : "") +
      (this.isOnActivePath ? " is-on-path" : "") +
      (this.isDimmed ? " is-dimmed" : "")
    );
  }

  /** The relationship chip's text — the single most important thing on the card for answering "why is this here?". Omitted entirely rather than shown empty when the Canvas has no context to give (e.g. the centre node itself). */
  get relationshipChipText() {
    if (!this.relationshipRole) {
      return null;
    }
    return this.relationshipContext
      ? `${this.relationshipRole} ${this.relationshipContext}`
      : this.relationshipRole;
  }

  get hasRelationshipChip() {
    return !!this.relationshipChipText;
  }

  /** Distance is stated only beyond one hop: labelling a direct neighbour "1 relationship away" is noise, while leaving a 3-hop node unlabelled actively misleads. */
  get hopLabel() {
    return this.hopDistance > 1
      ? `${this.hopDistance} relationships away`
      : null;
  }

  get hasHopLabel() {
    return !!this.hopLabel;
  }

  get resolvedTypeLabel() {
    return this.typeLabel || "";
  }

  get resolvedColor() {
    return COLOR_TOKEN_HEX[this.colorToken] || DEFAULT_COLOR_HEX;
  }

  get nodeStyle() {
    return `--oi-node-accent: ${this.resolvedColor};`;
  }

  /**
   * Screen-reader text is user-facing text, so it must never contain a raw typeKey — this
   * previously announced "SalesforceMetadata.CustomObject", which is exactly the internal
   * vocabulary the product is not allowed to expose. It now uses the registry's human label and
   * includes the relationship context, so a non-sighted user gets the same "why is this here"
   * answer the chip gives everyone else.
   */
  get ariaLabel() {
    const expandState = this.isExpanded ? "expanded" : "collapsed";
    const more = this.hasMoreNeighbors ? ", more relationships available" : "";
    const secondary = this.secondaryKey ? `, ${this.secondaryKey}` : "";
    const type = this.typeLabel ? `, ${this.typeLabel}` : "";
    const relationship = this.relationshipChipText
      ? `, ${this.relationshipChipText}`
      : "";
    const hops = this.hopLabel ? `, ${this.hopLabel}` : "";
    return `${this.label}${secondary}${type}${relationship}${hops}, ${expandState}${more}`;
  }

  get hasSecondaryKey() {
    return !!this.secondaryKey;
  }

  /**
   * Full, untruncated text for the hover tooltip (oiGraphNode.css/.html) — always the complete
   * label/secondaryKey regardless of whether the CSS ellipsis actually fired, since detecting
   * "is this specific instance currently truncated" would need a runtime DOM measurement this
   * component has no other reason to perform. Real Salesforce record Names routinely run past
   * any width this card could reasonably grow to (a 60-character Opportunity or Task Subject is
   * unremarkable), so a width-only fix can narrow how often this is needed but can never
   * eliminate the need for it — this is the durable backstop, not the primary-fields.
   */
  get tooltipText() {
    return this.secondaryKey
      ? `${this.label} — ${this.secondaryKey}`
      : this.label;
  }

  get expandToggleLabel() {
    return this.isExpanded ? "Collapse" : "Expand";
  }

  handleSelect() {
    this.dispatchEvent(
      new CustomEvent("select", { detail: { nodeKey: this.nodeKey } })
    );
  }

  handleKeydown(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.handleSelect();
    }
  }

  handleExpandToggle(event) {
    event.stopPropagation();
    this.dispatchEvent(
      new CustomEvent("expandtoggle", { detail: { nodeKey: this.nodeKey } })
    );
  }

  handleOpen(event) {
    event.stopPropagation();
    this.dispatchEvent(
      new CustomEvent("open", { detail: { nodeKey: this.nodeKey } })
    );
  }
}
