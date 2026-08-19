/**
 * Purpose: Admin configuration for Hierarchy Definitions/Levels (FR-001/002) AND relationship
 *          assignment (FR-003/004/005/017/018) — a standalone App Page tool, gated server-side
 *          by OI_Manage_Hierarchy (Definitions/Levels) and OI_Create_Hierarchy/OI_Edit_Hierarchy/
 *          OI_Delete_Hierarchy/OI_View_Hierarchy_History (Relationships). Previously this
 *          component covered ONLY Definitions/Levels — there was no UI anywhere in the package
 *          that could actually create a hierarchy relationship, despite the backend
 *          (OI_HierarchyRelationshipController) being fully built; the Relationships section
 *          below closes that gap.
 * Responsibilities: List Definitions, create/edit one via a form bound to
 *                    OI_HierarchyDefinitionController.saveDefinition's exact parameter shape,
 *                    and — once a Definition has a real Id (Levels are Master-Detail children,
 *                    so they cannot exist before their parent is saved) — list/create/edit/
 *                    delete its Levels via getLevels/saveLevel/deleteLevel, AND list/assign/
 *                    deactivate that Definition's OI_Hierarchy_Relationship__c rows and view a
 *                    child record's history, via OI_HierarchyRelationshipController. Parent/child
 *                    record selection reuses oiRecordPicker exactly as ADR-0022's own UI plan
 *                    intended, scoped to the Definition's Object_Api_Name__c. Every mutation
 *                    updates the in-memory list directly from the Apex call's own returned DTO
 *                    (or removes the deleted Id) rather than re-calling the cacheable
 *                    getDefinitions/getLevels/getRelationships methods again, which would risk
 *                    returning a stale Lightning Data Service cache entry for the very row just
 *                    changed — assignParent's implicit "move deactivates the sibling row" side
 *                    effect is replicated locally for the same reason (see
 *                    upsertRelationshipLocally's own comment).
 * Dependencies: OI_HierarchyDefinitionController (getDefinitions/saveDefinition/getLevels/
 *               saveLevel/deleteLevel), OI_HierarchyRelationshipController (getRelationships/
 *               assignParent/deactivateRelationship/getHistory), oiRecordPicker.
 * Limitations: No delete-confirmation dialog for a Level yet (CLAUDE.md: don't add UI beyond
 *              what's asked) — deleting a Level is a low-stakes, easily-redone admin action,
 *              not a destructive record-data operation. Deleting a Definition itself is not
 *              exposed at all: OI_HierarchyDefinitionController has no delete endpoint by
 *              design (a Definition's Status__c field is the intended deactivation path,
 *              matching Business Rule 7's "deactivate, never hard-delete" spirit already
 *              established for relationships). Parent/child pickers are scoped to the
 *              Definition's own Object_Api_Name__c — a hierarchy whose Levels span more than one
 *              object type cannot have a cross-object relationship assigned from this form yet
 *              (real, documented; still reachable via the Apex API directly).
 */
import { LightningElement } from 'lwc';
import getDefinitions from '@salesforce/apex/OI_HierarchyDefinitionController.getDefinitions';
import saveDefinition from '@salesforce/apex/OI_HierarchyDefinitionController.saveDefinition';
import getLevels from '@salesforce/apex/OI_HierarchyDefinitionController.getLevels';
import saveLevel from '@salesforce/apex/OI_HierarchyDefinitionController.saveLevel';
import deleteLevel from '@salesforce/apex/OI_HierarchyDefinitionController.deleteLevel';
import getRelationships from '@salesforce/apex/OI_HierarchyRelationshipController.getRelationships';
import assignParent from '@salesforce/apex/OI_HierarchyRelationshipController.assignParent';
import deactivateRelationship from '@salesforce/apex/OI_HierarchyRelationshipController.deactivateRelationship';
import getHistory from '@salesforce/apex/OI_HierarchyRelationshipController.getHistory';

const STATUS_OPTIONS = [
    { label: 'Active', value: 'Active' },
    { label: 'Inactive', value: 'Inactive' }
];

