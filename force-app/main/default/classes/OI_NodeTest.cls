/**
 * Purpose: Verifies OI_Node's immutable value-object behavior (GraphEngine.md §2).
 */
@isTest
private class OI_NodeTest {
    @isTest
    static void testConstructionCarriesAllFields() {
        OI_Node node = new OI_Node(
            'nodeKey1',
            1,
            'nodeKey1::v1',
            'Test.Type',
            'Label',
            'Secondary',
            'ParentKey',
            new Map<String, Object>{ 'a' => 1 },
            'checksum1',
            'scope1',
            'Active',
            null,
            null,
            true
        );
        System.assertEquals('nodeKey1', node.nodeKey);
        System.assertEquals(1, node.versionNumber);
        System.assertEquals('Active', node.state);
        System.assertEquals(true, node.isCurrent);
    }

    @isTest
    static void testWithLastSeenRunReturnsNewInstanceUnchangedOtherwise() {
        OI_Node original = new OI_Node('k', 1, 'k::v1', 't', 'l', 's', null, null, 'c', null, 'Active', null, null, true);
        Id fakeRunId = null;
        OI_Node touched = original.withLastSeenRun(fakeRunId);
        System.assertNotEquals(original, touched, 'withLastSeenRun must return a distinct instance, not mutate the original.');
        System.assertEquals(original.nodeKey, touched.nodeKey);
        System.assertEquals(original.checksum, touched.checksum);
    }

    @isTest
    static void testWithIsCurrentFlipsOnlyThatField() {
        OI_Node original = new OI_Node('k', 1, 'k::v1', 't', 'l', 's', null, null, 'c', null, 'Active', null, null, true);
        OI_Node superseded = original.withIsCurrent(false);
        System.assertEquals(true, original.isCurrent, 'Original instance must remain unmutated.');
        System.assertEquals(false, superseded.isCurrent);
        System.assertEquals(original.nodeKey, superseded.nodeKey);
    }

    @isTest
    static void testNullAttributesDefaultToEmptyMap() {
        OI_Node node = new OI_Node('k', 1, 'k::v1', 't', 'l', 's', null, null, 'c', null, 'Active', null, null, true);
        System.assertNotEquals(null, node.attributes);
        System.assertEquals(0, node.attributes.size());
    }
}
