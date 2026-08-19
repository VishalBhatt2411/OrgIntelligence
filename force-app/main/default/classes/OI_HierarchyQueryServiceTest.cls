/**
 * Purpose: Verifies OI_HierarchyQueryService's ancestor/descendant/path/membership traversal.
 */
@isTest
private class OI_HierarchyQueryServiceTest {
    @isTest
    static void testGetAncestorsWalksUpToTheRootNearestFirst() {
        Id definitionId = insertDefinition(10);
        Account root = new Account(Name = 'Root');
        Account mid = new Account(Name = 'Mid');
        Account leaf = new Account(Name = 'Leaf');
        insert new List<Account>{ root, mid, leaf };
        OI_HierarchyRelationshipService svc = new OI_HierarchyRelationshipService();
        svc.assignParent(definitionId, null, null, 'Account', root.Id, null, null, null, null);
        svc.assignParent(definitionId, 'Account', root.Id, 'Account', mid.Id, null, null, null, null);
        svc.assignParent(definitionId, 'Account', mid.Id, 'Account', leaf.Id, null, null, null, null);

        List<OI_Hierarchy_Relationship__c> ancestors = new OI_HierarchyQueryService().getAncestors(definitionId, 'Account', leaf.Id);

        System.assertEquals(2, ancestors.size(), 'leaf has two ancestors: mid and root.');
        System.assertEquals(mid.Id, ancestors[0].Parent_Record_Id__c, 'Nearest ancestor (mid) must come first.');
        System.assertEquals(root.Id, ancestors[1].Parent_Record_Id__c);
    }

    @isTest
    static void testGetPathReturnsRootFirst() {
        Id definitionId = insertDefinition(10);
        Account root = new Account(Name = 'Root');
        Account leaf = new Account(Name = 'Leaf');
        insert new List<Account>{ root, leaf };
        OI_HierarchyRelationshipService svc = new OI_HierarchyRelationshipService();
        svc.assignParent(definitionId, null, null, 'Account', root.Id, null, null, null, null);
        svc.assignParent(definitionId, 'Account', root.Id, 'Account', leaf.Id, null, null, null, null);

        List<OI_Hierarchy_Relationship__c> path = new OI_HierarchyQueryService().getPath(definitionId, 'Account', leaf.Id);

        System.assertEquals(1, path.size());
        System.assertEquals(root.Id, path[0].Parent_Record_Id__c, 'getPath must be root-first — the reverse order of getAncestors.');
    }

    @isTest
    static void testGetDescendantsFindsMultipleGenerationsViaBulkRingTraversal() {
        Id definitionId = insertDefinition(10);
        Account root = new Account(Name = 'Root');
        Account child1 = new Account(Name = 'Child 1');
        Account child2 = new Account(Name = 'Child 2');
        Account grandchild = new Account(Name = 'Grandchild');
        insert new List<Account>{ root, child1, child2, grandchild };
        OI_HierarchyRelationshipService svc = new OI_HierarchyRelationshipService();
        svc.assignParent(definitionId, null, null, 'Account', root.Id, null, null, null, null);
        svc.assignParent(definitionId, 'Account', root.Id, 'Account', child1.Id, null, null, null, null);
        svc.assignParent(definitionId, 'Account', root.Id, 'Account', child2.Id, null, null, null, null);
        svc.assignParent(definitionId, 'Account', child1.Id, 'Account', grandchild.Id, null, null, null, null);

        OI_HierarchyDescendantsResult result = new OI_HierarchyQueryService().getDescendants(definitionId, root.Id);

        Set<String> descendantChildIds = new Set<String>();
        for (OI_Hierarchy_Relationship__c link : result.descendants) {
            descendantChildIds.add(link.Child_Record_Id__c);
        }
        System.assertEquals(new Set<String>{ child1.Id, child2.Id, grandchild.Id }, descendantChildIds);
        System.assertEquals(false, result.hasMore);
    }

    @isTest
    static void testGetDescendantsOfALeafReturnsEmpty() {
        Id definitionId = insertDefinition(10);
        Account leaf = new Account(Name = 'Leaf');
        insert leaf;
        new OI_HierarchyRelationshipService().assignParent(definitionId, null, null, 'Account', leaf.Id, null, null, null, null);

        OI_HierarchyDescendantsResult result = new OI_HierarchyQueryService().getDescendants(definitionId, leaf.Id);

        System.assertEquals(0, result.descendants.size());
        System.assertEquals(false, result.hasMore);
    }

    @isTest
    static void testGetHierarchyMembershipFindsARecordAcrossMultipleDefinitions() {
        Id corporateDefId = insertDefinition(10);
        Id territoryDefId = insertDefinition(10);
        Account root1 = new Account(Name = 'Corp Root');
        Account root2 = new Account(Name = 'Territory Root');
        Account shared = new Account(Name = 'Shared Account');
        insert new List<Account>{ root1, root2, shared };
        OI_HierarchyRelationshipService svc = new OI_HierarchyRelationshipService();
        svc.assignParent(corporateDefId, null, null, 'Account', root1.Id, null, null, null, null);
        svc.assignParent(corporateDefId, 'Account', root1.Id, 'Account', shared.Id, null, null, null, null);
        svc.assignParent(territoryDefId, null, null, 'Account', root2.Id, null, null, null, null);
        svc.assignParent(territoryDefId, 'Account', root2.Id, 'Account', shared.Id, null, null, null, null);

        List<OI_Hierarchy_Relationship__c> memberships = new OI_HierarchyQueryService().getHierarchyMembership('Account', shared.Id);

        Set<Id> definitionIds = new Set<Id>();
        for (OI_Hierarchy_Relationship__c link : memberships) {
            definitionIds.add(link.Hierarchy_Definition__c);
        }
        System.assertEquals(new Set<Id>{ corporateDefId, territoryDefId }, definitionIds, 'The same Account participating in two independent hierarchy definitions simultaneously must both be found — the FRD\'s core capability a native lookup field cannot provide.');
    }

    private static Id insertDefinition(Integer maxLevels) {
        OI_Hierarchy_Definition__c definition = new OI_Hierarchy_Definition__c(
            Name = 'Test Def ' + Crypto.getRandomInteger(),
            Object_Api_Name__c = 'Account',
            Status__c = 'Active',
            Max_Levels__c = maxLevels
        );
        insert definition;
        return definition.Id;
    }
}
