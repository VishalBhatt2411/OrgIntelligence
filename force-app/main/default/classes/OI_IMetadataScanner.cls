/**
 * Purpose: The single Strategy interface, one implementation per componentKind
 *          (MetadataScanner.md §6).
 * Responsibilities: Define scan(context) -> OI_DiscoveryBatch. Stateless and idempotent —
 *                    safe to call again for the same context without side effects.
 * Dependencies: OI_ScanContext, OI_DiscoveryBatch.
 * Limitations: An implementation must never call OI_GraphEngine, construct a typeKey,
 *              perform DML against any OI_Graph_*__c object, or reference
 *              OI_MutationGenerator (MetadataScanner.md §6) — a code-review blocker, not a
 *              style preference. No concrete implementation ships this sprint
 *              (Roadmap Phase 1).
 */
public interface OI_IMetadataScanner {
    OI_DiscoveryBatch scan(OI_ScanContext context);
}