function blankDefinitionDraft() {
    return {
        definitionId: null,
        name: '',
        description: '',
        objectApiName: '',
        status: 'Active',
        maxLevels: 10,
        relationshipType: '',
        allowMultipleParents: false,
        allowMultipleHierarchies: false
    };
}

function blankLevelDraft(definitionId) {
    return {
        levelId: null,
        definitionId,
        levelName: '',
        levelNumber: 1,
        objectApiName: '',
        isRequired: false,
        relationshipFieldApiName: ''
    };
}

function blankRelationshipDraft(definitionId) {
    return {
        definitionId,
        parentRecordId: null,
        parentLabel: null,
        childRecordId: null,
        childLabel: null,
        hierarchyLevelId: '',
        relationshipType: '',
        effectiveStartDate: null,
        effectiveEndDate: null
    };
}

function errorMessageFor(error, fallback) {
    return (error && error.body && error.body.message) || fallback;
}

export default class OiHierarchyManager extends LightningElement {
    statusOptions = STATUS_OPTIONS;

    definitions = [];
    isLoadingDefinitions = true;
    definitionsError = null;

    definitionDraft = blankDefinitionDraft();
    isSavingDefinition = false;
    definitionFormError = null;

    levels = [];
    isLoadingLevels = false;
    levelsError = null;

    levelDraft = null;
    isSavingLevel = false;
    levelFormError = null;

    relationships = [];
    isLoadingRelationships = false;
    relationshipsError = null;

    relationshipDraft = null;
    isSavingRelationship = false;
    relationshipFormError = null;

    historyRows = [];
    isLoadingHistory = false;
    historyError = null;
    historyForRelationshipId = null;

    connectedCallback() {
        this.loadDefinitions();
    }

    async loadDefinitions() {
        this.isLoadingDefinitions = true;
        this.definitionsError = null;
        try {
            this.definitions = await getDefinitions();
        } catch (error) {
            this.definitions = [];
            this.definitionsError = errorMessageFor(error, 'Something went wrong loading hierarchy definitions. Please try again.');
        } finally {
            this.isLoadingDefinitions = false;
        }
    }

    get isEditingExistingDefinition() {
        return !!this.definitionDraft.definitionId;
    }

    get definitionFormTitle() {
        return this.isEditingExistingDefinition ? 'Edit Hierarchy' : 'New Hierarchy';
    }

    get hasDefinitionsError() {
        return !!this.definitionsError;
    }

    get hasDefinitionFormError() {
        return !!this.definitionFormError;
    }

    get showLevelsSection() {
        return this.isEditingExistingDefinition;
    }

    get showRelationshipsSection() {
        return this.isEditingExistingDefinition;
    }

    handleNewDefinitionClick() {
        this.definitionDraft = blankDefinitionDraft();
        this.definitionFormError = null;
        this.levels = [];
        this.levelDraft = null;
        this.levelsError = null;
        this.resetRelationshipsState();
    }

    handleDefinitionRowClick(event) {
        const definitionId = event.currentTarget.dataset.definitionId;
        const definition = this.definitions.find((candidate) => candidate.definitionId === definitionId);
        if (!definition) {
            return;
        }
        this.definitionDraft = { ...definition };
        this.definitionFormError = null;
        this.levelDraft = null;
        this.loadLevels(definitionId);
        this.resetRelationshipsState();
        this.loadRelationships(definitionId);
    }

    handleDefinitionFieldChange(event) {
        const field = event.target.dataset.field;
        this.definitionDraft = { ...this.definitionDraft, [field]: event.target.value };
    }

    handleAllowMultipleParentsChange(event) {
        this.definitionDraft = { ...this.definitionDraft, allowMultipleParents: event.target.checked };
    }

    handleAllowMultipleHierarchiesChange(event) {
        this.definitionDraft = { ...this.definitionDraft, allowMultipleHierarchies: event.target.checked };
    }

