/**
 * Purpose: Verifies OI_GraphSerializer shapes Node/Edge results into the wire-level
 *          OI_GraphFragment correctly (GraphEngine.md §4, §8).
 */
@isTest
private class OI_GraphSerializerTest {
    @isTest
    static void testToFragmentShapesNodesAndEdgesIntoSummaries() {
        OI_Node node = new OI_Node('n1', 1, 'n1::v1', 'Test.Type', 'Label', 'sk', null, null, 'c1', null, 'Active', null, null, true);
        OI_Edge edge = new OI_Edge('e1', 1, 'e1::v1', 'Test.EdgeType', 'n1', 'n2', null, null, 'Active', null, null, null, true);
        OI_GraphFragment fragment = new OI_GraphSerializer().toFragment('n1', new List<OI_Node>{ node }, new List<OI_Edge>{ edge }, new List<String>{ 'n2' }, true, 'cursor1');
        System.assertEquals('n1', fragment.centerNodeKey);
        System.assertEquals(1, fragment.nodes.size());
        System.assertEquals('Label', fragment.nodes[0].label);
        System.assertEquals(1, fragment.edges.size());
        System.assertEquals(true, fragment.hasMore);
        System.assertEquals('cursor1', fragment.nextCursor);
    }

    @isTest
    static void testToFragmentHandlesEmptyLists() {
        OI_GraphFragment fragment = new OI_GraphSerializer().toFragment('n1', new List<OI_Node>(), new List<OI_Edge>(), new List<String>(), false, null);
        System.assertEquals(0, fragment.nodes.size());
        System.assertEquals(0, fragment.edges.size());
    }
}
