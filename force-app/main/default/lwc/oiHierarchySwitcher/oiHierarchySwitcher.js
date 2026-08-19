/**
 * Purpose: Lets a user pick which configured Hierarchy Definition applies to the current
 *          record's object (FR-006/FR-007) — the entry point for oiHierarchyViewer.
 * Responsibilities: Load every Definition once (cacheable), narrow to the ones that are both
 *                    Active and scoped to the given objectApiName, and auto-select the first
 *                    match whenever the current selection stops being applicable (including on
 *                    first load and whenever objectApiName itself changes, e.g. a Record Page
 *                    instance reused across record navigations). Never silently defaults to a
 *                    hierarchy the caller didn't ask for.
 * Dependencies: OI_HierarchyDefinitionController.getDefinitions.
 * Limitations: If more than one Active Definition applies to the same object, the first one
 *              (Apex's own return order) is auto-selected — there is no documented "default
 *              hierarchy" concept yet (FR-006 names the requirement, not a tie-break rule), so
 *              CLAUDE.md's "never invent missing business requirements" applies here.
 */
import { LightningElement, api } from 'lwc';
import getDefinitions from '@salesforce/apex/OI_HierarchyDefinitionController.getDefinitions';

const ACTIVE_STATUS = 'Active';

export default class OiHierarchySwitcher extends LightningElement {
    allDefinitions = [];
    isLoading = true;
    errorMessage = null;
    _objectApiName;
    _selectedDefinitionId;

    connectedCallback() {
        this.loadDefinitions();
    }

    @api
    get objectApiName() {
        return this._objectApiName;
    }

    set objectApiName(value) {
        this._objectApiName = value;
        this.autoSelect();
    }

    get selectedDefinitionId() {
        return this._selectedDefinitionId;
    }

    async loadDefinitions() {
        this.isLoading = true;
        this.errorMessage = null;
        try {
            this.allDefinitions = await getDefinitions();
            this.autoSelect();
        } catch (error) {
            this.allDefinitions = [];
            this.errorMessage = (error && error.body && error.body.message) || 'Something went wrong loading hierarchies. Please try again.';
        } finally {
            this.isLoading = false;
        }
    }

    get applicableDefinitions() {
        if (!this._objectApiName) {
            return [];
        }
        return this.allDefinitions.filter((definition) => definition.objectApiName === this._objectApiName && definition.status === ACTIVE_STATUS);
    }

    get comboboxOptions() {
        return this.applicableDefinitions.map((definition) => ({ label: definition.name, value: definition.definitionId }));
    }

    get hasApplicableDefinitions() {
        return this.applicableDefinitions.length > 0;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get showEmptyState() {
        return !this.isLoading && !this.hasError && !this.hasApplicableDefinitions;
    }

    /** Re-derives the selection whenever either input to it changes (new data, new objectApiName) — a previous selection that no longer applies is replaced, never left dangling. */
    autoSelect() {
        const applicable = this.applicableDefinitions;
        const stillApplicable = applicable.some((definition) => definition.definitionId === this._selectedDefinitionId);
        if (stillApplicable) {
            return;
        }
        const nextId = applicable.length > 0 ? applicable[0].definitionId : null;
        if (nextId !== this._selectedDefinitionId) {
            this._selectedDefinitionId = nextId;
            this.notifyChange();
        }
    }

    handleChange(event) {
        this._selectedDefinitionId = event.detail.value;
        this.notifyChange();
    }

    notifyChange() {
        this.dispatchEvent(new CustomEvent('definitionchange', { detail: { definitionId: this._selectedDefinitionId } }));
    }
}
