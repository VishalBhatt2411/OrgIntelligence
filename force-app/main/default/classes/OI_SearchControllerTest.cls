/**
 * Purpose: Verifies OI_SearchController's minimal node-lookup contract (Sprint 10 — a
 *          deliberate substitute for the unbuilt SearchEngine.md epic, see the class's own
 *          doc comment).
 */
@isTest
private class OI_SearchControllerTest {
    @isTest
    static void testSearchReturnsCurrentNodesMatchingThePrefix() {
        insert new List<OI_Graph_Node__c>{
            new OI_Graph_Node__c(Node_Key__c = 'acc1', Node_Version_Key__c = 'acc1::v1', Version_Number__c = 1, Node_Type__c = 'T', Label__c = 'Account', Secondary_Key__c = 'Account', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Node__c(Node_Key__c = 'con1', Node_Version_Key__c = 'con1::v1', Version_Number__c = 1, Node_Type__c = 'T', Label__c = 'Contact', Secondary_Key__c = 'Contact', State__c = 'Active', Is_Current__c = true)
        };

        List<OI_NodeSummaryDTO> results = OI_SearchController.search('Acc');

        System.assertEquals(1, results.size());
        System.assertEquals('acc1', results[0].nodeKey);
    }

    @isTest
    static void testSearchBelowMinimumQueryLengthReturnsEmptyNotAnError() {
        List<OI_NodeSummaryDTO> results = OI_SearchController.search('a');
        System.assertEquals(0, results.size(), 'Min_Search_Query_Length__c is 2 — a 1-character query must return empty, not error or match everything.');
    }

    @isTest
    static void testSearchWithBlankQueryReturnsEmpty() {
        System.assertEquals(0, OI_SearchController.search(null).size());
        System.assertEquals(0, OI_SearchController.search('  ').size());
    }

    @isTest
    static void testSearchWithoutPermissionThrowsAuraHandledException() {
        User unprivileged = createUnprivilegedTestUser();
        System.runAs(unprivileged) {
            try {
                OI_SearchController.search('Account');
                System.assert(false, 'Expected AuraHandledException when OI_View_Graph is not assigned.');
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
