/**
 * Purpose: The literal-tree view of one record's descendants within one Hierarchy Definition
 *          (FR-010) — a container: calls OI_HierarchyQueryController.getDescendants only, then
 *          hands the result to oiHierarchyTreeNode for recursive rendering (ADR-0022 §3e).
 * Responsibilities: Re-fetch whenever definitionId/rootObjectApiName/rootRecordId changes
 *                    (three independent reactive @api setters, matching oiHierarchyPath's own
 *                    convention), only once all three are present. Reshape the flat
 *                    relationship list Apex returns into a parent-record-id -> children
 *                    adjacency map exactly once per fetch, not on every render or every node
 *                    expand — expand/collapse state lives entirely in oiHierarchyTreeNode and
 *                    never triggers a re-fetch.
 * Dependencies: OI_HierarchyQueryController.getDescendants, oiHierarchyTreeNode.
 * Limitations: hasMore (from OI_HierarchyDescendantsResult's own bounded-BFS ceiling) is
 *              surfaced as a visible note, never silently dropped (CLAUDE.md "no silent
 *              caps") — there is no "load more" affordance yet; that is real, undesigned
 *              future work, not a bug.
 */
import { LightningElement, api } from 'lwc';
import getDescendants from '@salesforce/apex/OI_HierarchyQueryController.getDescendants';

export default class OiHierarchyTree extends LightningElement {
    @api rootLabel;

    childrenByParentId = new Map();
    hasMore = false;
    isLoading = false;
    errorMessage = null;
    _definitionId;
    _rootObjectApiName;
    _rootRecordId;

    @api
    get definitionId() {
        return this._definitionId;
    }

    set definitionId(value) {
        this._definitionId = value;
        this.maybeLoadDescendants();
    }

    @api
    get rootObjectApiName() {
        return this._rootObjectApiName;
    }

    set rootObjectApiName(value) {
        this._rootObjectApiName = value;
        this.maybeLoadDescendants();
    }

    @api
    get rootRecordId() {
        return this._rootRecordId;
    }

    set rootRecordId(value) {
        this._rootRecordId = value;
        this.maybeLoadDescendants();
    }

    async maybeLoadDescendants() {
        if (!this._definitionId || !this._rootObjectApiName || !this._rootRecordId) {
            this.childrenByParentId = new Map();
            this.hasMore = false;
            return;
        }
        this.isLoading = true;
        this.errorMessage = null;
        try {
            const result = await getDescendants({ definitionId: this._definitionId, parentObjectApiName: this._rootObjectApiName, parentRecordId: this._rootRecordId });
            this.childrenByParentId = this.buildChildrenMap(result.descendants);
            this.hasMore = result.hasMore;
        } catch (error) {
            this.childrenByParentId = new Map();
            this.hasMore = false;
            this.errorMessage = (error && error.body && error.body.message) || 'Something went wrong loading the hierarchy tree. Please try again.';
        } finally {
            this.isLoading = false;
        }
    }

    buildChildrenMap(descendants) {
        const map = new Map();
        for (const relationship of descendants || []) {
            const siblings = map.get(relationship.parentRecordId) || [];
            siblings.push({ recordId: relationship.childRecordId, objectApiName: relationship.childObjectApiName, label: relationship.childLabel || '(not visible)' });
            map.set(relationship.parentRecordId, siblings);
        }
        return map;
    }

    get effectiveRootLabel() {
        return this.rootLabel || this._rootObjectApiName || 'Current record';
    }

    get hasRoot() {
        return !!(this._definitionId && this._rootObjectApiName && this._rootRecordId);
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get rootDepth() {
        return 0;
    }

    handleRootSelect(event) {
        this.dispatchEvent(new CustomEvent('recordselect', { detail: event.detail }));
    }
}
