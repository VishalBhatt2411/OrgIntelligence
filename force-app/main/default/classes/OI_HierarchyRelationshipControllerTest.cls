/**
 * Purpose: Verifies OI_HierarchyRelationshipController's permission-check -> service -> DTO
 *          contract, including resolved parent/child labels (ADR-0022).
 */
@isTest
private class OI_HierarchyRelationshipControllerTest {
    @isTest
    static void testAssignParentReturnsADTOWithResolvedLabels() {
        Id definitionId = insertDefinition();
        Account parent = new Account(Name = 'Parent Co');
        Account child = new Account(Name = 'Child Co');
        insert new List<Account>{ parent, child };

        OI_HierarchyRelationshipDTO dto = OI_HierarchyRelationshipController.assignParent(definitionId, 'Account', parent.Id, 'Account', child.Id, null, 'Reports To', null, null);

        System.assertEquals('Parent Co', dto.parentLabel);
        System.assertEquals('Child Co', dto.childLabel);
        System.assertEquals(true, dto.isActive);
    }

    @isTest
    static void testDeactivateRelationshipThenGetRelationshipsShowsItInactive() {
        Id definitionId = insertDefinition();
        Account child = new Account(Name = 'Child Co');
        insert child;
        OI_HierarchyRelationshipDTO created = OI_HierarchyRelationshipController.assignParent(definitionId, null, null, 'Account', child.Id, null, null, null, null);

        OI_HierarchyRelationshipController.deactivateRelationship(created.relationshipId);

        List<OI_HierarchyRelationshipDTO> all = OI_HierarchyRelationshipController.getRelationships(definitionId);
        System.assertEquals(1, all.size());
        System.assertEquals(false, all[0].isActive);
    }

    @isTest
    static void testGetHistoryReturnsAResolvedChangedByName() {
        Id definitionId = insertDefinition();
        Account child = new Account(Name = 'Child Co');
        insert child;
        OI_HierarchyRelationshipController.assignParent(definitionId, null, null, 'Account', child.Id, null, null, null, null);

        List<OI_HierarchyHistoryDTO> history = OI_HierarchyRelationshipController.getHistory(definitionId, 'Account', child.Id);

        System.assertEquals(1, history.size());
        System.assertEquals('Created', history[0].changeType);
        System.assertNotEquals(null, history[0].changedByName);
    }

    @isTest
    static void testAssignParentWithoutAnyRelevantPermissionThrowsAuraHandledException() {
        Id definitionId = insertDefinition();
        Account child = new Account(Name = 'Child Co');
        insert child;
        User unprivileged = createUnprivilegedTestUser();
        System.runAs(unprivileged) {
            try {
                OI_HierarchyRelationshipController.assignParent(definitionId, null, null, 'Account', child.Id, null, null, null, null);
                System.assert(false, 'Expected AuraHandledException when neither OI_Create_Hierarchy nor OI_Edit_Hierarchy is assigned.');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    private static Id insertDefinition() {
        OI_Hierarchy_Definition__c definition = new OI_Hierarchy_Definition__c(Name = 'Test', Object_Api_Name__c = 'Account', Status__c = 'Active', Max_Levels__c = 10);
        insert definition;
        return definition.Id;
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
