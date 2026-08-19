/**
 * Purpose: Verifies OI_GraphTraversal's real BFS expand (Sprint 10, completing the Sprint
 *          7 seam). Uses real DML against OI_Graph_Node__c/OI_Graph_Edge__c (matching
 *          OI_NodeSelectorTest/OI_EdgeSelectorTest's own convention) rather than the
 *          Fake-storage-provider pattern, since OI_GraphTraversal reads edges directly via
 *          OI_EdgeSelector — a SOQL path the injected OI_GraphRepository fake cannot
 *          intercept.
 */
@isTest
private class OI_GraphTraversalTest {
    @isTest
    static void testExpandZeroHopReturnsOnlyTheCenterNodeWithFrontierTrue() {
        insertNode('centerKey', 'Center Label', 'Center.Secondary');

        OI_GraphFragment fragment = new OI_GraphTraversal().expand('centerKey', 0, new Map<String, String>());

        System.assertEquals(1, fragment.nodes.size());
        System.assertEquals('centerKey', fragment.nodes[0].nodeKey);
        System.assertEquals(0, fragment.edges.size());
        System.assertEquals(1, fragment.frontier.size());
        System.assertEquals(false, fragment.hasMore);
    }

    @isTest
    static void testExpandOneHopReturnsBothOutgoingAndIncomingNeighbors() {
        insertNode('a', 'A', 'Sec.A');
        insertNode('b', 'B', 'Sec.B');
        insertNode('c', 'C', 'Sec.C');
        insertEdge('e1', 'a', 'b');
        insertEdge('e2', 'c', 'a');

        OI_GraphFragment fragment = new OI_GraphTraversal().expand('a', 1, new Map<String, String>());

        Set<String> nodeKeys = new Set<String>();
        for (OI_NodeSummary summary : fragment.nodes) {
            nodeKeys.add(summary.nodeKey);
        }
        System.assertEquals(new Set<String>{ 'a', 'b', 'c' }, nodeKeys, 'Expand must return the center plus both its outgoing and incoming direct neighbors.');
        System.assertEquals(2, fragment.edges.size());
        System.assertEquals(new Set<String>{ 'b', 'c' }, new Set<String>(fragment.frontier), 'Every freshly-revealed neighbor is frontier — neither has itself been expanded yet.');
        System.assertEquals(false, fragment.hasMore);
    }

    @isTest
    static void testExpandDeduplicatesANodeReachableViaTwoEdgesFromTheSameCenter() {
        insertNode('a', 'A', 'Sec.A');
        insertNode('b', 'B', 'Sec.B');
        insertEdge('e1', 'a', 'b');
        insertEdge('e2', 'b', 'a');

        OI_GraphFragment fragment = new OI_GraphTraversal().expand('a', 1, new Map<String, String>());

        Integer bCount = 0;
        for (OI_NodeSummary summary : fragment.nodes) {
            if (summary.nodeKey == 'b') {
                bCount++;
            }
        }
        System.assertEquals(1, bCount, 'A node reachable via two distinct edges to the same center must appear exactly once, never duplicated.');
        System.assertEquals(2, fragment.edges.size(), 'Both distinct edges must still be reported, even though the node they connect appears once.');
    }

    @isTest
    static void testExpandOfANodeWithNoEdgesReturnsOnlyTheCenter() {
        insertNode('lonely', 'Lonely', 'Sec.Lonely');

        OI_GraphFragment fragment = new OI_GraphTraversal().expand('lonely', 1, new Map<String, String>());

        System.assertEquals(1, fragment.nodes.size());
        System.assertEquals(0, fragment.edges.size());
        System.assertEquals(0, fragment.frontier.size());
        System.assertEquals(false, fragment.hasMore);
    }

    @isTest
    static void testExpandOfAnUnknownNodeKeyReturnsAnEmptyFragmentNotAnError() {
        OI_GraphFragment fragment = new OI_GraphTraversal().expand('doesNotExist', 1, new Map<String, String>());
        System.assertEquals(0, fragment.nodes.size());
    }

