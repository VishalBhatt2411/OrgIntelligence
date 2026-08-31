/**
 * Purpose: The only component that knows both the Salesforce metadata vocabulary and the
 *          Graph Engine's opaque vocabulary (MetadataScanner.md §15, ADR-0015) — translates
 *          a Discovery Model batch into Graph Mutations.
 * Responsibilities: Input: one OI_DiscoveryBatch (Salesforce vocabulary). Output:
 *                    List<OI_GraphMutation> (GraphEngine.md §7 shape), handed to
 *                    OI_GraphEngine.ingest — never to OI_GraphBuilder or
 *                    OI_GraphRepository directly (ADR-0013). Also performs retire-detection
 *                    for full-snapshot batches, reading current Active keys via
 *                    OI_GraphEngine's read-only pass-through (MetadataScanner.md §15 item 6).
 * Dependencies: OI_GraphEngine (constructor-injected), OI_ComponentKeyUtil, OI_HashUtil.
 * Limitations: componentKey resolution — a documented deviation from MetadataScanner.md
 *              §5's literal "hash(...)" wording for componentKey, and this class's own use
 *              of it. This class only ever sees ONE OI_DiscoveryBatch at a time (its
 *              documented contract), yet a component's parentComponentKey — or a
 *              relationship's endpoint componentKey — routinely refers to a component
 *              discovered by a DIFFERENT Scanner/task (a Field's parent Object, scanned
 *              separately from the Field). A one-way SHA-256 digest cannot be inverted to
 *              recover the (componentKind, namespace, fullyQualifiedName) needed to derive
 *              that other component's nodeKey without the original component in memory.
 *              OI_ComponentKeyUtil therefore builds componentKey as a deterministic,
 *              parseable string instead of a hash — componentKey remains internal-only
 *              (MetadataScanner.md §19), so nothing outside this Scanner/Mutation-Generator
 *              seam is affected. nodeKey/edgeKey/versionKey (the values actually persisted
 *              and potentially exposed via the API) are real SHA-256 digests, exactly as
 *              GraphEngine.md §2/§3 specify — this deviation is scoped narrowly to the
 *              Discovery-Model-internal componentKey/relationshipKey, not the Graph Engine's
 *              own keys. Cascading edge retirement when an endpoint node is retired
 *              (GraphEngine.md §5's "an edge can't be more active than what it points at")
 *              is Roadmap work, not built this sprint — this class only retires nodes/edges
 *              directly observed missing from a full snapshot of their OWN componentKind.
 */
