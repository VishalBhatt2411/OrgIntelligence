/**
 * Purpose: Verifies OI_Edge's immutable value-object behavior (GraphEngine.md §3).
 */
@isTest
private class OI_EdgeTest {
    @isTest
    static void testConstructionCarriesAllFields() {
        OI_Edge edge = new OI_Edge('edgeKey1', 1, 'edgeKey1::v1', 'Test.EdgeType', 'src', 'tgt', new Map<String, Object>(), 1.5, 'Active', 'scope1', null, null, true);
        System.assertEquals('edgeKey1', edge.edgeKey);
        System.assertEquals('src', edge.sourceNodeKey);
        System.assertEquals('tgt', edge.targetNodeKey);
        System.assertEquals(1.5, edge.weight);
    }

    @isTest
    static void testWithIsCurrentReturnsNewInstance() {
        OI_Edge original = new OI_Edge('k', 1, 'k::v1', 't', 's', 'tg', null, null, 'Active', null, null, null, true);
        OI_Edge superseded = original.withIsCurrent(false);
        System.assertEquals(true, original.isCurrent);
        System.assertEquals(false, superseded.isCurrent);
    }

    @isTest
    static void testNullAttributesDefaultToEmptyMap() {
        OI_Edge edge = new OI_Edge('k', 1, 'k::v1', 't', 's', 'tg', null, null, 'Active', null, null, null, true);
        System.assertNotEquals(null, edge.attributes);
        System.assertEquals(0, edge.attributes.size());
    }
}
