/**
 * Purpose: One instance per Object-type node when the Presentation Type Registry marks that
 *          type Show_Field_List__c = true (GraphUI.md §20 addendum) — a plain pill, visually
 *          distinguished from a generic oiGraphNode only by its accent border and a compact
 *          field-count line. Presentational only, exactly like oiGraphNode (§5) — never calls
 *          Apex, never touches the registry itself.
 * Responsibilities: Render the object header (icon/label/API name/expand-toggle — expand
 *                    means "reveal related objects," unchanged) plus a field-count line; emit
 *                    select/expandtoggle for the card itself.
 * Limitations (Hierarchy Visualizer field-browser sprint — a deliberate simplification, not
 *              a regression): this card no longer renders its own fields inline, and no
 *              longer offers a "show all fields" toggle. Browsing an object's fields is now
 *              the right-side Detail Panel's job (oiNodeDetailPanel's Fields section — Show
 *              All/Standard/Custom, search, field type), which the user reaches "on demand"
 *              by selecting the object, rather than every object's card being sized by
 *              however many fields it happens to have. Field absorption itself (a field node
 *              never gets its own separate pill on the canvas) is unchanged — see
 *              oiGraphCanvas.js's buildFieldAbsorptionMap — only this card's own field-LIST
 *              rendering is gone; `fields` is still accepted, but solely for its length.
 */
import { LightningElement, api } from 'lwc';

/** Same registry-driven semantic categories and same dark-mode-aware SLDS-hook-with-hex-fallback approach as oiGraphNode.js — see that file's doc comment for the full rationale; duplicated here (not shared) because the two components' own color maps are already independently duplicated, and unifying that is out of scope for this change. */
const COLOR_TOKEN_HEX = {
    brand: 'var(--slds-g-color-accent-1, #0176d3)',
    success: 'var(--slds-g-color-success-1, #2e844a)',
    warning: 'var(--slds-g-color-warning-1, #b57c00)',
    error: 'var(--slds-g-color-error-1, #ba0517)',
    neutral: 'var(--slds-g-color-border-2, #706e6b)'
};
const DEFAULT_COLOR_HEX = COLOR_TOKEN_HEX.neutral;

export default class OiSchemaObjectCard extends LightningElement {
    @api nodeKey;
    @api typeKey;
    @api label;
    @api secondaryKey;
    @api iconName = 'standard:record';
    @api colorToken = 'brand';
    @api isSelected = false;
    @api isExpanded = false;
    @api hasMoreNeighbors = false;
    @api fields = [];

    get cardClass() {
        return 'oi-schema-card' + (this.isSelected ? ' is-selected' : '');
    }

    get resolvedColor() {
        return COLOR_TOKEN_HEX[this.colorToken] || DEFAULT_COLOR_HEX;
    }

    get cardStyle() {
        return `--oi-node-accent: ${this.resolvedColor};`;
    }

    get totalFieldCount() {
        return (this.fields || []).length;
    }

    get fieldCountLabel() {
        const count = this.totalFieldCount;
        return count === 1 ? '1 field' : `${count} fields`;
    }

    get expandToggleLabel() {
        return this.isExpanded ? 'Collapse' : 'Expand';
    }

    /** Full, untruncated header text for the hover tooltip — see oiGraphNode.js's identical getter for the full rationale (real Object/API-name labels routinely outrun any width this card could reasonably grow to). */
    get tooltipText() {
        return this.secondaryKey ? `${this.label} — ${this.secondaryKey}` : this.label;
    }

    get ariaLabel() {
        const expandState = this.isExpanded ? 'expanded' : 'collapsed';
        const more = this.hasMoreNeighbors ? ', more relationships available' : '';
        return `${this.label}, Object, ${this.totalFieldCount} fields, ${expandState}${more}`;
    }

    handleHeaderClick() {
        this.dispatchEvent(new CustomEvent('select', { detail: { nodeKey: this.nodeKey } }));
    }

    handleHeaderKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleHeaderClick();
        }
    }

    handleExpandToggle(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('expandtoggle', { detail: { nodeKey: this.nodeKey } }));
    }
}
