/**
 * Purpose: Governor-safe ingestion of a large metadata type's discovered components
 *          (Sprint 9.1, ADR-0004 amendment) — replaces Queueable self-chaining for
 *          intra-type chunking with Batch Apex, whose execute()/finish() invocations are
 *          not tracked by the Developer Edition "Maximum stack depth" chain-depth counter
 *          OI_ScanOrchestratorQueueable's inter-type Queueable chain is subject to.
 * Responsibilities: Ingest batch.components in CHUNK_SIZE-sized scopes via
 *                    OI_MutationGenerator.translateAndIngest; accumulate observed nodeKeys
 *                    across scopes (Database.Stateful); on finish(), hand off to
 *                    OI_ScanRelationshipIngestBatchable if relationships remain, otherwise
 *                    directly to OI_ScanOrchestratorQueueable.finalizeTypeAfterIngest.
 * Dependencies: OI_MutationGenerator, OI_ScanOrchestratorQueueable (CHUNK_SIZE,
 *               finalizeTypeAfterIngest, failTaskAndAdvance, recordComponentIngestProgress),
 *               OI_ScanRelationshipIngestBatchable.
 * Limitations: A chunk-ingestion failure is isolated to this Scan Task (mirrors the
 *              Queueable path's existing failure-isolation guarantee) but does not retry
 *              the failed scope — matches OI_ScanOrchestratorQueueable's existing retry
 *              granularity (per Scan Task, not per record, MetadataScanner.md §14).
 */
public without sharing class OI_ScanComponentIngestBatchable implements Database.Batchable<OI_DiscoveredComponent>, Database.Stateful {
  /** Reports progress every 5th scope (~300 records at CHUNK_SIZE=60) — frequent enough to keep a large org's scan observably alive, bounded so a very large type doesn't multiply DML/platform-event volume per scope. */
  private static final Integer PROGRESS_REPORT_INTERVAL = 5;

  private final Id scanRunId;
  private final Id scanTaskId;
  private final String metadataTypeApiName;
  private final List<OI_DiscoveredComponent> components;
  private final List<OI_DiscoveredRelationship> relationships;
  private final Boolean isFullSnapshot;
  private final List<String> remainingMetadataTypes;

  private Set<String> observedNodeKeys = new Set<String>();
  private Boolean hadFailure = false;
  private Exception failure;
  private Integer scopesProcessed = 0;

  public OI_ScanComponentIngestBatchable(
    Id scanRunId,
    Id scanTaskId,
    String metadataTypeApiName,
    List<OI_DiscoveredComponent> components,
    List<OI_DiscoveredRelationship> relationships,
    Boolean isFullSnapshot,
    List<String> remainingMetadataTypes
  ) {
    this.scanRunId = scanRunId;
    this.scanTaskId = scanTaskId;
    this.metadataTypeApiName = metadataTypeApiName;
    this.components = components;
    this.relationships = relationships;
    this.isFullSnapshot = isFullSnapshot;
    this.remainingMetadataTypes = remainingMetadataTypes;
  }

  public Iterable<OI_DiscoveredComponent> start(Database.BatchableContext bc) {
    return components;
  }

  public void execute(
    Database.BatchableContext bc,
    List<OI_DiscoveredComponent> scope
  ) {
    if (hadFailure) {
      return;
    }
    try {
      OI_DiscoveryBatch chunkBatch = new OI_DiscoveryBatch(
        scanTaskId,
        metadataTypeApiName,
        scope,
        new List<OI_DiscoveredRelationship>(),
        false,
        0
      );
      OI_MutationGenerator generator = new OI_MutationGenerator();
      observedNodeKeys.addAll(generator.translateAndIngest(chunkBatch));
      /** DE-7: evict impact results this chunk's genuinely-changed components made stale — never the unchanged majority a full rescan also observes. */
      OI_ScanOrchestratorQueueable.invalidateImpactCacheFor(
        generator.consumeIngestDelta()
      );
      scopesProcessed++;
      if (Math.mod(scopesProcessed, PROGRESS_REPORT_INTERVAL) == 0) {
        OI_ScanOrchestratorQueueable.recordComponentIngestProgress(
          scanRunId,
          scanTaskId,
          metadataTypeApiName,
          observedNodeKeys.size(),
          components.size()
        );
      }
    } catch (Exception e) {
      hadFailure = true;
      failure = e;
    }
  }

  public void finish(Database.BatchableContext bc) {
    if (hadFailure) {
      OI_ScanOrchestratorQueueable.failTaskAndAdvance(
        scanRunId,
        scanTaskId,
        metadataTypeApiName,
        remainingMetadataTypes,
        failure
      );
      return;
    }
    if (!relationships.isEmpty()) {
      try {
        Database.executeBatch(
          new OI_ScanRelationshipIngestBatchable(
            scanRunId,
            scanTaskId,
            metadataTypeApiName,
            relationships,
            isFullSnapshot,
            observedNodeKeys,
            remainingMetadataTypes
          ),
          OI_ScanOrchestratorQueueable.CHUNK_SIZE
        );
      } catch (Exception e) {
        OI_ScanOrchestratorQueueable.failTaskAndAdvance(
          scanRunId,
          scanTaskId,
          metadataTypeApiName,
          remainingMetadataTypes,
          e
        );
      }
      return;
    }
    OI_ScanOrchestratorQueueable.finalizeTypeAfterIngest(
      scanRunId,
      scanTaskId,
      metadataTypeApiName,
      observedNodeKeys,
      isFullSnapshot,
      remainingMetadataTypes
    );
  }
}
