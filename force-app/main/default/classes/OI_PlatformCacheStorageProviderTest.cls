/**
 * Purpose: Verifies OI_PlatformCacheStorageProvider degrades to a harmless cache miss
 *          when the backing partition is not provisioned (GraphRepository.md §17) —
 *          the expected state this sprint (see class-level doc on the provider).
 */
@isTest
private class OI_PlatformCacheStorageProviderTest {
    @isTest
    static void testGetReturnsNullWhenPartitionMissing() {
        System.assertEquals(null, new OI_PlatformCacheStorageProvider().get('anykey'));
    }

    @isTest
    static void testPutAndEvictDoNotThrowWhenPartitionMissing() {
        OI_PlatformCacheStorageProvider provider = new OI_PlatformCacheStorageProvider();
        provider.put('k', 'v', 60);
        provider.evict('k');
        System.assert(true, 'No exception should propagate when the partition is not provisioned.');
    }
}
