/**
 * Purpose: Verifies OI_ImpactCacheRepository's get/put/evict behavior — cache hit, cache
 *          miss, TTL expiry, and root-node-keyed eviction (DE-7's mechanism).
 */
@isTest
private class OI_ImpactCacheRepositoryTest {
    @isTest
    static void testGetUnexpiredReturnsNullWhenNoRowExists() {
        OI_ImpactCacheRepository repo = new OI_ImpactCacheRepository();
        System.assertEquals(null, repo.getUnexpired('missing-key'));
    }

    @isTest
    static void testPutThenGetUnexpiredReturnsTheRow() {
        OI_ImpactCacheRepository repo = new OI_ImpactCacheRepository();
        Datetime now = Datetime.now();
        repo.put('key1', 'rootA', 'Forward', 3, '{"nodes":[]}', now, now.addMinutes(30));

        OI_Impact_Cache__c row = repo.getUnexpired('key1');
        System.assertNotEquals(null, row);
        System.assertEquals('rootA', row.Root_Node_Key__c);
        System.assertEquals('Forward', row.Direction__c);
        System.assertEquals(3, row.Depth__c);
        System.assertEquals('{"nodes":[]}', row.Manual_Test_Json__c);
    }

    @isTest
    static void testPutTwiceWithTheSameCacheKeyUpsertsRatherThanDuplicating() {
        OI_ImpactCacheRepository repo = new OI_ImpactCacheRepository();
        Datetime now = Datetime.now();
        repo.put('key1', 'rootA', 'Forward', 3, '{"nodes":[]}', now, now.addMinutes(30));
        repo.put('key1', 'rootA', 'Forward', 3, '{"nodes":["updated"]}', now, now.addMinutes(30));

        List<OI_Impact_Cache__c> rows = [SELECT Id, Manual_Test_Json__c FROM OI_Impact_Cache__c WHERE Cache_Key__c = 'key1'];
        System.assertEquals(1, rows.size(), 'A second put with the same Cache_Key__c must upsert, never insert a duplicate row.');
        System.assertEquals('{"nodes":["updated"]}', rows[0].Manual_Test_Json__c);
    }

    @isTest
    static void testGetUnexpiredReturnsNullForAnExpiredRow() {
        OI_ImpactCacheRepository repo = new OI_ImpactCacheRepository();
        Datetime past = Datetime.now().addMinutes(-60);
        repo.put('expiredKey', 'rootA', 'Forward', 3, '{"nodes":[]}', past, past.addMinutes(1));

        System.assertEquals(null, repo.getUnexpired('expiredKey'), 'A row past its Expires_At__c must be treated as a miss, never served stale.');
    }

    @isTest
    static void testEvictByRootNodeKeysRemovesOnlyMatchingRows() {
        OI_ImpactCacheRepository repo = new OI_ImpactCacheRepository();
        Datetime now = Datetime.now();
        repo.put('keyA', 'rootA', 'Forward', 3, '{}', now, now.addMinutes(30));
        repo.put('keyB', 'rootB', 'Forward', 3, '{}', now, now.addMinutes(30));

        repo.evictByRootNodeKeys(new Set<String>{ 'rootA' });

        System.assertEquals(null, repo.getUnexpired('keyA'), 'The evicted root\'s cache row must be gone.');
        System.assertNotEquals(null, repo.getUnexpired('keyB'), 'An unrelated root\'s cache row must survive the eviction untouched.');
    }

    @isTest
    static void testEvictByRootNodeKeysWithAnEmptySetIsANoOp() {
        OI_ImpactCacheRepository repo = new OI_ImpactCacheRepository();
        repo.put('keyA', 'rootA', 'Forward', 3, '{}', Datetime.now(), Datetime.now().addMinutes(30));

        repo.evictByRootNodeKeys(new Set<String>());

        System.assertNotEquals(null, repo.getUnexpired('keyA'));
    }
}
