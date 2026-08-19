/**
 * Purpose: In-memory fake implementing OI_IKeyValueCacheProvider, so OI_GraphCache can be
 *          unit-tested without a real Platform Cache partition.
 * Responsibilities: Mimic get/put/evict semantics in a plain Map.
 * Dependencies: None.
 * Limitations: Test-only — annotated @isTest. No TTL expiry simulation.
 */
@isTest
public class OI_FakeKeyValueCacheProvider implements OI_IKeyValueCacheProvider {
    public Map<String, Object> store = new Map<String, Object>();

    public Object get(String key) {
        return store.get(key);
    }

    public void put(String key, Object value, Integer ttlSeconds) {
        store.put(key, value);
    }

    public void evict(String key) {
        store.remove(key);
    }
}
