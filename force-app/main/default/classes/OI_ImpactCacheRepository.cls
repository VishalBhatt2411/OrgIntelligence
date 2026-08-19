/**
 * Purpose: Bulk persistence and lookup of OI_Impact_Cache__c — the only class that
 *          writes or queries this object (CodingStandards.md §1's Repository role), used
 *          exclusively by OI_DependencyEngineService.
 * Responsibilities: getUnexpired(cacheKey) — the cached row if present and not past its TTL;
 *                    put(...) — upsert by Cache_Key__c; evictByRootNodeKeys(...) — the DE-7
 *                    invalidation entry point. Deliberately a small, dedicated Repository for
 *                    its own object rather than routing through OI_GraphRepository/
 *                    OI_GraphCache — Impact Analysis results are a categorically different
 *                    cache (durable, node-scoped invalidation, its own TTL) from the Graph
 *                    Engine's own L1 fragment cache (GraphEngine.md §8), and this mirrors the
 *                    same self-contained-Repository-per-object pattern OI_LogRepository
 *                    already establishes for OI_Log__c.
 * Dependencies: OI_Impact_Cache__c.
 * Limitations: without sharing — this is an application-internal cache table (ADR-0006),
 *              the same posture OI_GraphRepository's write paths already take against
 *              OI_Graph_Node__c/OI_Graph_Edge__c. evictByRootNodeKeys only evicts rows whose
 *              Root_Node_Key__c is directly in the given set — computing "scan-delta keys
 *              plus their current 1-hop neighbors" (the full DE-7 rule) is
 *              OI_DependencyEngineService's job, not this class's; a change two or more hops
 *              inside an already-cached subgraph is not caught by this mechanism and goes
 *              stale until Expires_At__c, an accepted, documented risk (see
 *              OI_DependencyEngineService's own class doc).
 */
public without sharing class OI_ImpactCacheRepository {
    public OI_Impact_Cache__c getUnexpired(String cacheKey) {
        if (String.isBlank(cacheKey)) {
            return null;
        }
        List<OI_Impact_Cache__c> rows = [
            SELECT Id, Cache_Key__c, Root_Node_Key__c, Direction__c, Depth__c, Manual_Test_Json__c, Computed_At__c, Expires_At__c
            FROM OI_Impact_Cache__c
            WHERE Cache_Key__c = :cacheKey AND Expires_At__c > :Datetime.now()
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    public void put(String cacheKey, String rootNodeKey, String direction, Integer depth, String resultJson, Datetime computedAt, Datetime expiresAt) {
        if (String.isBlank(cacheKey)) {
            return;
        }
        OI_Impact_Cache__c row = new OI_Impact_Cache__c(
            Cache_Key__c = cacheKey,
            Root_Node_Key__c = rootNodeKey,
            Direction__c = direction,
            Depth__c = depth,
            Manual_Test_Json__c = resultJson,
            Computed_At__c = computedAt,
            Expires_At__c = expiresAt
        );
        upsert row OI_Impact_Cache__c.Cache_Key__c;
    }

    /** DE-7's mechanism — evicts every cached row whose Root_Node_Key__c is in the given set. Callable today (OI_DependencyEngineServiceTest exercises it directly); automatic invocation from the live scan pipeline (calling this once a scan delta is known) is a documented near-term follow-up, not wired in this pass — see Backlog.md's Dependency Engine epic. */
    public void evictByRootNodeKeys(Set<String> rootNodeKeys) {
        if (rootNodeKeys == null || rootNodeKeys.isEmpty()) {
            return;
        }
        delete [SELECT Id FROM OI_Impact_Cache__c WHERE Root_Node_Key__c IN :rootNodeKeys];
    }
}