    @isTest
    static void testExpandOmitsANeighborWhoseChecksumMatchesKnownChecksumsButStillReturnsItsEdge() {
        insertNode('a', 'A', 'Sec.A');
        OI_Graph_Node__c bRow = insertNode('b', 'B', 'Sec.B');
        insertEdge('e1', 'a', 'b');

        Map<String, String> known = new Map<String, String>{ 'b' => bRow.Checksum__c };
        OI_GraphFragment fragment = new OI_GraphTraversal().expand('a', 1, known);

        Set<String> nodeKeys = new Set<String>();
        for (OI_NodeSummary summary : fragment.nodes) {
            nodeKeys.add(summary.nodeKey);
        }
        System.assertEquals(true, nodeKeys.contains('a'));
        System.assertEquals(false, nodeKeys.contains('b'), 'A neighbor whose current checksum matches what the client already holds must be omitted (GraphEngine.md §9).');
        System.assertEquals(1, fragment.edges.size(), 'The edge to the checksum-matched neighbor must still be reported — the client already has the node to attach it to.');
    }

    @isTest
    static void testExpandResumesFromAnExplicitPageCursor() {
        insertNode('a', 'A', 'Sec.A');
        insertNode('b1', 'B1', 'Sec.B1');
        insertNode('b2', 'B2', 'Sec.B2');
        insertNode('b3', 'B3', 'Sec.B3');
        insertEdge('e1', 'a', 'b1');
        insertEdge('e2', 'a', 'b2');
        insertEdge('e3', 'a', 'b3');

        OI_GraphFragment fullPage = new OI_GraphTraversal().expand('a', 1, null, new Map<String, String>());
        System.assertEquals(3, fullPage.frontier.size(), 'Precondition: all three neighbors fit in one page under the 500 ceiling.');

        List<String> sortedNeighbors = new List<String>(fullPage.frontier);
        sortedNeighbors.sort();
        OI_GraphFragment resumed = new OI_GraphTraversal().expand('a', 1, sortedNeighbors[0], new Map<String, String>());

        Set<String> resumedKeys = new Set<String>();
        for (String key : resumed.frontier) {
            resumedKeys.add(key);
        }
        System.assertEquals(false, resumedKeys.contains(sortedNeighbors[0]), 'A cursor of the first key must exclude that key from the resumed page — cursor semantics are strictly-greater-than.');
        System.assertEquals(2, resumedKeys.size());
    }

    @isTest
    static void testExpandOmitsAnEdgeWhoseTargetHasNoCurrentNodeRow() {
        insertNode('a', 'A', 'Sec.A');
        insertEdge('e1', 'a', 'ghost');

        OI_GraphFragment fragment = new OI_GraphTraversal().expand('a', 1, new Map<String, String>());

        Set<String> nodeKeys = new Set<String>();
        for (OI_NodeSummary summary : fragment.nodes) {
            nodeKeys.add(summary.nodeKey);
        }
        System.assertEquals(new Set<String>{ 'a' }, nodeKeys, 'A revealed key with no current version row must never appear as a node.');
        System.assertEquals(0, fragment.edges.size(), 'An edge whose target resolves to no current node must never be returned — the client would have no node to attach it to.');
    }

    @isTest
    static void testTraverseDirectionalForwardFollowsOnlyOutgoingEdges() {
        insertNode('a', 'A', 'Sec.A');
        insertNode('b', 'B', 'Sec.B');
        insertNode('c', 'C', 'Sec.C');
        insertEdge('e1', 'a', 'b');
        insertEdge('e2', 'c', 'a');

        OI_GraphFragment fragment = new OI_GraphTraversal().traverseDirectional('a', 'forward', null, 1, 50);

        System.assertEquals(new Set<String>{ 'a', 'b' }, nodeKeySet(fragment), 'Forward traversal must follow only outgoing edges from a, reaching b but never c.');
    }

    @isTest
    static void testTraverseDirectionalReverseFollowsOnlyIncomingEdges() {
        insertNode('a', 'A', 'Sec.A');
        insertNode('b', 'B', 'Sec.B');
        insertNode('c', 'C', 'Sec.C');
        insertEdge('e1', 'a', 'b');
        insertEdge('e2', 'c', 'a');

        OI_GraphFragment fragment = new OI_GraphTraversal().traverseDirectional('a', 'reverse', null, 1, 50);

        System.assertEquals(new Set<String>{ 'a', 'c' }, nodeKeySet(fragment), 'Reverse traversal must follow only incoming edges to a, reaching c but never b.');
    }