    async handleSaveDefinition() {
        this.isSavingDefinition = true;
        this.definitionFormError = null;
        try {
            const draft = this.definitionDraft;
            const saved = await saveDefinition({
                definitionId: draft.definitionId,
                recordName: draft.name,
                description: draft.description,
                objectApiName: draft.objectApiName,
                status: draft.status,
                maxLevels: draft.maxLevels === '' || draft.maxLevels === null || draft.maxLevels === undefined ? null : Number(draft.maxLevels),
                relationshipType: draft.relationshipType,
                allowMultipleParents: !!draft.allowMultipleParents,
                allowMultipleHierarchies: !!draft.allowMultipleHierarchies
            });
            this.upsertDefinitionLocally(saved);
            this.definitionDraft = { ...saved };
            if (this.levels.length === 0) {
                this.loadLevels(saved.definitionId);
            }
            if (this.relationships.length === 0) {
                this.loadRelationships(saved.definitionId);
            }
        } catch (error) {
            this.definitionFormError = errorMessageFor(error, 'Something went wrong saving the hierarchy. Please try again.');
        } finally {
            this.isSavingDefinition = false;
        }
    }

    upsertDefinitionLocally(saved) {
        const index = this.definitions.findIndex((candidate) => candidate.definitionId === saved.definitionId);
        if (index === -1) {
            this.definitions = [...this.definitions, saved];
        } else {
            const next = [...this.definitions];
            next[index] = saved;
            this.definitions = next;
        }
    }

    async loadLevels(definitionId) {
        this.isLoadingLevels = true;
        this.levelsError = null;
        try {
            this.levels = await getLevels({ definitionId });
        } catch (error) {
            this.levels = [];
            this.levelsError = errorMessageFor(error, 'Something went wrong loading hierarchy levels. Please try again.');
        } finally {
            this.isLoadingLevels = false;
        }
    }

    get levelRows() {
        return this.levels.map((level) => ({ ...level, requiredLabel: level.isRequired ? 'Yes' : 'No' }));
    }

    get hasLevels() {
        return this.levels.length > 0;
    }

    get hasLevelsError() {
        return !!this.levelsError;
    }

    get hasLevelFormError() {
        return !!this.levelFormError;
    }

    handleAddLevelClick() {
        this.levelDraft = blankLevelDraft(this.definitionDraft.definitionId);
        this.levelFormError = null;
    }

    handleEditLevelClick(event) {
        const levelId = event.currentTarget.dataset.levelId;
        const level = this.levels.find((candidate) => candidate.levelId === levelId);
        if (!level) {
            return;
        }
        this.levelDraft = { ...level };
        this.levelFormError = null;
    }

    handleCancelLevelForm() {
        this.levelDraft = null;
        this.levelFormError = null;
    }

    handleLevelFieldChange(event) {
        const field = event.target.dataset.field;
        this.levelDraft = { ...this.levelDraft, [field]: event.target.value };
    }

    handleLevelRequiredChange(event) {
        this.levelDraft = { ...this.levelDraft, isRequired: event.target.checked };
    }

    async handleSaveLevel() {
        this.isSavingLevel = true;
        this.levelFormError = null;
        try {
            const draft = this.levelDraft;
            const saved = await saveLevel({
                levelId: draft.levelId,
                definitionId: draft.definitionId,
                levelName: draft.levelName,
                levelNumber: draft.levelNumber === '' || draft.levelNumber === null || draft.levelNumber === undefined ? null : Number(draft.levelNumber),
                objectApiName: draft.objectApiName,
                isRequired: !!draft.isRequired,
                relationshipFieldApiName: draft.relationshipFieldApiName
            });
            this.upsertLevelLocally(saved);
            this.levelDraft = null;
        } catch (error) {
            this.levelFormError = errorMessageFor(error, 'Something went wrong saving the hierarchy level. Please try again.');
        } finally {
            this.isSavingLevel = false;
        }
    }

    upsertLevelLocally(saved) {
        const index = this.levels.findIndex((candidate) => candidate.levelId === saved.levelId);
        if (index === -1) {
            this.levels = [...this.levels, saved];
        } else {
            const next = [...this.levels];
            next[index] = saved;
            this.levels = next;
        }
    }

