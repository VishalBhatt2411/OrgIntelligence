/**
 * Purpose: Backing store for OI_GraphCache's fragment-result caching policy
 *          (GraphRepository.md §10) — the Org Platform Cache partition.
 * Responsibilities: Implement OI_IKeyValueCacheProvider as thin pass-throughs to
 *                    Cache.Org. The only component with direct Platform Cache API access
 *                    (GraphRepository.md §10) — callable only by OI_GraphCache.
 * Dependencies: Cache.Org (Platform Cache).
 * Limitations: A backend failure degrades to a cache miss, never an error
 *              (GraphRepository.md §17) — every method swallows Cache.* exceptions,
 *              which includes the partition not existing yet. The 'local.OI_GraphCache'
 *              Platform Cache Partition itself is NOT provisioned in this sprint (a
 *              metadata-format issue with PlatformCachePartition deployment was hit and
 *              deferred rather than solved under time pressure — see Sprint 7 deliverables
 *              report). Until it is provisioned (Roadmap Phase 2), every call here is a
 *              guaranteed, harmless cache miss.
 */
public without sharing class OI_PlatformCacheStorageProvider implements OI_IKeyValueCacheProvider {
    private static final String PARTITION_NAME = 'local.OI_GraphCache';

    public Object get(String key) {
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(PARTITION_NAME);
            if (partition.contains(key)) {
                return partition.get(key);
            }
            return null;
        } catch (Cache.Org.OrgCacheException e) {
            return null;
        }
    }

    public void put(String key, Object value, Integer ttlSeconds) {
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(PARTITION_NAME);
            Integer effectiveTtl = ttlSeconds == null ? 3600 : ttlSeconds;
            partition.put(key, value, effectiveTtl);
        } catch (Cache.Org.OrgCacheException e) {
            // A cache write failure is never allowed to fail the caller's read/write path
            // (GraphRepository.md §17) — silently skipped; the durable Repository path is
            // unaffected either way.
        }
    }

    public void evict(String key) {
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(PARTITION_NAME);
            partition.remove(key);
        } catch (Cache.Org.OrgCacheException e) {
            // Same rationale as put() above.
        }
    }
}
