/**
 * Purpose: The relationship-view filter panel (Backlog UI-4, GraphUI.md §22) — lets a user
 *          choose which kind of relationship tree they're looking at, replacing the earlier
 *          ad hoc relationship-legend toggle row that only ever hid/showed edges by type.
 * Responsibilities: Purely presentational (props in, events out) — never touches
 *                    GraphViewState, never calls Apex, never decides what a typeKey means.
 *                    Renders one checkbox per already-registry-resolved edge type the
 *                    container hands it (so a future edge type — an Apex/Flow dependency,
 *                    say — appears automatically with zero change here), plus direction
 *                    (Parent/Child) and depth (direct-only) controls that are generic
 *                    graph-traversal concepts, not Salesforce-metadata-specific ones.
 * Dependencies: None.
 * Limitations: Direction/depth apply uniformly across every relationship type currently
 *              allowed — there is no per-type direction override (e.g. "outgoing Lookups but
 *              incoming Master-Detail"). GraphUI.md §22 does not ask for that granularity,
 *              and combining it with per-type checkboxes would multiply this panel's states
 *              well past what a "don't overbuild a filter panel" posture should accept.
 */
import { LightningElement, api } from 'lwc';

export default class OiFilterPanel extends LightningElement {
    /** Each option is checkbox state AND legend entry: {typeKey, displayLabel, description, isChecked, swatchClass}. See this component's own doc comment on why the panel now serves both roles. */
    @api edgeTypeOptions = [];
    @api direction = 'both';
    @api restrictToDirectOnly = false;

    get hasEdgeTypeOptions() {
        return (this.edgeTypeOptions || []).length > 0;
    }

    get showParents() {
        return this.direction !== 'incoming';
    }

    get showChildren() {
        return this.direction !== 'outgoing';
    }

    handleEdgeTypeToggle(event) {
        const typeKey = event.currentTarget.dataset.typeKey;
        this.dispatchEvent(new CustomEvent('edgetypetoggle', { detail: { typeKey } }));
    }

    handleParentsToggle() {
        this.dispatchEvent(new CustomEvent('directiontoggle', { detail: { showParents: !this.showParents, showChildren: this.showChildren } }));
    }

    handleChildrenToggle() {
        this.dispatchEvent(new CustomEvent('directiontoggle', { detail: { showParents: this.showParents, showChildren: !this.showChildren } }));
    }

    handleDepthToggle() {
        this.dispatchEvent(new CustomEvent('depthtoggle', { detail: { restrictToDirectOnly: !this.restrictToDirectOnly } }));
    }
}