    async handleDeleteLevel(event) {
        const levelId = event.currentTarget.dataset.levelId;
        try {
            await deleteLevel({ levelId });
            this.levels = this.levels.filter((candidate) => candidate.levelId !== levelId);
        } catch (error) {
            this.levelsError = errorMessageFor(error, 'Something went wrong deleting the hierarchy level. Please try again.');
        }
    }

    resetRelationshipsState() {
        this.relationships = [];
        this.relationshipDraft = null;
        this.relationshipsError = null;
        this.relationshipFormError = null;
        this.historyForRelationshipId = null;
        this.historyRows = [];
        this.historyError = null;
    }

    async loadRelationships(definitionId) {
        this.isLoadingRelationships = true;
        this.relationshipsError = null;
        try {
            this.relationships = await getRelationships({ definitionId });
        } catch (error) {
            this.relationships = [];
            this.relationshipsError = errorMessageFor(error, 'Something went wrong loading hierarchy relationships. Please try again.');
        } finally {
            this.isLoadingRelationships = false;
        }
    }

    get hasRelationshipsError() {
        return !!this.relationshipsError;
    }

    get hasRelationships() {
        return this.relationships.length > 0;
    }

    /** Root-level relationships (no Parent_Record_Id__c) display as "(root)" rather than a blank cell — the same "root" concept the FRD's own path rendering (FR-012) already uses. A record whose label failed the accessibility re-check (ADR-0022) falls back to its raw Id, matching oiHierarchyTree's own "(not visible)"-style honesty rather than hiding the row. */
    get relationshipRows() {
        return this.relationships.map((relationship) => ({
            ...relationship,
            parentDisplay: relationship.parentRecordId ? relationship.parentLabel || relationship.parentRecordId : '(root)',
            childDisplay: relationship.childLabel || relationship.childRecordId,
            statusLabel: relationship.isActive ? 'Active' : 'Inactive',
            isHistoryOpenForThisRow: relationship.relationshipId === this.historyForRelationshipId,
            historyRowKey: relationship.relationshipId + '-history'
        }));
    }

    get levelOptions() {
        return [{ label: '(none — root level)', value: '' }, ...this.levels.map((level) => ({ label: level.levelName, value: level.levelId }))];
    }

    get hasRelationshipFormError() {
        return !!this.relationshipFormError;
    }

    /** Both the parent and child pickers are scoped to the Definition's own Object_Api_Name__c — the common case throughout this FRD (Corporate/Territory/Dealer hierarchies are each built on one primary object). A hierarchy whose Levels span more than one object type (Object_Api_Name__c differs per Level) cannot have a cross-object relationship assigned from this form yet — a real, documented limitation, not a silent gap; it remains reachable via the Apex API directly. */
    handleParentSelect(event) {
        this.relationshipDraft = { ...this.relationshipDraft, parentRecordId: event.detail.recordId, parentLabel: event.detail.label };
    }

    handleChildSelect(event) {
        this.relationshipDraft = { ...this.relationshipDraft, childRecordId: event.detail.recordId, childLabel: event.detail.label };
    }

    handleClearParent() {
        this.relationshipDraft = { ...this.relationshipDraft, parentRecordId: null, parentLabel: null };
    }

    handleClearChild() {
        this.relationshipDraft = { ...this.relationshipDraft, childRecordId: null, childLabel: null };
    }

    get hasSelectedParent() {
        return !!(this.relationshipDraft && this.relationshipDraft.parentRecordId);
    }

    get hasSelectedChild() {
        return !!(this.relationshipDraft && this.relationshipDraft.childRecordId);
    }

    handleNewRelationshipClick() {
        this.relationshipDraft = blankRelationshipDraft(this.definitionDraft.definitionId);
        this.relationshipFormError = null;
    }

    handleCancelRelationshipForm() {
        this.relationshipDraft = null;
        this.relationshipFormError = null;
    }

