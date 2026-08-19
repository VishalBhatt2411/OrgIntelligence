/**
 * Purpose: Verifies OI_HierarchySearchController's permission-check -> service -> DTO contract.
 */
@isTest
private class OI_HierarchySearchControllerTest {
    @isTest
    static void testSearchReturnsResolvedLabels() {
        Id definitionId = insertDefinition();
        insertLevel(definitionId, 'Account', 1);
        Account root = new Account(Name = 'Root Co');
        Account child = new Account(Name = 'Child Co');
        insert new List<Account>{ root, child };
        new OI_HierarchyRelationshipService().assignParent(definitionId, null, null, 'Account', root.Id, null, null, null, null);
        new OI_HierarchyRelationshipService().assignParent(definitionId, 'Account', root.Id, 'Account', child.Id, null, null, null, null);

        List<OI_HierarchyRelationshipDTO> results = OI_HierarchySearchController.search(definitionId, 'Child', null, false);

        System.assertEquals(1, results.size());
        System.assertEquals('Child Co', results[0].childLabel);
    }

    @isTest
    static void testSearchWithoutPermissionThrowsAuraHandledException() {
        Id definitionId = insertDefinition();
        User unprivileged = createUnprivilegedTestUser();
        System.runAs(unprivileged) {
            try {
                OI_HierarchySearchController.search(definitionId, 'Child', null, false);
                System.assert(false, 'Expected AuraHandledException when OI_View_Hierarchy is not assigned.');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    private static Id insertDefinition() {
        OI_Hierarchy_Definition__c definition = new OI_Hierarchy_Definition__c(Name = 'Test Def', Object_Api_Name__c = 'Account', Status__c = 'Active', Max_Levels__c = 10);
        insert definition;
        return definition.Id;
    }

    private static void insertLevel(Id definitionId, String objectApiName, Integer levelNumber) {
        insert new OI_Hierarchy_Level__c(Name = 'Level ' + levelNumber, Hierarchy_Definition__c = definitionId, Object_Api_Name__c = objectApiName, Level_Number__c = levelNumber);
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
