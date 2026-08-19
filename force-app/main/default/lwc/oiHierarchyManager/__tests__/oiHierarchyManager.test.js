import { createElement } from 'lwc';
import OiHierarchyManager from 'c/oiHierarchyManager';
import getDefinitions from '@salesforce/apex/OI_HierarchyDefinitionController.getDefinitions';
import saveDefinition from '@salesforce/apex/OI_HierarchyDefinitionController.saveDefinition';
import getLevels from '@salesforce/apex/OI_HierarchyDefinitionController.getLevels';
import saveLevel from '@salesforce/apex/OI_HierarchyDefinitionController.saveLevel';
import deleteLevel from '@salesforce/apex/OI_HierarchyDefinitionController.deleteLevel';
import getRelationships from '@salesforce/apex/OI_HierarchyRelationshipController.getRelationships';
import assignParent from '@salesforce/apex/OI_HierarchyRelationshipController.assignParent';
import deactivateRelationship from '@salesforce/apex/OI_HierarchyRelationshipController.deactivateRelationship';
import getHistory from '@salesforce/apex/OI_HierarchyRelationshipController.getHistory';

jest.mock('@salesforce/apex/OI_HierarchyDefinitionController.getDefinitions', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_HierarchyDefinitionController.saveDefinition', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_HierarchyDefinitionController.getLevels', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_HierarchyDefinitionController.saveLevel', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_HierarchyDefinitionController.deleteLevel', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_HierarchyRelationshipController.getRelationships', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_HierarchyRelationshipController.assignParent', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_HierarchyRelationshipController.deactivateRelationship', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OI_HierarchyRelationshipController.getHistory', () => ({ default: jest.fn() }), { virtual: true });

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const EXISTING_DEFINITION = { definitionId: 'def1', name: 'Corporate Hierarchy', description: 'desc', objectApiName: 'Account', status: 'Active', maxLevels: 10, relationshipType: 'Corporate', allowMultipleParents: false, allowMultipleHierarchies: false };

const EXISTING_RELATIONSHIP = {
    relationshipId: 'rel1',
    definitionId: 'def1',
    levelId: null,
    parentObjectApiName: null,
    parentRecordId: null,
    parentLabel: null,
    childObjectApiName: 'Account',
    childRecordId: '001x1',
    childLabel: 'Acme Corp',
    effectiveStartDate: null,
    effectiveEndDate: null,
    isActive: true,
    relationshipType: 'Corporate'
};

