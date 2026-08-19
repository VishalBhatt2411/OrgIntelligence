/**
 * Purpose: Verifies OI_HierarchyRelationshipService's create/move/deactivate orchestration
 *          and the audit trail each writes.
 */
@isTest
private class OI_HierarchyRelationshipServiceTest {
    @isTest
    static void testAssignParentCreatesARootLevelRelationshipAndAHistoryRow() {
        Id definitionId = insertDefinition('Test Def', false);
        Account child = new Account(Name = 'Child A');
        insert child;

        OI_Hierarchy_Relationship__c saved = new OI_HierarchyRelationshipService().assignParent(definitionId, null, null, 'Account', child.Id, null, 'Reports To', null, null);

        System.assertEquals(true, saved.Is_Active__c);
        System.assertEquals(definitionId, saved.Hierarchy_Definition__c);
        List<OI_Hierarchy_Relationship_History__c> history = [SELECT Change_Type__c, New_Parent_Record_Id__c FROM OI_Hierarchy_Relationship_History__c WHERE Child_Record_Id__c = :child.Id];
        System.assertEquals(1, history.size());
        System.assertEquals('Created', history[0].Change_Type__c);
    }

    @isTest
    static void testAssignParentTwiceWithoutMultipleParentsMovesTheChildAndWritesAMovedHistoryRow() {
        Id definitionId = insertDefinition('Test Def', false);
        Account parent1 = new Account(Name = 'Parent 1');
        Account parent2 = new Account(Name = 'Parent 2');
        Account child = new Account(Name = 'Child A');
        insert new List<Account>{ parent1, parent2, child };

        OI_HierarchyRelationshipService service = new OI_HierarchyRelationshipService();
        service.assignParent(definitionId, 'Account', parent1.Id, 'Account', child.Id, null, null, null, null);
        service.assignParent(definitionId, 'Account', parent2.Id, 'Account', child.Id, null, null, null, null);

        List<OI_Hierarchy_Relationship__c> activeForChild = [SELECT Parent_Record_Id__c FROM OI_Hierarchy_Relationship__c WHERE Child_Record_Id__c = :child.Id AND Is_Active__c = true];
        System.assertEquals(1, activeForChild.size(), 'Only one active parent must remain when Allow_Multiple_Parents__c is false.');
        System.assertEquals(parent2.Id, activeForChild[0].Parent_Record_Id__c);

        List<OI_Hierarchy_Relationship__c> inactiveForChild = [SELECT Id FROM OI_Hierarchy_Relationship__c WHERE Child_Record_Id__c = :child.Id AND Is_Active__c = false];
        System.assertEquals(1, inactiveForChild.size(), 'The original parent1 relationship must be deactivated, never deleted (FR-017 audit).');

        List<OI_Hierarchy_Relationship_History__c> moveHistory = [
            SELECT Change_Type__c, Previous_Parent_Record_Id__c, New_Parent_Record_Id__c
            FROM OI_Hierarchy_Relationship_History__c
            WHERE Child_Record_Id__c = :child.Id AND Change_Type__c = 'Moved'
        ];
        System.assertEquals(1, moveHistory.size());
        System.assertEquals(parent1.Id, moveHistory[0].Previous_Parent_Record_Id__c);
        System.assertEquals(parent2.Id, moveHistory[0].New_Parent_Record_Id__c);
    }

    @isTest
    static void testAssignParentAllowsASecondConcurrentParentWhenMultipleParentsIsEnabled() {
        Id definitionId = insertDefinition('Multi Parent Def', true);
        Account parent1 = new Account(Name = 'Parent 1');
        Account parent2 = new Account(Name = 'Parent 2');
        Account child = new Account(Name = 'Child A');
        insert new List<Account>{ parent1, parent2, child };

        OI_HierarchyRelationshipService service = new OI_HierarchyRelationshipService();
        service.assignParent(definitionId, 'Account', parent1.Id, 'Account', child.Id, null, null, null, null);
        service.assignParent(definitionId, 'Account', parent2.Id, 'Account', child.Id, null, null, null, null);

        List<OI_Hierarchy_Relationship__c> activeForChild = [SELECT Id FROM OI_Hierarchy_Relationship__c WHERE Child_Record_Id__c = :child.Id AND Is_Active__c = true];
        System.assertEquals(2, activeForChild.size(), 'Both parents must remain active when Allow_Multiple_Parents__c is true.');
    }

