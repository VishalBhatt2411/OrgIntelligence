/**
 * Purpose: Verifies OI_HierarchyValidationService's FRD business-rule enforcement —
 *          self-parent, duplicate, inactive-definition, circular-relationship detection
 *          (including the mandatory cyclic fixture), multiple-parents policy, and effective
 *          dates.
 */
@isTest
private class OI_HierarchyValidationServiceTest {
    @isTest
    static void testValidateAssignmentRejectsAnInactiveDefinition() {
        OI_Hierarchy_Definition__c definition = new OI_Hierarchy_Definition__c(Name = 'Test', Object_Api_Name__c = 'Account', Status__c = 'Inactive', Max_Levels__c = 10);
        try {
            new OI_HierarchyValidationService().validateAssignment(definition, new List<OI_Hierarchy_Relationship__c>(), 'parent1', 'child1');
            System.assert(false, 'Expected rejection of an inactive hierarchy.');
        } catch (OI_ValidationException e) {
            System.assert(e.getMessage().contains('Inactive Hierarchy'));
        }
    }

    @isTest
    static void testValidateAssignmentRejectsARecordAsItsOwnParent() {
        OI_Hierarchy_Definition__c definition = new OI_Hierarchy_Definition__c(Name = 'Test', Object_Api_Name__c = 'Account', Status__c = 'Active', Max_Levels__c = 10);
        try {
            new OI_HierarchyValidationService().validateAssignment(definition, new List<OI_Hierarchy_Relationship__c>(), 'sameId', 'sameId');
            System.assert(false, 'Expected rejection of a self-parent assignment.');
        } catch (OI_ValidationException e) {
            System.assert(e.getMessage().contains('cannot be its own parent'));
        }
    }

    @isTest
    static void testValidateAssignmentAllowsARootLevelAssignmentWithNoParent() {
        OI_Hierarchy_Definition__c definition = new OI_Hierarchy_Definition__c(Name = 'Test', Object_Api_Name__c = 'Account', Status__c = 'Active', Max_Levels__c = 10);
        new OI_HierarchyValidationService().validateAssignment(definition, new List<OI_Hierarchy_Relationship__c>(), null, 'child1');
        System.assert(true, 'A root-level assignment (blank parent) must not throw.');
    }

    @isTest
    static void testAssertNotDuplicateRejectsAnExactExistingActivePair() {
        List<OI_Hierarchy_Relationship__c> existing = new List<OI_Hierarchy_Relationship__c>{
            new OI_Hierarchy_Relationship__c(Parent_Record_Id__c = 'p1', Child_Record_Id__c = 'c1', Is_Active__c = true)
        };
        try {
            new OI_HierarchyValidationService().assertNotDuplicate(existing, 'p1', 'c1');
            System.assert(false, 'Expected rejection of an exact duplicate active pair.');
        } catch (OI_ValidationException e) {
            System.assert(e.getMessage().contains('Duplicate Relationship'));
        }
    }

    @isTest
    static void testAssertNotDuplicateAllowsTheSameChildWithADifferentParent() {
        List<OI_Hierarchy_Relationship__c> existing = new List<OI_Hierarchy_Relationship__c>{
            new OI_Hierarchy_Relationship__c(Parent_Record_Id__c = 'p1', Child_Record_Id__c = 'c1', Is_Active__c = true)
        };
        new OI_HierarchyValidationService().assertNotDuplicate(existing, 'p2', 'c1');
        System.assert(true, 'A different parent for the same child must not be treated as a duplicate — this is exactly what Allow_Multiple_Parents__c is meant to permit.');
    }

    @isTest
    static void testAssertNotDuplicateIgnoresAnInactiveMatch() {
        List<OI_Hierarchy_Relationship__c> existing = new List<OI_Hierarchy_Relationship__c>{
            new OI_Hierarchy_Relationship__c(Parent_Record_Id__c = 'p1', Child_Record_Id__c = 'c1', Is_Active__c = false)
        };
        new OI_HierarchyValidationService().assertNotDuplicate(existing, 'p1', 'c1');
        System.assert(true, 'An inactive (e.g. previously deactivated) matching row must not block re-establishing the same pair.');
    }

    /**
     * The required, non-optional test case: a real cyclic fixture, A -> B -> C -> A, must be
     * detected before the third edge is ever written (mirroring GraphUI.md §13's mandatory
     * diamond-subgraph precedent, applied here to hierarchy circular-relationship detection).
     */
    @isTest
    static void testAssertNoCircularRelationshipDetectsADeepCycle() {
        List<OI_Hierarchy_Relationship__c> existing = new List<OI_Hierarchy_Relationship__c>{
            new OI_Hierarchy_Relationship__c(Parent_Record_Id__c = 'b', Child_Record_Id__c = 'a', Is_Active__c = true),
            new OI_Hierarchy_Relationship__c(Parent_Record_Id__c = 'c', Child_Record_Id__c = 'b', Is_Active__c = true)
        };
        // Proposed: c's parent becomes a — closing the cycle a -> b -> c -> a.
        try {
            new OI_HierarchyValidationService().assertNoCircularRelationship(existing, 'a', 'c', 10);
            System.assert(false, 'Expected circular-relationship detection for a -> b -> c -> a.');
        } catch (OI_ValidationException e) {
            System.assert(e.getMessage().contains('Circular Relationship'));
        }
    }