    handleRelationshipFieldChange(event) {
        const field = event.target.dataset.field;
        this.relationshipDraft = { ...this.relationshipDraft, [field]: event.target.value };
    }

    async handleSaveRelationship() {
        this.isSavingRelationship = true;
        this.relationshipFormError = null;
        try {
            const draft = this.relationshipDraft;
            const objectApiName = this.definitionDraft.objectApiName;
            const saved = await assignParent({
                definitionId: draft.definitionId,
                parentObjectApiName: draft.parentRecordId ? objectApiName : null,
                parentRecordId: draft.parentRecordId,
                childObjectApiName: objectApiName,
                childRecordId: draft.childRecordId,
                hierarchyLevelId: draft.hierarchyLevelId || null,
                relationshipType: draft.relationshipType || null,
                effectiveStartDate: draft.effectiveStartDate || null,
                effectiveEndDate: draft.effectiveEndDate || null
            });
            this.upsertRelationshipLocally(saved);
            this.relationshipDraft = null;
        } catch (error) {
            this.relationshipFormError = errorMessageFor(error, 'Something went wrong saving the hierarchy relationship. Please try again.');
        } finally {
            this.isSavingRelationship = false;
        }
    }

    /**
     * assignParent's own return value only ever reflects the ONE row it wrote or moved — never
     * the sibling row a "move" implicitly deactivated (OI_HierarchyRelationshipService's own
     * documented behavior). Re-calling the cacheable getRelationships here would risk a stale
     * cache read for the very rows just changed (the same reasoning upsertDefinitionLocally/
     * upsertLevelLocally already establish for their own cacheable reads), so a move's second,
     * implicit side effect is instead replicated locally: single-parent definitions deactivate
     * any other currently-active row for the same child, mirroring OI_HierarchyRelationshipService's
     * own isMove rule exactly (never invented independently of it).
     */
    upsertRelationshipLocally(saved) {
        const deactivateSiblings = !this.definitionDraft.allowMultipleParents;
        const next = this.relationships
            .filter((relationship) => relationship.relationshipId !== saved.relationshipId)
            .map((relationship) =>
                deactivateSiblings && relationship.isActive && relationship.childRecordId === saved.childRecordId ? { ...relationship, isActive: false } : relationship
            );
        this.relationships = [...next, saved];
    }

    async handleDeactivateRelationship(event) {
        const relationshipId = event.currentTarget.dataset.relationshipId;
        try {
            await deactivateRelationship({ relationshipId });
            this.relationships = this.relationships.map((relationship) => (relationship.relationshipId === relationshipId ? { ...relationship, isActive: false } : relationship));
        } catch (error) {
            this.relationshipsError = errorMessageFor(error, 'Something went wrong deactivating the hierarchy relationship. Please try again.');
        }
    }

    get hasHistoryError() {
        return !!this.historyError;
    }

    get hasHistoryRows() {
        return this.historyRows.length > 0;
    }

    /** History is per CHILD record (FR-017 tracks a record's own parent-change trail), not per relationship row, but the toggle is keyed by the specific row clicked — clicking the same row again closes it, matching the Levels/Definition form's own single-open-item convention. */
    async handleViewHistoryClick(event) {
        const relationshipId = event.currentTarget.dataset.relationshipId;
        if (this.historyForRelationshipId === relationshipId) {
            this.handleCloseHistory();
            return;
        }
        const childObjectApiName = event.currentTarget.dataset.childObjectApiName;
        const childRecordId = event.currentTarget.dataset.childRecordId;
        this.historyForRelationshipId = relationshipId;
        this.isLoadingHistory = true;
        this.historyError = null;
        try {
            this.historyRows = await getHistory({ definitionId: this.definitionDraft.definitionId, childObjectApiName, childRecordId });
        } catch (error) {
            this.historyRows = [];
            this.historyError = errorMessageFor(error, 'Something went wrong loading hierarchy history. Please try again.');
        } finally {
            this.isLoadingHistory = false;
        }
    }

    handleCloseHistory() {
        this.historyForRelationshipId = null;
        this.historyRows = [];
        this.historyError = null;
    }
}
