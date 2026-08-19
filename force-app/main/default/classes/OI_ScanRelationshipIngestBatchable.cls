/**
 * Purpose: Governor-safe ingestion of a large metadata type's discovered relationships
 *          (Sprint 9.1, ADR-0004 amendment) — the relationship-phase counterpart of
 *          OI_ScanComponentIngestBatchable, chained from that class's finish() when a
 *          type's relationships also exceed OI_ScanOrchestratorQueueable.CHUNK_SIZE.
 * Responsibilities: Ingest relationships in CHUNK_SIZE-sized scopes via
 *                    OI_MutationGenerator.translateAndIngest; on finish(), hand off to
 *                    OI_ScanOrchestratorQueueable.finalizeTypeAfterIngest with the
 *                    observedNodeKeys carried over from the component phase.
 * Dependencies: OI_MutationGenerator, OI_ScanOrchestratorQueueable (CHUNK_SIZE,
 *               finalizeTypeAfterIngest, failTaskAndAdvance).
 * Limitations: translateAndIngest's observed-nodeKey bookkeeping only derives keys from
 *              components (MetadataScanner.md §15) — a relationships-only ingest never
 *              contributes new keys, so observedNodeKeys is carried through unchanged
 *              rather than re-accumulated here.
 */
public without sharing class OI_ScanRelationshipIngestBatchable implements Database.Batchable<OI_DiscoveredRelationship>, Database.Stateful {
    private final Id scanRunId;
    private final Id scanTaskId;
    private final String metadataTypeApiName;
    private final List<OI_DiscoveredRelationship> relationships;
    private final Boolean isFullSnapshot;
    private final Set<String> observedNodeKeys;
    private final List<String> remainingMetadataTypes;

    private Boolean hadFailure = false;
    private Exception failure;

    public OI_ScanRelationshipIngestBatchable(
        Id scanRunId,
        Id scanTaskId,
        String metadataTypeApiName,
        List<OI_DiscoveredRelationship> relationships,
        Boolean isFullSnapshot,
        Set<String> observedNodeKeys,
        List<String> remainingMetadataTypes
    ) {
        this.scanRunId = scanRunId;
        this.scanTaskId = scanTaskId;
        this.metadataTypeApiName = metadataTypeApiName;
        this.relationships = relationships;
        this.isFullSnapshot = isFullSnapshot;
        this.observedNodeKeys = observedNodeKeys;
        this.remainingMetadataTypes = remainingMetadataTypes;
    }

    public Iterable<OI_DiscoveredRelationship> start(Database.BatchableContext bc) {
        return relationships;
    }

    public void execute(Database.BatchableContext bc, List<OI_DiscoveredRelationship> scope) {
        if (hadFailure) {
            return;
        }
        try {
            OI_DiscoveryBatch chunkBatch = new OI_DiscoveryBatch(scanTaskId, metadataTypeApiName, new List<OI_DiscoveredComponent>(), scope, false, 0);
            OI_MutationGenerator generator = new OI_MutationGenerator();
            generator.translateAndIngest(chunkBatch);
            /** DE-7: this is the phase that matters most for Impact Analysis staleness — an edge change alters impact answers for nodes whose own content never changed (OI_IngestDelta explains the case). */
            OI_ScanOrchestratorQueueable.invalidateImpactCacheFor(generator.consumeIngestDelta());
        } catch (Exception e) {
            hadFailure = true;
            failure = e;
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (hadFailure) {
            OI_ScanOrchestratorQueueable.failTaskAndAdvance(scanRunId, scanTaskId, metadataTypeApiName, remainingMetadataTypes, failure);
            return;
        }
        OI_ScanOrchestratorQueueable.finalizeTypeAfterIngest(scanRunId, scanTaskId, metadataTypeApiName, observedNodeKeys, isFullSnapshot, remainingMetadataTypes);
    }
}
