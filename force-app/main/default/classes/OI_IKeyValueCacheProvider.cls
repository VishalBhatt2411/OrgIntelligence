/**
 * Purpose: The narrower interface the Platform Cache storage provider implements
 *          (GraphRepository.md §3, §10) — deliberately separate from
 *          OI_IGraphStorageProvider, since a cache entry has no "current version" or
 *          archival concept.
 * Responsibilities: Define get/put/evict — the only three operations OI_GraphCache needs
 *                    from its backing store, issued through OI_GraphRepository (the only
 *                    component with direct Platform Cache API access).
 * Dependencies: None.
 * Limitations: Implementations must degrade a backend failure to a cache miss, never an
 *              error (GraphRepository.md §17).
 */
public interface OI_IKeyValueCacheProvider {
    Object get(String key);

    void put(String key, Object value, Integer ttlSeconds);

    void evict(String key);
}
