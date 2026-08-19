/**
 * Purpose: One node in the literal hierarchy tree (ADR-0022 §3e) — a genuine tree renderer,
 *          deliberately not the radial oiGraphCanvas. A configured Hierarchy Definition is, by
 *          admin design (Allow_Multiple_Parents__c defaults off), overwhelmingly a real rooted
 *          tree per hierarchy type, so a literal tree is not the misrepresentation it would be
 *          for the organically multi-parented/cyclic metadata graph (ADR-0019).
 * Responsibilities: Render one record's label + Object type, an expand/collapse toggle when
 *                    it has children (looked up from the shared childrenByParentId map, never
 *                    a per-node Apex call), and recurse into itself for each child. The root
 *                    node's own label is never clickable (navigating to the record you're
 *                    already viewing accomplishes nothing) — only descendant labels emit
 *                    recordselect, relayed upward unchanged through every intermediate level
 *                    via the standard LWC parent-child event-binding chain (a custom event
 *                    does not cross component boundaries on its own without this relay).
 * Dependencies: None — purely presentational, given an already-computed adjacency map.
 * Limitations: Recursion depth is bounded transitively by however many rings
 *              OI_HierarchyQueryService.getDescendants actually returned (itself bounded by
 *              Max_Levels__c/MAX_DESCENDANT_NODE_COUNT) — this component does not separately
 *              enforce a depth ceiling of its own.
 */
import { LightningElement, api } from 'lwc';

export default class OiHierarchyTreeNode extends LightningElement {
    @api nodeRecordId;
    @api nodeObjectApiName;
    @api nodeLabel;
    @api childrenByParentId;
    @api depth = 0;
    _isRoot = false;
    rootExpansionInitialized = false;

    isExpanded = false;

    @api
    get isRoot() {
        return this._isRoot;
    }

    set isRoot(value) {
        this._isRoot = value === true || value === 'true';
        // A hierarchy should communicate its structure immediately. Descendants remain
        // collapsed for progressive disclosure, but the root opens once on first render.
        if (this._isRoot && !this.rootExpansionInitialized) {
            this.isExpanded = true;
            this.rootExpansionInitialized = true;
        }
    }

    get children() {
        return (this.childrenByParentId && this.childrenByParentId.get(this.nodeRecordId)) || [];
    }

    get hasChildren() {
        return this.children.length > 0;
    }

    get showChildren() {
        return this.isExpanded && this.hasChildren;
    }

    get toggleLabel() {
        return this.isExpanded ? 'Collapse' : 'Expand';
    }

    get isLabelClickable() {
        return !this._isRoot;
    }

    get childDepth() {
        return this.depth + 1;
    }

    get nodeStyle() {
        return `padding-left: ${this.depth * 1.25}rem; --oi-tree-indent: ${this.depth * 1.25}rem;`;
    }

    get childrenStyle() {
        return `--oi-tree-child-indent: ${this.childDepth * 1.25}rem;`;
    }

    handleToggle(event) {
        event.stopPropagation();
        this.isExpanded = !this.isExpanded;
    }

    handleLabelClick() {
        this.dispatchEvent(new CustomEvent('recordselect', { detail: { objectApiName: this.nodeObjectApiName, recordId: this.nodeRecordId } }));
    }

    /** Relays a descendant's selection upward unchanged — every intermediate level must do this explicitly since LWC custom events are caught only by a direct parent-child template binding, not native bubbling across component boundaries. */
    handleChildSelect(event) {
        this.dispatchEvent(new CustomEvent('recordselect', { detail: event.detail }));
    }
}
