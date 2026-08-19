/**
 * Purpose: Verifies OI_HierarchyDefinitionService's Definition/Level CRUD (FR-001/002).
 */
@isTest
private class OI_HierarchyDefinitionServiceTest {
    @isTest
    static void testSaveDefinitionValidatesTheConfiguredObjectApiName() {
        OI_Hierarchy_Definition__c definition = new OI_Hierarchy_Definition__c(Name = 'Test', Object_Api_Name__c = 'Account', Status__c = 'Active', Max_Levels__c = 10);
        OI_Hierarchy_Definition__c saved = new OI_HierarchyDefinitionService().saveDefinition(definition);
        System.assertNotEquals(null, saved.Id);
    }

    @isTest
    static void testSaveDefinitionRejectsAnUnknownObjectApiName() {
        OI_Hierarchy_Definition__c definition = new OI_Hierarchy_Definition__c(Name = 'Test', Object_Api_Name__c = 'NotARealObject__x', Status__c = 'Active', Max_Levels__c = 10);
        try {
            new OI_HierarchyDefinitionService().saveDefinition(definition);
            System.assert(false, 'Expected rejection of an unknown object API name.');
        } catch (OI_ValidationException e) {
            System.assert(e.getMessage().contains('Unknown object'));
        }
    }

    @isTest
    static void testSaveLevelRequiresADefinition() {
        OI_Hierarchy_Level__c level = new OI_Hierarchy_Level__c(Name = 'Level 1', Level_Number__c = 1, Object_Api_Name__c = 'Account');
        try {
            new OI_HierarchyDefinitionService().saveLevel(level);
            System.assert(false, 'Expected rejection of a level with no owning definition.');
        } catch (OI_ValidationException e) {
            System.assert(e.getMessage().contains('hierarchy definition'));
        }
    }

    @isTest
    static void testGetLevelsReturnsOnlyLevelsForTheRequestedDefinitionOrderedByLevelNumber() {
        OI_Hierarchy_Definition__c definition = new OI_Hierarchy_Definition__c(Name = 'Test', Object_Api_Name__c = 'Account', Status__c = 'Active', Max_Levels__c = 10);
        insert definition;
        insert new List<OI_Hierarchy_Level__c>{
            new OI_Hierarchy_Level__c(Hierarchy_Definition__c = definition.Id, Name = 'Level 2', Level_Number__c = 2, Object_Api_Name__c = 'Account'),
            new OI_Hierarchy_Level__c(Hierarchy_Definition__c = definition.Id, Name = 'Level 1', Level_Number__c = 1, Object_Api_Name__c = 'Account')
        };

        List<OI_Hierarchy_Level__c> levels = new OI_HierarchyDefinitionService().getLevels(definition.Id);

        System.assertEquals(2, levels.size());
        System.assertEquals(1, levels[0].Level_Number__c, 'Levels must be ordered by Level_Number__c ascending.');
    }

    @isTest
    static void testGetDefinitionThrowsForAnUnknownId() {
        try {
            new OI_HierarchyDefinitionService().getDefinition(null);
            System.assert(false, 'Expected rejection of an unknown definition Id.');
        } catch (OI_ValidationException e) {
            System.assert(e.getMessage().contains('Unknown hierarchy definition'));
        }
    }
}
