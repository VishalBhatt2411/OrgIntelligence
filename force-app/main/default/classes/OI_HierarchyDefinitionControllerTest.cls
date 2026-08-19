/**
 * Purpose: Verifies OI_HierarchyDefinitionController's permission-check -> service -> DTO
 *          contract, mirroring OI_GraphControllerTest's established pattern.
 */
@isTest
private class OI_HierarchyDefinitionControllerTest {
    @isTest
    static void testSaveDefinitionThenGetDefinitionsReturnsIt() {
        OI_HierarchyDefinitionDTO saved = OI_HierarchyDefinitionController.saveDefinition(null, 'Corporate', 'desc', 'Account', 'Active', 10, 'Reports To', false, true);
        System.assertNotEquals(null, saved.definitionId);

        List<OI_HierarchyDefinitionDTO> all = OI_HierarchyDefinitionController.getDefinitions();
        System.assertEquals(1, all.size());
        System.assertEquals('Corporate', all[0].name);
    }

    @isTest
    static void testSaveLevelThenGetLevelsReturnsIt() {
        OI_HierarchyDefinitionDTO definition = OI_HierarchyDefinitionController.saveDefinition(null, 'Corporate', null, 'Account', 'Active', 10, null, false, true);

        OI_HierarchyDefinitionController.saveLevel(null, definition.definitionId, 'Region', 1, 'Account', true, null);
        List<OI_HierarchyLevelDTO> levels = OI_HierarchyDefinitionController.getLevels(definition.definitionId);

        System.assertEquals(1, levels.size());
        System.assertEquals('Region', levels[0].levelName);
    }

    @isTest
    static void testSaveDefinitionWithoutManagePermissionThrowsAuraHandledException() {
        User unprivileged = createUnprivilegedTestUser();
        System.runAs(unprivileged) {
            try {
                OI_HierarchyDefinitionController.saveDefinition(null, 'Corporate', null, 'Account', 'Active', 10, null, false, true);
                System.assert(false, 'Expected AuraHandledException when OI_Manage_Hierarchy is not assigned.');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    @isTest
    static void testGetDefinitionsWithoutViewPermissionThrowsAuraHandledException() {
        User unprivileged = createUnprivilegedTestUser();
        System.runAs(unprivileged) {
            try {
                OI_HierarchyDefinitionController.getDefinitions();
                System.assert(false, 'Expected AuraHandledException when OI_View_Hierarchy is not assigned.');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    private static User createUnprivilegedTestUser() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniqueSuffix = String.valueOf(Crypto.getRandomInteger()).right(8);
        User u = new User(
            FirstName = 'OI Test',
            LastName = 'Unprivileged' + uniqueSuffix,
            Email = 'oi.test.' + uniqueSuffix + '@example.invalid',
            Username = 'oi.test.' + uniqueSuffix + '@example.invalid',
            Alias = 'oitst' + uniqueSuffix.left(3),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = standardProfile.Id
        );
        insert u;
        return u;
    }
}
