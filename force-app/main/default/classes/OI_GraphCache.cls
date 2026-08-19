/**
 * Purpose: Fragment-result caching policy (GraphEngine.md §14) — decides cache keys,
 *          TTLs, and invalidation, issuing reads/writes through OI_GraphRepository's
 *          Platform Cache provider rather than calling Cache.Org directly
 *          (GraphRepository.md §10).
 * Responsibilities: Reachable only through OI_GraphEngine (ADR-0013). Never calls the
 *                    Platform Cache API itself.
 * Dependencies: OI_IKeyValueCacheProvider (constructor-injected).
 * Limitations: Sprint 7 scope is the seam only — no fragment shape exists yet to cache
 *              (OI_GraphTraversal ships in Roadmap Phase 2).
 */
public class OI_GraphCache {
    private final OI_IKeyValueCacheProvider cacheProvider;

    public OI_GraphCache() {
        this(new OI_PlatformCacheStorageProvider());
    }

    public OI_GraphCache(OI_IKeyValueCacheProvider cacheProvider) {
        this.cacheProvider = cacheProvider;
    }

    /** Builds the cache key: hash(nodeKey + hopDepth + filterSet + currentVersionChecksum) (Architecture §11). */
    public String buildFragmentCacheKey(String nodeKey, Integer hopDepth, String filterSetSignature, String checksum) {
        String raw = nodeKey + ':' + hopDepth + ':' + filterSetSignature + ':' + checksum;
        Blob hashed = Crypto.generateDigest('SHA-256', Blob.valueOf(raw));
        return EncodingUtil.convertToHex(hashed);
    }

    public OI_GraphFragment getFragment(String cacheKey) {
        Object cached = cacheProvider.get(cacheKey);
        return cached instanceof OI_GraphFragment ? (OI_GraphFragment) cached : null;
    }

    public void putFragment(String cacheKey, OI_GraphFragment fragment, Integer ttlSeconds) {
        cacheProvider.put(cacheKey, fragment, ttlSeconds);
    }

    public void evict(String cacheKey) {
        cacheProvider.evict(cacheKey);
    }
}
