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
import { LightningElement, api } from 'lwc';

/**
 * SLDS-style semantic categories the Presentation Type Registry's Color_Token__c is documented
 * to use (DataModel.md §4.1) — an unrecognized token (a future registry value this component
 * has never seen) falls back to neutral gray, never a broken style. Each value is an SLDS
 * global styling hook with the *current* literal color as its fallback: when Lightning
 * Experience's Cosmos/dark-mode tokens are present they supply the color (so a node's accent
 * stripe stays correct in dark mode), and when they are not (an older org, a context without
 * SLDS 2) the fallback renders pixel-identical to before this change. Nested inside another
 * custom property (`--oi-node-accent`, consumed by oiGraphNode.css) is ordinary, fully
 * supported CSS custom-property resolution — not a special case.
 */
const COLOR_TOKEN_HEX = {
    brand: 'var(--slds-g-color-accent-1, #0176d3)',
    success: 'var(--slds-g-color-success-1, #2e844a)',
    warning: 'var(--slds-g-color-warning-1, #b57c00)',
    error: 'var(--slds-g-color-error-1, #ba0517)',
    neutral: 'var(--slds-g-color-border-2, #706e6b)'
};
const DEFAULT_COLOR_HEX = COLOR_TOKEN_HEX.neutral;

export default class OiGraphNode extends LightningElement {
    @api nodeKey;
    @api typeKey;
    @api label;
    @api secondaryKey;
    @api state;
    @api iconName = 'standard:custom';
    @api colorToken = 'neutral';
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
            'oi-graph-node' +
            (this.isSelected ? ' is-selected' : '') +
            (this.isCluster ? ' is-cluster' : '') +
            (this.isOnActivePath ? ' is-on-path' : '') +
            (this.isDimmed ? ' is-dimmed' : '')
        );
    }

    /** The relationship chip's text — the single most important thing on the card for answering "why is this here?". Omitted entirely rather than shown empty when the Canvas has no context to give (e.g. the centre node itself). */
    get relationshipChipText() {
        if (!this.relationshipRole) {
            return null;
        }
        return this.relationshipContext ? `${this.relationshipRole} ${this.relationshipContext}` : this.relationshipRole;
    }

    get hasRelationshipChip() {
        return !!this.relationshipChipText;
    }

    /** Distance is stated only beyond one hop: labelling a direct neighbour "1 relationship away" is noise, while leaving a 3-hop node unlabelled actively misleads. */
    get hopLabel() {
        return this.hopDistance > 1 ? `${this.hopDistance} relationships away` : null;
    }

    get hasHopLabel() {
        return !!this.hopLabel;
    }

    get resolvedTypeLabel() {
        return this.typeLabel || '';
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
        const expandState = this.isExpanded ? 'expanded' : 'collapsed';
        const more = this.hasMoreNeighbors ? ', more relationships available' : '';
        const secondary = this.secondaryKey ? `, ${this.secondaryKey}` : '';
        const type = this.typeLabel ? `, ${this.typeLabel}` : '';
        const relationship = this.relationshipChipText ? `, ${this.relationshipChipText}` : '';
        const hops = this.hopLabel ? `, ${this.hopLabel}` : '';
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
        return this.secondaryKey ? `${this.label} — ${this.secondaryKey}` : this.label;
    }

    get expandToggleLabel() {
        return this.isExpanded ? 'Collapse' : 'Expand';
    }

    handleSelect() {
        this.dispatchEvent(new CustomEvent('select', { detail: { nodeKey: this.nodeKey } }));
    }

    handleKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleSelect();
        }
    }

    handleExpandToggle(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('expandtoggle', { detail: { nodeKey: this.nodeKey } }));
    }
}
