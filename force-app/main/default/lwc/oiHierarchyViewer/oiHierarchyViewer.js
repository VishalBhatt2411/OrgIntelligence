/**
 * Purpose: The Record Page-droppable Hierarchy Accelerator widget (FR-025, ADR-0022 §3e) —
 *          composes oiHierarchySwitcher + oiHierarchyPath + oiHierarchyTree for the record the
 *          widget is placed on.
 * Responsibilities: Read recordId/objectApiName from Lightning page context (Lightning App
 *                    Builder auto-populates these exact @api property names on a Record Page),
 *                    resolve which Hierarchy Definition applies via oiHierarchySwitcher, and
 *                    wire that definitionId into both oiHierarchyPath and oiHierarchyTree for
 *                    the same record. Forwards oiHierarchyPath's free currentrecordlabel
 *                    broadcast into oiHierarchyTree's rootLabel, so the tree's root shows the
 *                    record's real name rather than a generic placeholder, without a second
 *                    query. A recordselect bubbled up from either child navigates the user to
 *                    that record's own standard record page via NavigationMixin — this widget
 *                    owns neither recordId nor objectApiName (the Record Page does), so
 *                    "selecting" a different record can only ever mean navigating away, never
 *                    re-rendering in place.
 * Dependencies: oiHierarchySwitcher, oiHierarchyPath, oiHierarchyTree, NavigationMixin.
 * Limitations: If zero Active Definitions apply to the page's object, only the switcher's own
 *              empty-state message renders — Path/Tree are not shown, per oiHierarchySwitcher's
 *              own documented null-definitionId contract.
 */
import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class OiHierarchyViewer extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;

    definitionId = null;
    currentRecordLabel = null;

    get hasDefinition() {
        return !!this.definitionId;
    }

    handleDefinitionChange(event) {
        this.definitionId = event.detail.definitionId;
        this.currentRecordLabel = null;
    }

    handleCurrentRecordLabel(event) {
        this.currentRecordLabel = event.detail.label;
    }

    handleRecordSelect(event) {
        const { objectApiName, recordId } = event.detail;
        if (!recordId || recordId === this.recordId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName,
                actionName: 'view'
            }
        });
    }
}
