/**
 * Purpose: The root-first ancestor breadcrumb for one record within one Hierarchy Definition
 *          (FR-012) — "Global Enterprise / North America / USA / ABC Motors" rendered as
 *          clickable crumbs.
 * Responsibilities: Re-fetch OI_HierarchyQueryController.getPath whenever definitionId,
 *                    objectApiName, or recordId changes (three independent reactive @api
 *                    setters, matching oiNodeDetailPanel's own nodeKey-setter convention), and
 *                    only once all three are present. Emit recordselect (never navigate
 *                    directly — that decision belongs to whatever composes this component,
 *                    e.g. oiHierarchyViewer's NavigationMixin) when an ancestor crumb is
 *                    clicked.
 * Dependencies: OI_HierarchyQueryController.getPath.
 * Limitations: The trailing "current record" crumb is derived from the last path entry's own
 *              already-resolved childLabel whenever the record has at least one ancestor —
 *              never a second query just to fetch its own name. For a root-level record (zero
 *              ancestors), there is no free source for that label, so the caller may supply
 *              one via currentRecordLabel; if it doesn't, the trail simply reports that the
 *              record is a root rather than fabricating a label. Whenever this label becomes
 *              known, it is also broadcast via a currentrecordlabel event so a sibling
 *              component (e.g. oiHierarchyTree, which has no label source of its own for the
 *              record it's rooted on) can reuse it instead of issuing its own query.
 */
import { LightningElement, api } from 'lwc';
import getPath from '@salesforce/apex/OI_HierarchyQueryController.getPath';

export default class OiHierarchyPath extends LightningElement {
    path = [];
    isLoading = false;
    errorMessage = null;
    _definitionId;
    _objectApiName;
    _recordId;

    @api currentRecordLabel;

    @api
    get definitionId() {
        return this._definitionId;
    }

    set definitionId(value) {
        this._definitionId = value;
        this.maybeLoadPath();
    }

    @api
    get objectApiName() {
        return this._objectApiName;
    }

    set objectApiName(value) {
        this._objectApiName = value;
        this.maybeLoadPath();
    }

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        this.maybeLoadPath();
    }

    async maybeLoadPath() {
        if (!this._definitionId || !this._objectApiName || !this._recordId) {
            this.path = [];
            return;
        }
        this.isLoading = true;
        this.errorMessage = null;
        try {
            this.path = await getPath({ definitionId: this._definitionId, childObjectApiName: this._objectApiName, childRecordId: this._recordId });
            this.emitCurrentRecordLabelIfKnown();
        } catch (error) {
            this.path = [];
            this.errorMessage = (error && error.body && error.body.message) || 'Something went wrong loading the hierarchy path. Please try again.';
        } finally {
            this.isLoading = false;
        }
    }

    get crumbs() {
        const ancestorCrumbs = this.path.map((relationship) => ({
            key: relationship.relationshipId,
            recordId: relationship.parentRecordId,
            objectApiName: relationship.parentObjectApiName,
            label: relationship.parentLabel || '(not visible)',
            isCurrent: false
        }));
        if (this.path.length > 0) {
            const last = this.path[this.path.length - 1];
            ancestorCrumbs.push({
                key: 'current',
                recordId: last.childRecordId,
                objectApiName: last.childObjectApiName,
                label: last.childLabel || this.currentRecordLabel || '(not visible)',
                isCurrent: true
            });
        } else if (this.currentRecordLabel) {
            ancestorCrumbs.push({
                key: 'current',
                recordId: this._recordId,
                objectApiName: this._objectApiName,
                label: this.currentRecordLabel,
                isCurrent: true
            });
        }
        return ancestorCrumbs;
    }

    get hasCrumbs() {
        return this.crumbs.length > 0;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get showRootNote() {
        return !this.isLoading && !this.hasError && this.path.length === 0;
    }

    /** The current record's own resolved name is only ever available as a side effect of the last path entry's childLabel — there is no query dedicated to fetching it, so this only fires when the record actually has an ancestor. */
    emitCurrentRecordLabelIfKnown() {
        if (this.path.length === 0) {
            return;
        }
        const label = this.path[this.path.length - 1].childLabel;
        if (label) {
            this.dispatchEvent(new CustomEvent('currentrecordlabel', { detail: { label } }));
        }
    }

    handleCrumbClick(event) {
        const recordId = event.currentTarget.dataset.recordId;
        const objectApiName = event.currentTarget.dataset.objectApiName;
        this.dispatchEvent(new CustomEvent('recordselect', { detail: { objectApiName, recordId } }));
    }
}
