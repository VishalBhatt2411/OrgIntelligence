/**
 * Purpose: Verifies OI_HierarchyQueryController's permission-check -> service -> DTO
 *          contract for ancestors/descendants/path/membership.
 */
@isTest
private class OI_HierarchyQueryControllerTest {
    @isTest
    static void testGetAncestorsAndGetPathReturnResolvedLabels() {
        Id definitionId = insertDefinition();
        Account root = new Account(Name = 'Root Co');
        Account leaf = new Account(Name = 'Leaf Co');
        insert new List<Account>{ root, leaf };
        OI_HierarchyRelationshipController.assignParent(definitionId, null, null, 'Account', root.Id, null, null, null, null);
        OI_HierarchyRelationshipController.assignParent(definitionId, 'Account', root.Id, 'Account', leaf.Id, null, null, null, null);

        List<OI_HierarchyRelationshipDTO> ancestors = OI_HierarchyQueryController.getAncestors(definitionId, 'Account', leaf.Id);
        List<OI_HierarchyRelationshipDTO> path = OI_HierarchyQueryController.getPath(definitionId, 'Account', leaf.Id);

        System.assertEquals(1, ancestors.size());
        System.assertEquals('Root Co', ancestors[0].parentLabel);
        System.assertEquals(1, path.size());
        System.assertEquals('Root Co', path[0].parentLabel);
    }

    @isTest
    static void testGetDescendantsReturnsAnHonestHasMoreFlag() {
        Id definitionId = insertDefinition();
        Account root = new Account(Name = 'Root Co');
        Account child = new Account(Name = 'Child Co');
        insert new List<Account>{ root, child };
        OI_HierarchyRelationshipController.assignParent(definitionId, null, null, 'Account', root.Id, null, null, null, null);
        OI_HierarchyRelationshipController.assignParent(definitionId, 'Account', root.Id, 'Account', child.Id, null, null, null, null);

        OI_HierarchyDescendantsResultDTO result = OI_HierarchyQueryController.getDescendants(definitionId, 'Account', root.Id);

        System.assertEquals(1, result.descendants.size());
        System.assertEquals('Child Co', result.descendants[0].childLabel);
        System.assertEquals(false, result.hasMore);
    }

    @isTest
    static void testGetHierarchyMembershipWithoutPermissionThrowsAuraHandledException() {
        User unprivileged = createUnprivilegedTestUser();
        System.runAs(unprivileged) {
            try {
                OI_HierarchyQueryController.getHierarchyMembership('Account', '001000000000001AAA');
                System.assert(false, 'Expected AuraHandledException when OI_View_Hierarchy is not assigned.');
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