    @isTest
    static void testAssignParentRejectsACircularAssignment() {
        Id definitionId = insertDefinition('Test Def', false);
        Account a = new Account(Name = 'A');
        Account b = new Account(Name = 'B');
        insert new List<Account>{ a, b };

        OI_HierarchyRelationshipService service = new OI_HierarchyRelationshipService();
        service.assignParent(definitionId, 'Account', b.Id, 'Account', a.Id, null, null, null, null); // b is a's parent

        try {
            service.assignParent(definitionId, 'Account', a.Id, 'Account', b.Id, null, null, null, null); // proposed: a becomes b's parent -> cycle
            System.assert(false, 'Expected circular-relationship rejection.');
        } catch (OI_ValidationException e) {
            System.assert(e.getMessage().contains('Circular Relationship'));
        }
    }

    @isTest
    static void testDeactivateRelationshipFlipsIsActiveAndWritesADeactivatedHistoryRow() {
        Id definitionId = insertDefinition('Test Def', false);
        Account child = new Account(Name = 'Child A');
        insert child;
        OI_Hierarchy_Relationship__c saved = new OI_HierarchyRelationshipService().assignParent(definitionId, null, null, 'Account', child.Id, null, null, null, null);

        new OI_HierarchyRelationshipService().deactivateRelationship(saved.Id);

        OI_Hierarchy_Relationship__c reloaded = [SELECT Is_Active__c FROM OI_Hierarchy_Relationship__c WHERE Id = :saved.Id];
        System.assertEquals(false, reloaded.Is_Active__c);
        List<OI_Hierarchy_Relationship_History__c> history = [SELECT Change_Type__c FROM OI_Hierarchy_Relationship_History__c WHERE Child_Record_Id__c = :child.Id AND Change_Type__c = 'Deactivated'];
        System.assertEquals(1, history.size());
    }

    @isTest
    static void testAssignParentRejectsAHierarchyLevelFromAnotherDefinition() {
        Id definitionId = insertDefinition('Test Def', false);
        Id otherDefinitionId = insertDefinition('Other Def', false);
        OI_Hierarchy_Level__c levelFromOtherDefinition = new OI_Hierarchy_Level__c(Name = 'Level 1', Hierarchy_Definition__c = otherDefinitionId, Object_Api_Name__c = 'Account', Level_Number__c = 1);
        insert levelFromOtherDefinition;
        Account child = new Account(Name = 'Child A');
        insert child;

        try {
            new OI_HierarchyRelationshipService().assignParent(definitionId, null, null, 'Account', child.Id, levelFromOtherDefinition.Id, null, null, null);
            System.assert(false, 'Expected rejection of a Hierarchy Level that belongs to a different Hierarchy Definition (Business Rule 9).');
        } catch (OI_ValidationException e) {
            System.assert(e.getMessage().contains('Invalid Parent'));
        }
    }

    @isTest
    static void testAssignParentRejectsAnUnknownDefinition() {
        try {
            new OI_HierarchyRelationshipService().assignParent(null, null, null, 'Account', '001000000000001AAA', null, null, null, null);
            System.assert(false, 'Expected rejection of a null/unknown definition.');
        } catch (OI_ValidationException e) {
            System.assert(e.getMessage().contains('Unknown hierarchy definition'));
        }
    }

    private static Id insertDefinition(String recordName, Boolean allowMultipleParents) {
        OI_Hierarchy_Definition__c definition = new OI_Hierarchy_Definition__c(
            Name = recordName,
            Object_Api_Name__c = 'Account',
            Status__c = 'Active',
            Max_Levels__c = 10,
            Allow_Multiple_Parents__c = allowMultipleParents
        );
        insert definition;
        return definition.Id;
    }
}