public inherited sharing class OI_MutationGenerator {
    private static final String TYPE_KEY_PREFIX = 'SalesforceMetadata.';
    private static final Integer RETIRE_DETECTION_PAGE_SIZE = 200;

    private final OI_GraphEngine graphEngine;

    /**
     * Accumulates what every ingest through THIS instance genuinely changed (DE-7). Instance-
     * scoped rather than returned per call, because a caller chunking one logical scan task
     * across several translateAndIngest/retireKeys calls must invalidate the Impact Analysis
     * cache ONCE against the union of all of them — invalidating per chunk would both waste
     * work and, worse, leave a later chunk's changes uninvalidated if the caller stopped
     * reading intermediate results. Exposed via consumeIngestDelta(), which clears as it reads
     * so the same delta can never be acted on twice.
     */
    private final OI_IngestDelta accumulatedDelta = new OI_IngestDelta();

    /**
     * Relationships this instance dropped because an endpoint componentKey could not be resolved
     * to a nodeKey. Counted rather than silently discarded (which is what this class did before):
     * a non-zero value is the difference between "this type genuinely has few dependencies" and
     * "we found dependencies and threw some away," and only the second one is a defect worth
     * chasing. Surfaced through scan coverage so it reaches an admin instead of dying here.
     */
    private Integer skippedRelationshipCount = 0;

    /** Reads and clears the skipped count — same read-and-clear contract as consumeIngestDelta, for the same reason: a caller must not be able to double-report the same skips. */
    public Integer consumeSkippedRelationshipCount() {
        Integer consumed = skippedRelationshipCount;
        skippedRelationshipCount = 0;
        return consumed;
    }

    /**
     * Returns everything this instance has changed since the last call, and clears it.
     *
     * Read-and-clear rather than a plain getter: double-invalidating is harmless but wasteful,
     * whereas silently re-reporting stale keys after a caller has already acted on them makes
     * the contract ambiguous about whose responsibility invalidation is. Consuming makes the
     * handoff explicit and single-owner.
     */
    public OI_IngestDelta consumeIngestDelta() {
        OI_IngestDelta consumed = new OI_IngestDelta(
            new Set<String>(accumulatedDelta.changedNodeKeys),
            new Set<String>(accumulatedDelta.changedEdgeKeys),
            new Set<String>(accumulatedDelta.impactedNodeKeys)
        );
        accumulatedDelta.changedNodeKeys.clear();
        accumulatedDelta.changedEdgeKeys.clear();
        accumulatedDelta.impactedNodeKeys.clear();
        return consumed;
    }

    public OI_MutationGenerator() {
        this(new OI_GraphEngine());
    }

    public OI_MutationGenerator(OI_GraphEngine graphEngine) {
        this.graphEngine = graphEngine;
    }

    /**
     * Translates a Discovery Model batch into Graph Mutations and ingests them via
     * OI_GraphEngine (MetadataScanner.md §15). Returns the nodeKeys observed in this call
     * — an opaque bookkeeping set (never interpreted by the caller) that lets a caller
     * chunking a large type's components across multiple calls/hops (governor-limit-safe,
     * per OI_ScanOrchestratorQueueable) accumulate the full observed set and pass it to
     * retireMissingKeys once, after every chunk has been ingested, rather than relying on
     * this method's own per-call isFullSnapshot handling (which is correct only when a
     * single call already represents the type's complete batch).
     */
    public Set<String> translateAndIngest(OI_DiscoveryBatch batch) {
        if (batch == null) {
            return new Set<String>();
        }
        Id scanRunId = resolveScanRunId(batch.scanTaskId);
        List<OI_GraphMutation> mutations = new List<OI_GraphMutation>();
        Set<String> observedNodeKeys = new Set<String>();

        for (OI_DiscoveredComponent component : batch.components) {
            String typeKey = TYPE_KEY_PREFIX + component.componentKind;
            String nodeKey = deriveNodeKey(typeKey, component.namespace, component.fullyQualifiedName);
            observedNodeKeys.add(nodeKey);
            mutations.add(
                OI_GraphMutation.upsertNode(
                    nodeKey,
                    typeKey,
                    resolveLabel(component),
                    component.fullyQualifiedName,
                    resolveComponentKeyToNodeKey(component.parentComponentKey),
                    component.rawAttributes,
                    component.rawChecksum,
                    null,
                    scanRunId
                )
            );
        }

        for (OI_DiscoveredRelationship relationship : batch.relationships) {
            String fromNodeKey = resolveComponentKeyToNodeKey(relationship.fromComponentKey);
            String toNodeKey = resolveComponentKeyToNodeKey(relationship.toComponentKey);
            if (fromNodeKey == null || toNodeKey == null) {
                /** Counted, not silently dropped — see skippedRelationshipCount. Skipping is still the right action (an edge needs two resolvable endpoints), but the fact that it happened must survive. */
                skippedRelationshipCount++;
                continue;
            }
            String edgeTypeKey = TYPE_KEY_PREFIX + relationship.relationshipKind;
            String edgeKey = deriveEdgeKey(fromNodeKey, edgeTypeKey, toNodeKey);
            mutations.add(
                OI_GraphMutation.upsertEdge(edgeKey, edgeTypeKey, fromNodeKey, toNodeKey, relationship.rawAttributes, null, null, null, scanRunId)
            );
        }

        if (!mutations.isEmpty()) {
            accumulatedDelta.addAll(graphEngine.ingest(mutations));
        }

        if (batch.isFullSnapshot == true && String.isNotBlank(batch.componentKind)) {
            retireMissingKeys(batch.componentKind, observedNodeKeys, scanRunId);
        }
        return observedNodeKeys;
    }

    /**
     * Retire-detection entry point (MetadataScanner.md §15 item 6), callable directly by a
     * caller that has accumulated the full observed-key set for a componentKind across
     * multiple chunked translateAndIngest calls, as well as internally by translateAndIngest
     * itself for the simple, unchunked, single-call case. Loops across every page of Active
     * keys internally — safe for a small-to-moderate Active-key population. A caller
     * chunking a large retirement wave across multiple transactions (Sprint 9.1,
     * OI_ScanRetireDetectionBatchable) should use findMissingKeys + retireKeys instead,
     * which split the (cheap, read-only) diff from the (DML-costly) retire so only the
     * latter needs to be chunked.
     */
    public void retireMissingKeys(String componentKind, Set<String> observedNodeKeys, Id scanRunId) {
        performRetireDetection(TYPE_KEY_PREFIX + componentKind, observedNodeKeys, scanRunId);
    }

    /**
     * Read-only half of retire-detection (Sprint 9.1 — replaces the Sprint 9/MS-4b
     * retireMissingKeysPage, which combined the read and the retire into one paginated
     * call and therefore had to page the *write* side too). Loops across every page of
     * Active keys internally, same as performRetireDetection, but returns the candidates
     * instead of retiring them — safe to call in one transaction even for a large Active-
     * key population, since this issues no DML at all, only the same paginated reads
     * getCurrentActiveKeysByType already bounds to RETIRE_DETECTION_PAGE_SIZE per call.
     */
    public List<String> findMissingKeys(String componentKind, Set<String> observedNodeKeys) {
        String typeKey = TYPE_KEY_PREFIX + componentKind;
        List<String> missingKeys = new List<String>();
        String cursor = null;
        Boolean hasMore = true;
        while (hasMore) {
            OI_KeysPage page = graphEngine.getCurrentActiveKeysByType(typeKey, cursor, RETIRE_DETECTION_PAGE_SIZE, false);
            for (String activeKey : page.items) {
                if (!observedNodeKeys.contains(activeKey)) {
                    missingKeys.add(activeKey);
                }
            }
            hasMore = page.hasMore;
            cursor = page.nextCursor;
        }
        return missingKeys;
    }

    /**
     * Write half of retire-detection (Sprint 9.1) — retires exactly the given nodeKeys,
     * paired with findMissingKeys. Takes an already-identified list rather than diffing
     * itself, so a caller chunking the DML-costly retire step across multiple transactions
     * (OI_ScanRetireDetectionBatchable, one Batch Apex scope per call) never re-reads or
     * re-diffs what findMissingKeys already determined once, up front.
     */
    public void retireKeys(List<String> nodeKeysToRetire, Id scanRunId) {
        if (nodeKeysToRetire == null || nodeKeysToRetire.isEmpty()) {
            return;
        }
        List<OI_GraphMutation> retireMutations = new List<OI_GraphMutation>();
        for (String nodeKey : nodeKeysToRetire) {
            retireMutations.add(OI_GraphMutation.retireNode(nodeKey, scanRunId));
        }
        accumulatedDelta.addAll(graphEngine.ingest(retireMutations));
    }

    /**
     * typeKey derivation: a deterministic naming convention, not a runtime lookup table
     * (MetadataScanner.md §15 item 1). nodeKey/edgeKey derivation matches GraphEngine.md
     * §2/§3 exactly — a real SHA-256 digest over typeKey+namespace+fullyQualifiedName.
     */
    /**
     * The friendly Describe/Tooling label a Scanner captured in rawAttributes.label (e.g.
     * "Owner ID" for Account.OwnerId, versus the "Account.OwnerId" API name already carried
     * separately in secondaryKey) — falls back to fullyQualifiedName only for componentKinds
     * that don't capture a distinct label attribute (e.g. ApexClass has no separate friendly
     * label concept). Without this, Label__c was a second copy of the API name, defeating the
     * distinct Label/API-Name display the Hierarchy Visualizer's Detail Panel requires.
     */
    private String resolveLabel(OI_DiscoveredComponent component) {
        Object rawLabel = component.rawAttributes.get('label');
        return rawLabel instanceof String && String.isNotBlank((String) rawLabel) ? (String) rawLabel : component.fullyQualifiedName;
    }

    private String deriveNodeKey(String typeKey, String namespace, String fullyQualifiedName) {
        return OI_HashUtil.hash(typeKey + '::' + (namespace == null ? '' : namespace) + '::' + fullyQualifiedName);
    }

    private String deriveEdgeKey(String sourceNodeKey, String edgeTypeKey, String targetNodeKey) {
        return OI_HashUtil.hash(sourceNodeKey + '::' + edgeTypeKey + '::' + targetNodeKey);
    }

    /** See class doc — resolves a componentKey to a nodeKey without requiring the original component in memory. */
    private String resolveComponentKeyToNodeKey(String componentKey) {
        if (String.isBlank(componentKey)) {
            return null;
        }
        OI_ComponentKeyUtil.ParsedComponentKey parsed = OI_ComponentKeyUtil.parse(componentKey);
        if (parsed == null) {
            return null;
        }
        return deriveNodeKey(TYPE_KEY_PREFIX + parsed.componentKind, parsed.namespace, parsed.fullyQualifiedName);
    }

    private Id resolveScanRunId(Id scanTaskId) {
        if (scanTaskId == null) {
            return null;
        }
        List<OI_Scan_Task__c> tasks = [SELECT Scan_Run__c FROM OI_Scan_Task__c WHERE Id = :scanTaskId LIMIT 1];
        return tasks.isEmpty() ? null : tasks[0].Scan_Run__c;
    }

    /**
     * Retire-detection (full scans only, MetadataScanner.md §15 item 6): paginate through
     * every currently-Active key of this typeKey via OI_GraphEngine's read-only pass-
     * through, diff against what this batch actually observed, and retire exactly the
     * difference. Never loads the full key set into memory at once.
     */
    private void performRetireDetection(String typeKey, Set<String> observedNodeKeys, Id scanRunId) {
        List<OI_GraphMutation> retireMutations = new List<OI_GraphMutation>();
        String cursor = null;
        Boolean hasMore = true;
        while (hasMore) {
            OI_KeysPage page = graphEngine.getCurrentActiveKeysByType(typeKey, cursor, RETIRE_DETECTION_PAGE_SIZE, false);
            for (String activeKey : page.items) {
                if (!observedNodeKeys.contains(activeKey)) {
                    retireMutations.add(OI_GraphMutation.retireNode(activeKey, scanRunId));
                }
            }
            hasMore = page.hasMore;
            cursor = page.nextCursor;
        }
        if (!retireMutations.isEmpty()) {
            accumulatedDelta.addAll(graphEngine.ingest(retireMutations));
        }
    }
}
