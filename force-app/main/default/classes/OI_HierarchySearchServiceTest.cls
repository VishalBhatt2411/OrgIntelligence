@isTest
private class OI_HierarchySearchServiceTest {
    @isTest
    static void testSearchByNameReturnsOnlyRelationshipsForTheMatchedRecordWithinTheDefinition() {
        Id definitionId = insertDefinition();
        insertLevel(definitionId, 'Account', 1);
        Account root = new Account(Name = 'Root Co');
        Account child = new Account(Name = 'Child Co');
        Account unrelated = new Account(Name = 'Unrelated Co');
        insert new List<Account>{ root, child, unrelated };
        assign(definitionId, null, null, 'Account', root.Id);
        assign(definitionId, 'Account', root.Id, 'Account', child.Id);

        List<OI_Hierarchy_Relationship__c> results = new OI_HierarchySearchService().search(definitionId, 'Child', null, false);

        System.assertEquals(1, results.size());
        System.assertEquals(child.Id, (Id) results[0].Child_Record_Id__c);
    }

    @isTest
    static void testSearchByRecordIdMatchesExactly() {
        Id definitionId = insertDefinition();
        insertLevel(definitionId, 'Account', 1);
        Account root = new Account(Name = 'Root Co');
        Account child = new Account(Name = 'Child Co');
        insert new List<Account>{ root, child };
        assign(definitionId, null, null, 'Account', root.Id);
        assign(definitionId, 'Account', root.Id, 'Account', child.Id);

        List<OI_Hierarchy_Relationship__c> results = new OI_HierarchySearchService().search(definitionId, String.valueOf(child.Id), null, false);

        System.assertEquals(1, results.size());
        System.assertEquals(child.Id, (Id) results[0].Child_Record_Id__c);
    }

    @isTest
    static void testSearchBelowMinimumQueryLengthReturnsEmptyNotAnError() {
        Id definitionId = insertDefinition();
        System.assertEquals(0, new OI_HierarchySearchService().search(definitionId, 'a', null, false).size());
    }

    @isTest
    static void testSearchWithoutADefinitionReturnsEmptyNotAnError() {
        System.assertEquals(0, new OI_HierarchySearchService().search(null, 'Child', null, false).size());
    }

    @isTest
    static void testSearchWithNoNameMatchReturnsEmpty() {
        Id definitionId = insertDefinition();
        insertLevel(definitionId, 'Account', 1);
        Account root = new Account(Name = 'Root Co');
        insert root;
        assign(definitionId, null, null, 'Account', root.Id);

        System.assertEquals(0, new OI_HierarchySearchService().search(definitionId, 'Nonexistent', null, false).size());
    }

    @isTest
    static void testSearchFiltersByHierarchyLevelId() {
        Id definitionId = insertDefinition();
        Id matchingLevelId = insertLevel(definitionId, 'Account', 1);
        Id otherLevelId = insertLevel(definitionId, 'Account', 2);
        Account root = new Account(Name = 'Root Co');
        Account child = new Account(Name = 'Child Co');
        insert new List<Account>{ root, child };
        assign(definitionId, null, null, 'Account', root.Id);
        new OI_HierarchyRelationshipService().assignParent(definitionId, 'Account', root.Id, 'Account', child.Id, matchingLevelId, null, null, null);

        System.assertEquals(1, new OI_HierarchySearchService().search(definitionId, 'Child', matchingLevelId, false).size());
        System.assertEquals(0, new OI_HierarchySearchService().search(definitionId, 'Child', otherLevelId, false).size());
    }

    @isTest
    static void testSearchExcludesInactiveRelationshipsUnlessIncludeInactiveIsTrue() {
        Id definitionId = insertDefinition();
        insertLevel(definitionId, 'Account', 1);
        Account root = new Account(Name = 'Root Co');
        Account child = new Account(Name = 'Child Co');
        insert new List<Account>{ root, child };
        assign(definitionId, null, null, 'Account', root.Id);
        OI_Hierarchy_Relationship__c saved = assign(definitionId, 'Account', root.Id, 'Account', child.Id);
        new OI_HierarchyRelationshipService().deactivateRelationship(saved.Id);

        System.assertEquals(0, new OI_HierarchySearchService().search(definitionId, 'Child', null, false).size());
        System.assertEquals(1, new OI_HierarchySearchService().search(definitionId, 'Child', null, true).size());
    }

    private static Id insertDefinition() {
        OI_Hierarchy_Definition__c definition = new OI_Hierarchy_Definition__c(Name = 'Test Def', Object_Api_Name__c = 'Account', Status__c = 'Active', Max_Levels__c = 10);
        insert definition;
        return definition.Id;
    }

    private static Id insertLevel(Id definitionId, String objectApiName, Integer levelNumber) {
        OI_Hierarchy_Level__c level = new OI_Hierarchy_Level__c(
            Name = 'Level ' + levelNumber,
            Hierarchy_Definition__c = definitionId,
            Object_Api_Name__c = objectApiName,
            Level_Number__c = levelNumber
        );
        insert level;
        return level.Id;
    }

    private static OI_Hierarchy_Relationship__c assign(Id definitionId, String parentObjectApiName, String parentRecordId, String childObjectApiName, String childRecordId) {
        return new OI_HierarchyRelationshipService().assignParent(definitionId, parentObjectApiName, parentRecordId, childObjectApiName, childRecordId, null, null, null, null);
    }
}
