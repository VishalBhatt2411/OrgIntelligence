/**
 * Purpose: Verifies OI_GraphCache's key-building determinism and get/put/evict
 *          delegation to its injected cache provider (GraphEngine.md §14).
 */
@isTest
private class OI_GraphCacheTest {
    @isTest
    static void testPutAndGetFragmentRoundTrips() {
        OI_GraphCache cache = new OI_GraphCache(new OI_FakeKeyValueCacheProvider());
        OI_GraphFragment fragment = new OI_GraphFragment('n1', new List<OI_NodeSummary>(), new List<OI_EdgeSummary>(), new List<String>(), false, null);
        String key = cache.buildFragmentCacheKey('n1', 1, 'filterSig', 'checksum1');
        cache.putFragment(key, fragment, 60);
        System.assertEquals('n1', cache.getFragment(key).centerNodeKey);
    }

    @isTest
    static void testGetFragmentReturnsNullOnMiss() {
        System.assertEquals(null, new OI_GraphCache(new OI_FakeKeyValueCacheProvider()).getFragment('missingkey'));
    }

    @isTest
    static void testBuildFragmentCacheKeyIsDeterministic() {
        OI_GraphCache cache = new OI_GraphCache(new OI_FakeKeyValueCacheProvider());
        System.assertEquals(cache.buildFragmentCacheKey('n1', 1, 'f', 'c'), cache.buildFragmentCacheKey('n1', 1, 'f', 'c'));
    }

    @isTest
    static void testBuildFragmentCacheKeyChangesWithChecksum() {
        OI_GraphCache cache = new OI_GraphCache(new OI_FakeKeyValueCacheProvider());
        System.assertNotEquals(cache.buildFragmentCacheKey('n1', 1, 'f', 'c1'), cache.buildFragmentCacheKey('n1', 1, 'f', 'c2'));
    }

    @isTest
    static void testEvictRemovesEntry() {
        OI_GraphCache cache = new OI_GraphCache(new OI_FakeKeyValueCacheProvider());
        String key = cache.buildFragmentCacheKey('n1', 1, 'f', 'c');
        cache.putFragment(key, new OI_GraphFragment('n1', null, null, null, false, null), 60);
        cache.evict(key);
        System.assertEquals(null, cache.getFragment(key));
    }
}