    @isTest
    static void testAssertNoCircularRelationshipAllowsAGenuineNonCyclicChain() {
        List<OI_Hierarchy_Relationship__c> existing = new List<OI_Hierarchy_Relationship__c>{
            new OI_Hierarchy_Relationship__c(Parent_Record_Id__c = 'b', Child_Record_Id__c = 'a', Is_Active__c = true)
        };
        new OI_HierarchyValidationService().assertNoCircularRelationship(existing, 'z', 'd', 10);
        System.assert(true, 'An assignment unrelated to any existing chain must never be flagged.');
    }

    @isTest
    static void testAssertNoCircularRelationshipRespectsMaxLevelsBound() {
        // A chain of 5 hops: e5<-e4<-e3<-e2<-e1<-e0. With maxLevels=2, the walk from e1 must not reach e5 (4 hops away), so no false positive.
        List<OI_Hierarchy_Relationship__c> existing = new List<OI_Hierarchy_Relationship__c>{
            new OI_Hierarchy_Relationship__c(Parent_Record_Id__c = 'e1', Child_Record_Id__c = 'e0', Is_Active__c = true),
            new OI_Hierarchy_Relationship__c(Parent_Record_Id__c = 'e2', Child_Record_Id__c = 'e1', Is_Active__c = true),
            new OI_Hierarchy_Relationship__c(Parent_Record_Id__c = 'e3', Child_Record_Id__c = 'e2', Is_Active__c = true),
            new OI_Hierarchy_Relationship__c(Parent_Record_Id__c = 'e4', Child_Record_Id__c = 'e3', Is_Active__c = true)
        };
        new OI_HierarchyValidationService().assertNoCircularRelationship(existing, 'e1', 'e4', 2);
        System.assert(true, 'A proposed pair 4 hops apart must not be flagged when maxLevels=2 bounds the walk short of reaching it.');
    }

    @isTest
    static void testValidateEffectiveDatesRejectsAnEndDateBeforeItsStartDate() {
        try {
            new OI_HierarchyValidationService().validateEffectiveDates(Date.today(), Date.today().addDays(-1));
            System.assert(false, 'Expected rejection of an end date before the start date.');
        } catch (OI_ValidationException e) {
            System.assert(e.getMessage().contains('Effective End Date'));
        }
    }

    @isTest
    static void testValidateEffectiveDatesAllowsBlankDates() {
        new OI_HierarchyValidationService().validateEffectiveDates(null, null);
        System.assert(true, 'Effective dating is optional (FR-018) — blank dates must never be rejected.');
    }

    @isTest
    static void testAssertLevelBelongsToDefinitionAllowsABlankLevel() {
        new OI_HierarchyValidationService().assertLevelBelongsToDefinition(null, new List<OI_Hierarchy_Level__c>());
        System.assert(true, 'A relationship with no Hierarchy Level at all (FR-002 does not mandate one) must never be rejected.');
    }

    @isTest
    static void testAssertLevelBelongsToDefinitionAllowsALevelPresentInTheGivenSet() {
        OI_Hierarchy_Definition__c definition = new OI_Hierarchy_Definition__c(Name = 'Test', Object_Api_Name__c = 'Account', Status__c = 'Active', Max_Levels__c = 10);
        insert definition;
        OI_Hierarchy_Level__c level = new OI_Hierarchy_Level__c(Name = 'Level 1', Hierarchy_Definition__c = definition.Id, Object_Api_Name__c = 'Account', Level_Number__c = 1);
        insert level;

        new OI_HierarchyValidationService().assertLevelBelongsToDefinition(level.Id, new List<OI_Hierarchy_Level__c>{ level });
        System.assert(true, 'A level that is genuinely part of the caller-supplied set must never be rejected.');
    }

    @isTest
    static void testAssertLevelBelongsToDefinitionRejectsALevelFromAnotherDefinition() {
        OI_Hierarchy_Definition__c otherDefinition = new OI_Hierarchy_Definition__c(Name = 'Other', Object_Api_Name__c = 'Account', Status__c = 'Active', Max_Levels__c = 10);
        insert otherDefinition;
        OI_Hierarchy_Level__c levelFromAnotherDefinition = new OI_Hierarchy_Level__c(Name = 'Level 1', Hierarchy_Definition__c = otherDefinition.Id, Object_Api_Name__c = 'Account', Level_Number__c = 1);
        insert levelFromAnotherDefinition;

        try {
            new OI_HierarchyValidationService().assertLevelBelongsToDefinition(levelFromAnotherDefinition.Id, new List<OI_Hierarchy_Level__c>());
            System.assert(false, 'Expected rejection of a Hierarchy Level that does not belong to the given definition (Business Rule 9).');
        } catch (OI_ValidationException e) {
            System.assert(e.getMessage().contains('Invalid Parent'));
        }
    }
}
