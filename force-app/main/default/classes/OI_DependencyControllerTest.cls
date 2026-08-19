/**
 * Purpose: Verifies OI_DependencyController's thin permission-check -> call -> DTO-map
 *          contract, mirroring OI_GraphControllerTest's own established pattern.
 */
@isTest
private class OI_DependencyControllerTest {
    @isTest
    static void testGetImpactReturnsAffectedComponentsAndSubgraphShapedLikeAGraphFragment() {
        insertClassNode('ctrlA', 'Ctrl A');
        insertClassNode('ctrlB', 'Ctrl B');
        insertReferencesEdge('ctrlA', 'ctrlB');

        OI_ImpactResultDTO result = OI_DependencyController.getImpact('ctrlA', 'forward', 3);

        System.assertEquals('ctrlA', result.rootNodeKey);
        System.assertEquals('forward', result.direction);
        System.assertEquals(1, result.affectedComponents.size());
        System.assertEquals('ctrlB', result.affectedComponents[0].nodeKey);
        System.assertNotEquals(null, result.subgraph, 'subgraph must be present, shaped like OI_GraphFragmentDTO, so the client can merge it via the existing applyExpand path unchanged.');
        System.assertEquals(2, result.subgraph.nodes.size());
        System.assertNotEquals(null, result.coverageCaveat);
    }

    @isTest
    static void testGetImpactForAnUnknownNodeKeyReturnsAnEmptyAffectedComponentsListNotAnError() {
        OI_ImpactResultDTO result = OI_DependencyController.getImpact('doesNotExist', 'forward', 3);
        System.assertEquals(0, result.affectedComponents.size());
    }

    @isTest
    static void testGetImpactWithoutPermissionThrowsAuraHandledException() {
        User unprivileged = createUnprivilegedTestUser();
        System.runAs(unprivileged) {
            try {
                OI_DependencyController.getImpact('anyKey', 'forward', 3);
                System.assert(false, 'Expected AuraHandledException when OI_View_Graph is not assigned.');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    private static void insertClassNode(String nodeKey, String label) {
        insert new OI_Graph_Node__c(
            Node_Key__c = nodeKey,
            Node_Version_Key__c = nodeKey + '::v1',
            Version_Number__c = 1,
            Node_Type__c = 'SalesforceMetadata.ApexClass',
            Label__c = label,
            Secondary_Key__c = label,
            Checksum__c = nodeKey + '-checksum',
            State__c = 'Active',
            Is_Current__c = true
        );
    }

    private static void insertReferencesEdge(String fromKey, String toKey) {
        insert new OI_Graph_Edge__c(
            Edge_Key__c = fromKey + '->' + toKey,
            Edge_Version_Key__c = fromKey + '->' + toKey + '::v1',
            Version_Number__c = 1,
            Edge_Type__c = 'SalesforceMetadata.REFERENCES',
            Source_Node_Key__c = fromKey,
            Target_Node_Key__c = toKey,
            State__c = 'Active',
            Is_Current__c = true
        );
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