describe('c-oi-hierarchy-manager', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    beforeEach(() => {
        getDefinitions.mockReset();
        saveDefinition.mockReset();
        getLevels.mockReset();
        saveLevel.mockReset();
        deleteLevel.mockReset();
        getRelationships.mockReset();
        assignParent.mockReset();
        deactivateRelationship.mockReset();
        getHistory.mockReset();
        // Every existing test that selects/saves a Definition now also triggers loadRelationships
        // (Relationships load alongside Levels) -- default to an empty list so tests unrelated to
        // Relationships don't need their own boilerplate mock just to avoid an unhandled undefined.
        getRelationships.mockResolvedValue([]);
    });

    it('lists loaded definitions and hides the Levels section until an existing one is selected', async () => {
        getDefinitions.mockResolvedValue([EXISTING_DEFINITION]);
        const element = createElement('c-oi-hierarchy-manager', { is: OiHierarchyManager });
        document.body.appendChild(element);
        await flushPromises();

        const rows = element.shadowRoot.querySelectorAll('[data-id="definition-row"]');
        expect(rows).toHaveLength(1);
        expect(element.shadowRoot.querySelector('[data-id="add-level-button"]')).toBeNull();
    });

    it('loads and shows Levels once an existing definition row is clicked', async () => {
        getDefinitions.mockResolvedValue([EXISTING_DEFINITION]);
        getLevels.mockResolvedValue([{ levelId: 'lvl1', definitionId: 'def1', levelName: 'Region', levelNumber: 1, objectApiName: 'Account', isRequired: true, relationshipFieldApiName: 'ParentId' }]);
        const element = createElement('c-oi-hierarchy-manager', { is: OiHierarchyManager });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="definition-row"]').click();
        await flushPromises();

        expect(getLevels).toHaveBeenCalledWith({ definitionId: 'def1' });
        const table = element.shadowRoot.querySelector('[data-id="levels-table"]');
        expect(table).not.toBeNull();
        expect(table.textContent).toContain('Region');
        expect(table.textContent).toContain('Yes');
    });

    it('never calls getLevels for the blank draft before it has a real Id (Levels are Master-Detail children that cannot exist yet)', async () => {
        getDefinitions.mockResolvedValue([]);
        const element = createElement('c-oi-hierarchy-manager', { is: OiHierarchyManager });
        document.body.appendChild(element);
        await flushPromises();

        expect(getLevels).not.toHaveBeenCalled();
    });

    it('reveals the Levels section immediately after saving a brand-new definition, without a page reload', async () => {
        getDefinitions.mockResolvedValue([]);
        getLevels.mockResolvedValue([]);
        saveDefinition.mockResolvedValue({ ...EXISTING_DEFINITION, definitionId: 'def2', name: 'New One' });
        const element = createElement('c-oi-hierarchy-manager', { is: OiHierarchyManager });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="save-definition-button"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="add-level-button"]')).not.toBeNull();
    });

    it('upserts the saved Level into the local list without re-calling getLevels (avoids a stale cacheable read)', async () => {
        getDefinitions.mockResolvedValue([EXISTING_DEFINITION]);
        getLevels.mockResolvedValue([]);
        saveLevel.mockResolvedValue({ levelId: 'lvl1', definitionId: 'def1', levelName: 'Region', levelNumber: 1, objectApiName: 'Account', isRequired: false, relationshipFieldApiName: 'ParentId' });
        const element = createElement('c-oi-hierarchy-manager', { is: OiHierarchyManager });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="definition-row"]').click();
        await flushPromises();
        expect(getLevels).toHaveBeenCalledTimes(1);

        element.shadowRoot.querySelector('[data-id="add-level-button"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="save-level-button"]').click();
        await flushPromises();

        expect(getLevels).toHaveBeenCalledTimes(1);
        const table = element.shadowRoot.querySelector('[data-id="levels-table"]');
        expect(table.textContent).toContain('Region');
    });

    it('removes a deleted Level from the local list on delete', async () => {
        getDefinitions.mockResolvedValue([EXISTING_DEFINITION]);
        getLevels.mockResolvedValue([{ levelId: 'lvl1', definitionId: 'def1', levelName: 'Region', levelNumber: 1, objectApiName: 'Account', isRequired: false, relationshipFieldApiName: 'ParentId' }]);
        deleteLevel.mockResolvedValue(undefined);
        const element = createElement('c-oi-hierarchy-manager', { is: OiHierarchyManager });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="definition-row"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="delete-level-button"]').click();
        await flushPromises();

        expect(deleteLevel).toHaveBeenCalledWith({ levelId: 'lvl1' });
        expect(element.shadowRoot.querySelector('[data-id="levels-empty"]')).not.toBeNull();
    });

    it('surfaces a save failure as a visible form error, never a silently dropped save', async () => {
        getDefinitions.mockResolvedValue([]);
        saveDefinition.mockRejectedValue({ body: { message: 'Duplicate Relationship — this hierarchy relationship already exists.' } });
        const element = createElement('c-oi-hierarchy-manager', { is: OiHierarchyManager });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="save-definition-button"]').click();
        await flushPromises();

        const error = element.shadowRoot.querySelector('[data-id="definition-form-error"]');
        expect(error.textContent).toBe('Duplicate Relationship — this hierarchy relationship already exists.');
    });

    it('loads and lists relationships once an existing definition is selected', async () => {
        getDefinitions.mockResolvedValue([EXISTING_DEFINITION]);
        getLevels.mockResolvedValue([]);
        getRelationships.mockResolvedValue([EXISTING_RELATIONSHIP]);
        const element = createElement('c-oi-hierarchy-manager', { is: OiHierarchyManager });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="definition-row"]').click();
        await flushPromises();

        expect(getRelationships).toHaveBeenCalledWith({ definitionId: 'def1' });
        const table = element.shadowRoot.querySelector('[data-id="relationships-table"]');
        expect(table).not.toBeNull();
        expect(table.textContent).toContain('Acme Corp');
        expect(table.textContent).toContain('(root)');
        expect(table.textContent).toContain('Active');
    });

    it('shows an empty state when a definition has no relationships yet', async () => {
        getDefinitions.mockResolvedValue([EXISTING_DEFINITION]);
        getLevels.mockResolvedValue([]);
        getRelationships.mockResolvedValue([]);
        const element = createElement('c-oi-hierarchy-manager', { is: OiHierarchyManager });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="definition-row"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="relationships-empty"]')).not.toBeNull();
    });

    it('assigns a new relationship by picking child/parent records via oiRecordPicker and saving', async () => {
        getDefinitions.mockResolvedValue([EXISTING_DEFINITION]);
        getLevels.mockResolvedValue([]);
        getRelationships.mockResolvedValue([]);
        const savedRelationship = { ...EXISTING_RELATIONSHIP, relationshipId: 'rel2', parentObjectApiName: 'Account', parentRecordId: '001root', parentLabel: 'Root Co' };
        assignParent.mockResolvedValue(savedRelationship);
        const element = createElement('c-oi-hierarchy-manager', { is: OiHierarchyManager });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="definition-row"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="add-relationship-button"]').click();
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="child-record-picker"]').dispatchEvent(new CustomEvent('select', { detail: { recordId: '001x1', label: 'Acme Corp' } }));
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="parent-record-picker"]').dispatchEvent(new CustomEvent('select', { detail: { recordId: '001root', label: 'Root Co' } }));
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="save-relationship-button"]').click();
        await flushPromises();

        expect(assignParent).toHaveBeenCalledWith({
            definitionId: 'def1',
            parentObjectApiName: 'Account',
            parentRecordId: '001root',
            childObjectApiName: 'Account',
            childRecordId: '001x1',
            hierarchyLevelId: null,
            relationshipType: null,
            effectiveStartDate: null,
            effectiveEndDate: null
        });
        expect(element.shadowRoot.querySelector('[data-id="relationship-form"]')).toBeNull();
        const table = element.shadowRoot.querySelector('[data-id="relationships-table"]');
        expect(table.textContent).toContain('Root Co');
        expect(table.textContent).toContain('Acme Corp');
    });

    it('deactivates a relationship', async () => {
        getDefinitions.mockResolvedValue([EXISTING_DEFINITION]);
        getLevels.mockResolvedValue([]);
        getRelationships.mockResolvedValue([EXISTING_RELATIONSHIP]);
        deactivateRelationship.mockResolvedValue(undefined);
        const element = createElement('c-oi-hierarchy-manager', { is: OiHierarchyManager });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="definition-row"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="deactivate-relationship-button"]').click();
        await flushPromises();

        expect(deactivateRelationship).toHaveBeenCalledWith({ relationshipId: 'rel1' });
        expect(element.shadowRoot.querySelector('[data-id="relationships-table"]').textContent).toContain('Inactive');
    });

    it("views a relationship's history and closes it again on a second click of the same row", async () => {
        getDefinitions.mockResolvedValue([EXISTING_DEFINITION]);
        getLevels.mockResolvedValue([]);
        getRelationships.mockResolvedValue([EXISTING_RELATIONSHIP]);
        getHistory.mockResolvedValue([
            {
                historyId: 'h1',
                childObjectApiName: 'Account',
                childRecordId: '001x1',
                previousParentRecordId: null,
                previousParentLabel: null,
                newParentRecordId: null,
                newParentLabel: null,
                changedByName: 'Jane Admin',
                changedDate: '2026-08-19T00:00:00.000Z',
                changeType: 'Created'
            }
        ]);
        const element = createElement('c-oi-hierarchy-manager', { is: OiHierarchyManager });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="definition-row"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="view-history-button"]').click();
        await flushPromises();

        expect(getHistory).toHaveBeenCalledWith({ definitionId: 'def1', childObjectApiName: 'Account', childRecordId: '001x1' });
        expect(element.shadowRoot.querySelector('[data-id="history-list"]').textContent).toContain('Created');

        element.shadowRoot.querySelector('[data-id="view-history-button"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="history-panel"]')).toBeNull();
    });

    it('surfaces a relationship save failure as a visible form error', async () => {
        getDefinitions.mockResolvedValue([EXISTING_DEFINITION]);
        getLevels.mockResolvedValue([]);
        getRelationships.mockResolvedValue([]);
        assignParent.mockRejectedValue({ body: { message: 'Invalid Parent — the selected hierarchy level is not valid for this hierarchy.' } });
        const element = createElement('c-oi-hierarchy-manager', { is: OiHierarchyManager });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="definition-row"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="add-relationship-button"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="child-record-picker"]').dispatchEvent(new CustomEvent('select', { detail: { recordId: '001x1', label: 'Acme Corp' } }));
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="save-relationship-button"]').click();
        await flushPromises();

        const error = element.shadowRoot.querySelector('[data-id="relationship-form-error"]');
        expect(error.textContent).toBe('Invalid Parent — the selected hierarchy level is not valid for this hierarchy.');
    });

    it('a move (single-parent Definition) locally deactivates the sibling relationship for the same child, without re-fetching the cacheable list', async () => {
        getDefinitions.mockResolvedValue([EXISTING_DEFINITION]);
        getLevels.mockResolvedValue([]);
        const existingActiveParent = { ...EXISTING_RELATIONSHIP, relationshipId: 'rel1', parentObjectApiName: 'Account', parentRecordId: '001oldparent', parentLabel: 'Old Parent' };
        getRelationships.mockResolvedValue([existingActiveParent]);
        const movedRelationship = { ...EXISTING_RELATIONSHIP, relationshipId: 'rel2', parentObjectApiName: 'Account', parentRecordId: '001newparent', parentLabel: 'New Parent' };
        assignParent.mockResolvedValue(movedRelationship);
        const element = createElement('c-oi-hierarchy-manager', { is: OiHierarchyManager });
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="definition-row"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="add-relationship-button"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="child-record-picker"]').dispatchEvent(new CustomEvent('select', { detail: { recordId: '001x1', label: 'Acme Corp' } }));
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="parent-record-picker"]').dispatchEvent(new CustomEvent('select', { detail: { recordId: '001newparent', label: 'New Parent' } }));
        await flushPromises();
        element.shadowRoot.querySelector('[data-id="save-relationship-button"]').click();
        await flushPromises();

        expect(getRelationships).toHaveBeenCalledTimes(1);
        const rows = Array.from(element.shadowRoot.querySelectorAll('[data-id="relationships-table"] tbody tr'));
        const oldParentRow = rows.find((row) => row.textContent.includes('Old Parent'));
        const newParentRow = rows.find((row) => row.textContent.includes('New Parent'));
        expect(oldParentRow.textContent).toContain('Inactive');
        expect(newParentRow.textContent).not.toContain('Inactive');
    });
});
