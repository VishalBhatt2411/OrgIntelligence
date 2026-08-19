/**
 * Purpose: Verifies OI_GraphMutation's named factories produce the correct shape per
 *          mutation type (GraphEngine.md §7).
 */
@isTest
private class OI_GraphMutationTest {
    @isTest
    static void testUpsertNodeFactory() {
        OI_GraphMutation mutation = OI_GraphMutation.upsertNode('nk', 'Test.Type', 'Label', 'sk', 'pk', new Map<String, Object>{ 'x' => 1 }, 'checksum', 'scope', UserInfo.getUserId());
        System.assertEquals(OI_GraphMutation.MutationType.UPSERT_NODE, mutation.mutationType);
        System.assertEquals('nk', mutation.nodeKey);
        System.assertEquals(null, mutation.edgeKey);
        System.assertEquals('pk', mutation.parentKey);
        System.assertEquals(UserInfo.getUserId(), mutation.scanRunId);
    }

    @isTest
    static void testRetireNodeFactory() {
        OI_GraphMutation mutation = OI_GraphMutation.retireNode('nk', UserInfo.getUserId());
        System.assertEquals(OI_GraphMutation.MutationType.RETIRE_NODE, mutation.mutationType);
        System.assertEquals('nk', mutation.nodeKey);
        System.assertEquals(0, mutation.attributes.size());
    }

    @isTest
    static void testUpsertEdgeFactory() {
        OI_GraphMutation mutation = OI_GraphMutation.upsertEdge('ek', 'Test.EdgeType', 'src', 'tgt', new Map<String, Object>(), 'checksum', 2.0, 'scope', UserInfo.getUserId());
        System.assertEquals(OI_GraphMutation.MutationType.UPSERT_EDGE, mutation.mutationType);
        System.assertEquals('src', mutation.sourceNodeKey);
        System.assertEquals('tgt', mutation.targetNodeKey);
        System.assertEquals(2.0, mutation.weight);
    }

    @isTest
    static void testRetireEdgeFactory() {
        OI_GraphMutation mutation = OI_GraphMutation.retireEdge('ek', UserInfo.getUserId());
        System.assertEquals(OI_GraphMutation.MutationType.RETIRE_EDGE, mutation.mutationType);
        System.assertEquals('ek', mutation.edgeKey);
    }
}
