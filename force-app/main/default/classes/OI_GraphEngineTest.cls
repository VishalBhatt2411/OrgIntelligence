/**
 * Purpose: Verifies OI_GraphEngine contains no logic of its own — every method call
 *          delegates to exactly the expected internal component (ADR-0013,
 *          CodingStandards.md §12).
 */
@isTest
private class OI_GraphEngineTest {
    @isTest
    static void testGetNodeDetailDelegatesToRepository() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        fake.writeVersion(OI_TestDataFactory.newNodeVersionRecord('n1', 1, 'c1'), true);
        OI_GraphRepository repo = new OI_GraphRepository(fake, fake);
        OI_GraphEngine engine = new OI_GraphEngine(new OI_GraphBuilder(repo), new OI_GraphTraversal(repo), repo, new OI_GraphSerializer(), new OI_GraphCache());
        OI_VersionRecord result = engine.getNodeDetail('n1');
        System.assertNotEquals(null, result);
        System.assertEquals('c1', result.checksum);
    }

    @isTest
    static void testGetNodeDetailReturnsNullWhenAbsent() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphRepository repo = new OI_GraphRepository(fake, fake);
        OI_GraphEngine engine = new OI_GraphEngine(new OI_GraphBuilder(repo), new OI_GraphTraversal(repo), repo, new OI_GraphSerializer(), new OI_GraphCache());
        System.assertEquals(null, engine.getNodeDetail('missing'));
    }

    @isTest
    static void testIngestDelegatesToBuilder() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphRepository repo = new OI_GraphRepository(fake, fake);
        OI_GraphEngine engine = new OI_GraphEngine(new OI_GraphBuilder(repo), new OI_GraphTraversal(repo), repo, new OI_GraphSerializer(), new OI_GraphCache());
        engine.ingest(
            new List<OI_GraphMutation>{
                OI_GraphMutation.upsertNode('n1', 'Test.Type', 'Label', null, null, new Map<String, Object>(), 'c1', null, UserInfo.getUserId())
            }
        );
        System.assertNotEquals(null, fake.versionsByKey.get('n1'), 'The facade must delegate ingest() to OI_GraphBuilder, which must actually persist via the injected Repository.');
    }

    /**
     * Sprint 10: OI_GraphTraversal.expand reads edges via OI_EdgeSelector directly (real
     * SOQL, GraphRepository.md's own Selector-only rule) rather than through the injected
     * OI_GraphRepository — the Fake-provider injection this test class otherwise relies on
     * cannot intercept that path, so this test uses real DML for the one node it expects
     * back, matching OI_GraphTraversalTest's own established convention for this class.
     */
    @isTest
    static void testGetGraphFragmentDelegatesToTraversal() {
        insert new OI_Graph_Node__c(
            Node_Key__c = 'n1',
            Node_Version_Key__c = 'n1::v1',
            Version_Number__c = 1,
            Node_Type__c = 'SalesforceMetadata.TestType',
            Label__c = 'N1',
            Secondary_Key__c = 'Sec.N1',
            Checksum__c = 'c1',
            State__c = 'Active',
            Is_Current__c = true
        );

        OI_GraphFragment fragment = new OI_GraphEngine().getGraphFragment('n1', 0, new Map<String, String>());

        System.assertEquals(1, fragment.nodes.size(), 'The facade must delegate to a genuinely working OI_GraphTraversal, not the old Sprint 7 stub.');
        System.assertEquals('n1', fragment.nodes[0].nodeKey);
    }

    @isTest
    static void testGetGraphFragmentPaginatedOverloadDelegatesToTraversal() {
        OI_GraphFragment fragment = new OI_GraphEngine().getGraphFragment('missingKey', 1, null, new Map<String, String>());
        System.assertEquals(0, fragment.nodes.size(), 'An unknown center key must return an empty fragment, not an error, from either overload.');
    }

    /**
     * getRelationshipCounts reads via OI_EdgeSelector directly (same real-SOQL precedent as
     * OI_GraphTraversal.expand — see that class's own doc comment), so this needs real
     * OI_Graph_Edge__c rows rather than the Fake-provider injection this test class otherwise
     * relies on.
     */
    @isTest
    static void testGetRelationshipCountsAggregatesOutgoingAndIncomingByType() {
        insert new List<OI_Graph_Edge__c>{
            new OI_Graph_Edge__c(Edge_Key__c = 'rc1', Edge_Version_Key__c = 'rc1::v1', Version_Number__c = 1, Edge_Type__c = 'SalesforceMetadata.HAS_FIELD', Source_Node_Key__c = 'engineObj', Target_Node_Key__c = 'engineField', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Edge__c(Edge_Key__c = 'rc2', Edge_Version_Key__c = 'rc2::v1', Version_Number__c = 1, Edge_Type__c = 'SalesforceMetadata.LOOKUP_TO', Source_Node_Key__c = 'otherField', Target_Node_Key__c = 'engineObj', State__c = 'Active', Is_Current__c = true)
        };

        OI_RelationshipCounts counts = new OI_GraphEngine().getRelationshipCounts('engineObj');

        System.assertEquals(1, counts.outgoingByType.get('SalesforceMetadata.HAS_FIELD'));
        System.assertEquals(1, counts.incomingByType.get('SalesforceMetadata.LOOKUP_TO'));
        System.assertEquals(2, counts.total());
    }

    /**
     * getMembersByEdgeType is generic — it never assumes what 'Test.MemberOf' means — but
     * its edge read is the same real-SOQL precedent as getRelationshipCounts above, so this
     * needs real OI_Graph_Edge__c rows rather than the Fake-provider injection.
     */
    @isTest
    static void testGetMembersByEdgeTypeReturnsOnlyTargetsOfTheGivenEdgeType() {
        insert new List<OI_Graph_Node__c>{
            new OI_Graph_Node__c(Node_Key__c = 'memberA', Node_Version_Key__c = 'memberA::v1', Version_Number__c = 1, Node_Type__c = 'Test.Member', Label__c = 'Member A', Secondary_Key__c = 'Sec.A', Checksum__c = 'c1', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Node__c(Node_Key__c = 'memberB', Node_Version_Key__c = 'memberB::v1', Version_Number__c = 1, Node_Type__c = 'Test.Member', Label__c = 'Member B', Secondary_Key__c = 'Sec.B', Checksum__c = 'c1', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Node__c(Node_Key__c = 'notAMember', Node_Version_Key__c = 'notAMember::v1', Version_Number__c = 1, Node_Type__c = 'Test.Other', Label__c = 'Not A Member', Secondary_Key__c = 'Sec.C', Checksum__c = 'c1', State__c = 'Active', Is_Current__c = true)
        };
        insert new List<OI_Graph_Edge__c>{
            new OI_Graph_Edge__c(Edge_Key__c = 'me1', Edge_Version_Key__c = 'me1::v1', Version_Number__c = 1, Edge_Type__c = 'Test.MemberOf', Source_Node_Key__c = 'parentX', Target_Node_Key__c = 'memberA', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Edge__c(Edge_Key__c = 'me2', Edge_Version_Key__c = 'me2::v1', Version_Number__c = 1, Edge_Type__c = 'Test.MemberOf', Source_Node_Key__c = 'parentX', Target_Node_Key__c = 'memberB', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Edge__c(Edge_Key__c = 'me3', Edge_Version_Key__c = 'me3::v1', Version_Number__c = 1, Edge_Type__c = 'Test.OtherEdge', Source_Node_Key__c = 'parentX', Target_Node_Key__c = 'notAMember', State__c = 'Active', Is_Current__c = true)
        };

        List<OI_VersionRecord> members = new OI_GraphEngine().getMembersByEdgeType('parentX', 'Test.MemberOf');

        Set<String> memberKeys = new Set<String>();
        for (OI_VersionRecord member : members) {
            memberKeys.add(member.key);
        }
        System.assertEquals(2, members.size(), 'Only edges of the requested type must contribute members.');
        System.assert(memberKeys.contains('memberA'));
        System.assert(memberKeys.contains('memberB'));
        System.assert(!memberKeys.contains('notAMember'), 'A different edge type from the same source must never leak into the result.');
    }

    @isTest
    static void testGetMembersByEdgeTypeReturnsEmptyListWhenParentHasNoMatchingEdges() {
        List<OI_VersionRecord> members = new OI_GraphEngine().getMembersByEdgeType('lonelyParent', 'Test.MemberOf');
        System.assertEquals(0, members.size());
    }

    /**
     * getImpactSubgraph reads edges via OI_EdgeSelector directly through OI_GraphTraversal,
     * the same real-SOQL precedent getGraphFragment/getRelationshipCounts/getMembersByEdgeType
     * above already establish for this Engine — real DML, not the Fake-provider injection.
     */
    @isTest
    static void testGetImpactSubgraphDelegatesToTraversal() {
        insert new List<OI_Graph_Node__c>{
            new OI_Graph_Node__c(Node_Key__c = 'depA', Node_Version_Key__c = 'depA::v1', Version_Number__c = 1, Node_Type__c = 'SalesforceMetadata.ApexClass', Label__c = 'A', Secondary_Key__c = 'A', Checksum__c = 'c1', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Node__c(Node_Key__c = 'depB', Node_Version_Key__c = 'depB::v1', Version_Number__c = 1, Node_Type__c = 'SalesforceMetadata.ApexClass', Label__c = 'B', Secondary_Key__c = 'B', Checksum__c = 'c1', State__c = 'Active', Is_Current__c = true)
        };
        insert new OI_Graph_Edge__c(
            Edge_Key__c = 'depEdge1',
            Edge_Version_Key__c = 'depEdge1::v1',
            Version_Number__c = 1,
            Edge_Type__c = 'SalesforceMetadata.REFERENCES',
            Source_Node_Key__c = 'depA',
            Target_Node_Key__c = 'depB',
            State__c = 'Active',
            Is_Current__c = true
        );

        OI_GraphFragment fragment = new OI_GraphEngine().getImpactSubgraph('depA', 'forward', null, 3, 50);

        Set<String> nodeKeys = new Set<String>();
        for (OI_NodeSummary summary : fragment.nodes) {
            nodeKeys.add(summary.nodeKey);
        }
        System.assertEquals(new Set<String>{ 'depA', 'depB' }, nodeKeys, 'The facade must delegate to a genuinely working traverseDirectional, not a stub.');
    }
}