    @isTest
    static void testTraverseDirectionalFiltersByEdgeType() {
        insertNode('a', 'A', 'Sec.A');
        insertNode('b', 'B', 'Sec.B');
        insertNode('c', 'C', 'Sec.C');
        insertTypedEdge('e1', 'a', 'b', 'SalesforceMetadata.REFERENCES');
        insertTypedEdge('e2', 'a', 'c', 'SalesforceMetadata.HAS_FIELD');

        OI_GraphFragment fragment = new OI_GraphTraversal().traverseDirectional('a', 'forward', new Set<String>{ 'SalesforceMetadata.REFERENCES' }, 1, 50);

        System.assertEquals(new Set<String>{ 'a', 'b' }, nodeKeySet(fragment), 'Only edges matching the allowed edgeTypeKeys must be traversed.');
    }

    @isTest
    static void testTraverseDirectionalRespectsMaxDepth() {
        insertNode('a', 'A', 'Sec.A');
        insertNode('b', 'B', 'Sec.B');
        insertNode('c', 'C', 'Sec.C');
        insertEdge('e1', 'a', 'b');
        insertEdge('e2', 'b', 'c');

        OI_GraphFragment fragment = new OI_GraphTraversal().traverseDirectional('a', 'forward', null, 1, 50);

        System.assertEquals(new Set<String>{ 'a', 'b' }, nodeKeySet(fragment), 'A maxDepth of 1 must not reach c, two hops away.');
    }

    @isTest
    static void testTraverseDirectionalMarksHasMoreTrueWhenTheNodeCountCeilingTruncatesExploration() {
        insertNode('a', 'A', 'Sec.A');
        insertNode('b', 'B', 'Sec.B');
        insertNode('c', 'C', 'Sec.C');
        insertEdge('e1', 'a', 'b');
        insertEdge('e2', 'a', 'c');

        OI_GraphFragment fragment = new OI_GraphTraversal().traverseDirectional('a', 'forward', null, 1, 1);

        System.assertEquals(true, fragment.hasMore, 'Hitting the node-count ceiling mid-ring must be reported, never silently dropped.');
    }

    @isTest
    static void testTraverseDirectionalOfAnUnknownNodeKeyReturnsAnEmptyFragmentNotAnError() {
        OI_GraphFragment fragment = new OI_GraphTraversal().traverseDirectional('doesNotExist', 'forward', null, 3, 50);
        System.assertEquals(0, fragment.nodes.size());
    }

    private static Set<String> nodeKeySet(OI_GraphFragment fragment) {
        Set<String> keys = new Set<String>();
        for (OI_NodeSummary summary : fragment.nodes) {
            keys.add(summary.nodeKey);
        }
        return keys;
    }

    private static void insertTypedEdge(String edgeKey, String sourceKey, String targetKey, String edgeType) {
        insert new OI_Graph_Edge__c(
            Edge_Key__c = edgeKey,
            Edge_Version_Key__c = edgeKey + '::v1',
            Version_Number__c = 1,
            Edge_Type__c = edgeType,
            Source_Node_Key__c = sourceKey,
            Target_Node_Key__c = targetKey,
            State__c = 'Active',
            Is_Current__c = true
        );
    }

    private static OI_Graph_Node__c insertNode(String nodeKey, String label, String secondaryKey) {
        OI_Graph_Node__c node = new OI_Graph_Node__c(
            Node_Key__c = nodeKey,
            Node_Version_Key__c = nodeKey + '::v1',
            Version_Number__c = 1,
            Node_Type__c = 'SalesforceMetadata.TestType',
            Label__c = label,
            Secondary_Key__c = secondaryKey,
            Checksum__c = nodeKey + '-checksum',
            State__c = 'Active',
            Is_Current__c = true
        );
        insert node;
        return node;
    }

    private static void insertEdge(String edgeKey, String sourceKey, String targetKey) {
        insert new OI_Graph_Edge__c(
            Edge_Key__c = edgeKey,
            Edge_Version_Key__c = edgeKey + '::v1',
            Version_Number__c = 1,
            Edge_Type__c = 'SalesforceMetadata.TestRelationship',
            Source_Node_Key__c = sourceKey,
            Target_Node_Key__c = targetKey,
            State__c = 'Active',
            Is_Current__c = true
        );
    }
}
