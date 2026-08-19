/**
 * Purpose: The only component permitted to decide that a node or edge should change
 *          (GraphEngine.md §7) — turns Mutations into version-aware writes via
 *          OI_GraphRepository.
 * Responsibilities: Reachable only through OI_GraphEngine (ADR-0013). Never touches
 *                    storage directly — every read and write goes through
 *                    OI_GraphRepository (CodingStandards.md §2). Implements the three-way
 *                    version decision (new / liveness-touch / new-version, GraphEngine.md
 *                    §7) plus the parallel two-way retire decision (§5/§6) for a bulk
 *                    Mutation batch.
 * Dependencies: OI_GraphRepository (constructor-injected).
 * Limitations: commitVersion cannot be bulked across different keys without losing its
 *              atomicity guarantee (GraphRepository.md §11) — a content-changed or newly-
 *              discovered observation costs one Repository round-trip per key. Callers
 *              (OI_MutationGenerator, via OI_ScanOrchestratorQueueable) are responsible for
 *              keeping a single ingest() batch within the 150-DML-statement-per-transaction
 *              ceiling this implies (GraphRepository.md §24) — not enforced here, since the
 *              safe batch size depends on how many of a batch's observations are actually
 *              new/changed versus unchanged liveness touches, which the Builder cannot know
 *              in advance of the very Repository read that ingest() itself performs.
 *              Optimistic-concurrency retry (GE-2c, GraphRepository.md §15): on
 *              OI_ConcurrencyException from commitVersion, re-reads that one key's current
 *              version and retries its three-way/retire decision exactly once; a second
 *              conflict propagates uncaught as a task-level failure. No backoff/delay is
 *              introduced before the retry — Apex has no synchronous sleep primitive
 *              usable mid-transaction, and GraphRepository.md §15 itself frames the race
 *              window as narrow enough that an immediate re-read is expected to resolve it.
 */
public class OI_GraphBuilder {
    private final OI_GraphRepository repository;

    public OI_GraphBuilder() {
        this(new OI_GraphRepository());
    }

    public OI_GraphBuilder(OI_GraphRepository repository) {
        this.repository = repository;
    }

    /**
     * Ingests a bulk Mutation batch (GraphEngine.md §7) and reports what genuinely CHANGED as
     * an OI_IngestDelta.
     *
     * This Builder is the only component that can report that: the three-way decision below is
     * the single place where "observed and identical" (a liveness touch) is distinguished from
     * "observed and actually different" (a new version). Callers previously had no way to know
     * which, and Impact Analysis cache invalidation (DE-7) requires exactly this distinction to
     * be both correct and useful — see OI_IngestDelta's own doc comment for why observation
     * sets are simultaneously too broad and too narrow a substitute.
     *
     * Returning a value where this method used to return void is deliberately non-breaking:
     * Apex permits discarding a return value, so every existing `builder.ingest(...)` statement
     * continues to compile and behave identically.
     */
    public OI_IngestDelta ingest(List<OI_GraphMutation> mutations) {
        OI_IngestDelta delta = new OI_IngestDelta();
        if (mutations == null || mutations.isEmpty()) {
            return delta;
        }

        List<OI_GraphMutation> nodeUpserts = new List<OI_GraphMutation>();
        List<OI_GraphMutation> nodeRetires = new List<OI_GraphMutation>();
        List<OI_GraphMutation> edgeUpserts = new List<OI_GraphMutation>();
        List<OI_GraphMutation> edgeRetires = new List<OI_GraphMutation>();

        for (OI_GraphMutation mutation : mutations) {
            validate(mutation);
            if (mutation.mutationType == OI_GraphMutation.MutationType.UPSERT_NODE) {
                nodeUpserts.add(mutation);
            } else if (mutation.mutationType == OI_GraphMutation.MutationType.RETIRE_NODE) {
                nodeRetires.add(mutation);
            } else if (mutation.mutationType == OI_GraphMutation.MutationType.UPSERT_EDGE) {
                edgeUpserts.add(mutation);
            } else {
                edgeRetires.add(mutation);
            }
        }

        applyUpserts(nodeUpserts, false, delta);
        applyUpserts(edgeUpserts, true, delta);
        applyRetires(nodeRetires, false, delta);
        applyRetires(edgeRetires, true, delta);
        return delta;
    }

    /**
     * Records one genuinely-changed key into the delta. An edge additionally contributes BOTH
     * of its endpoint nodes to impactedNodeKeys, because Impact Analysis traverses edges — a
     * node whose own content never changed can still have a different impact answer once an
     * edge touching it changes (OI_IngestDelta's doc comment works through the concrete case).
     */
    private void recordChange(OI_GraphMutation mutation, Boolean isEdgeFlavor, OI_IngestDelta delta) {
        if (!isEdgeFlavor) {
            delta.changedNodeKeys.add(mutation.nodeKey);
            delta.impactedNodeKeys.add(mutation.nodeKey);
            return;
        }
        delta.changedEdgeKeys.add(mutation.edgeKey);
        /** Null for a retireEdge mutation, which carries no endpoints — a documented, currently-unreachable gap (see OI_IngestDelta's Limitations). */
        if (String.isNotBlank(mutation.sourceNodeKey)) {
            delta.impactedNodeKeys.add(mutation.sourceNodeKey);
        }
        if (String.isNotBlank(mutation.targetNodeKey)) {
            delta.impactedNodeKeys.add(mutation.targetNodeKey);
        }
    }

    /**
     * The three-way decision (GraphEngine.md §7): bulk-read current versions for the whole
     * batch first, then decide per key — never a per-observation Repository read.
     */
    private void applyUpserts(List<OI_GraphMutation> upserts, Boolean isEdgeFlavor, OI_IngestDelta delta) {
        if (upserts.isEmpty()) {
            return;
        }
        Set<String> keys = new Set<String>();
        for (OI_GraphMutation mutation : upserts) {
            keys.add(isEdgeFlavor ? mutation.edgeKey : mutation.nodeKey);
        }
        Map<String, OI_VersionRecord> currentByKey = repository.getCurrentVersions(keys, isEdgeFlavor);
        Set<String> livenessTouchKeys = new Set<String>();
        Id livenessRunId = null;

        for (OI_GraphMutation mutation : upserts) {
            String key = isEdgeFlavor ? mutation.edgeKey : mutation.nodeKey;
            OI_VersionRecord current = currentByKey.get(key);
            if (current != null && current.checksum == mutation.checksum) {
                /** Identical checksum — the liveness-touch branch. Deliberately NOT recorded as a change: this is the exact case the impact cache must survive, or a rescan of an unchanged org would pointlessly flush every cached result. */
                livenessTouchKeys.add(key);
                livenessRunId = mutation.scanRunId;
            } else {
                commitUpsertWithRetry(mutation, isEdgeFlavor, current);
                recordChange(mutation, isEdgeFlavor, delta);
            }
        }

        if (!livenessTouchKeys.isEmpty()) {
            repository.touchLiveness(livenessTouchKeys, livenessRunId, isEdgeFlavor);
        }
    }

    /**
     * Commits a new/changed version, retrying once on OI_ConcurrencyException with a fresh
     * read of that one key's current state (GE-2c, GraphRepository.md §15). A second
     * conflict is not retried further — it propagates to the caller as a real failure.
     */
    private void commitUpsertWithRetry(OI_GraphMutation mutation, Boolean isEdgeFlavor, OI_VersionRecord current) {
        try {
            commitVersionFor(mutation, current == null ? 1 : current.versionNumber + 1, isEdgeFlavor, current == null ? null : current.versionKey);
        } catch (OI_ConcurrencyException e) {
            String key = isEdgeFlavor ? mutation.edgeKey : mutation.nodeKey;
            OI_VersionRecord freshCurrent = repository.getCurrentVersions(new Set<String>{ key }, isEdgeFlavor).get(key);
            if (freshCurrent != null && freshCurrent.checksum == mutation.checksum) {
                repository.touchLiveness(new Set<String>{ key }, mutation.scanRunId, isEdgeFlavor);
                return;
            }
            commitVersionFor(mutation, freshCurrent == null ? 1 : freshCurrent.versionNumber + 1, isEdgeFlavor, freshCurrent == null ? null : freshCurrent.versionKey);
        }
    }

    /**
     * The parallel two-way retire decision (GraphEngine.md §5/§6): idempotent no-op if the
     * current version is already Stale/SoftDeleted/Purged (or absent), otherwise a new
     * version carrying state = Stale.
     */
    private void applyRetires(List<OI_GraphMutation> retires, Boolean isEdgeFlavor, OI_IngestDelta delta) {
        if (retires.isEmpty()) {
            return;
        }
        Set<String> keys = new Set<String>();
        for (OI_GraphMutation mutation : retires) {
            keys.add(isEdgeFlavor ? mutation.edgeKey : mutation.nodeKey);
        }
        Map<String, OI_VersionRecord> currentByKey = repository.getCurrentVersions(keys, isEdgeFlavor);

        for (OI_GraphMutation mutation : retires) {
            String key = isEdgeFlavor ? mutation.edgeKey : mutation.nodeKey;
            OI_VersionRecord current = currentByKey.get(key);
            /** An idempotent no-op retire genuinely changed nothing, so it must not invalidate anything either — same reasoning as the liveness-touch branch in applyUpserts. */
            if (isRetireNoOp(current)) {
                continue;
            }
            commitRetireWithRetry(mutation, isEdgeFlavor, current);
            recordChange(mutation, isEdgeFlavor, delta);
        }
    }

    private Boolean isRetireNoOp(OI_VersionRecord current) {
        return current == null || current.state == 'Stale' || current.state == 'SoftDeleted' || current.state == 'Purged';
    }

    /** Same GE-2c retry shape as commitUpsertWithRetry, applied to the retire decision. */
    private void commitRetireWithRetry(OI_GraphMutation mutation, Boolean isEdgeFlavor, OI_VersionRecord current) {
        try {
            commitRetiredVersion(mutation, current);
        } catch (OI_ConcurrencyException e) {
            String key = isEdgeFlavor ? mutation.edgeKey : mutation.nodeKey;
            OI_VersionRecord freshCurrent = repository.getCurrentVersions(new Set<String>{ key }, isEdgeFlavor).get(key);
            if (isRetireNoOp(freshCurrent)) {
                return;
            }
            commitRetiredVersion(mutation, freshCurrent);
        }
    }

    private void commitRetiredVersion(OI_GraphMutation mutation, OI_VersionRecord current) {
        Integer nextVersionNumber = current.versionNumber + 1;
        OI_VersionRecord retiredVersion = new OI_VersionRecord(
            current.key,
            current.key + '::v' + nextVersionNumber,
            nextVersionNumber,
            current.typeKey,
            current.label,
            current.secondaryKey,
            current.parentKey,
            current.attributes,
            current.checksum,
            'Stale',
            current.graphScope,
            mutation.scanRunId,
            mutation.scanRunId,
            true,
            current.sourceKey,
            current.targetKey
        );
        repository.commitVersion(retiredVersion, current.versionKey);
    }

    private void commitVersionFor(OI_GraphMutation mutation, Integer versionNumber, Boolean isEdgeFlavor, String supersededVersionKey) {
        String key = isEdgeFlavor ? mutation.edgeKey : mutation.nodeKey;
        OI_VersionRecord newVersion = new OI_VersionRecord(
            key,
            key + '::v' + versionNumber,
            versionNumber,
            mutation.typeKey,
            mutation.label,
            mutation.secondaryKey,
            mutation.parentKey,
            mutation.attributes,
            mutation.checksum,
            'Active',
            mutation.graphScope,
            mutation.scanRunId,
            mutation.scanRunId,
            true,
            isEdgeFlavor ? mutation.sourceNodeKey : null,
            isEdgeFlavor ? mutation.targetNodeKey : null
        );
        repository.commitVersion(newVersion, supersededVersionKey);
    }

    /**
     * Generic graph-mechanics invariants only — never a domain rule (GraphEngine.md §7).
     */
    private void validate(OI_GraphMutation mutation) {
        Boolean isEdge =
            mutation.mutationType == OI_GraphMutation.MutationType.UPSERT_EDGE || mutation.mutationType == OI_GraphMutation.MutationType.RETIRE_EDGE;
        String key = isEdge ? mutation.edgeKey : mutation.nodeKey;
        if (String.isBlank(key)) {
            throw new OI_ValidationException('Graph mutation is missing a required key.');
        }
        if (mutation.mutationType == OI_GraphMutation.MutationType.UPSERT_EDGE) {
            if (String.isBlank(mutation.sourceNodeKey) || String.isBlank(mutation.targetNodeKey)) {
                throw new OI_ValidationException('UpsertEdge mutation ' + mutation.edgeKey + ' is missing a source or target node key.');
            }
            Boolean allowSelfLoop = mutation.attributes.containsKey('allowSelfLoop') && mutation.attributes.get('allowSelfLoop') == true;
            if (mutation.sourceNodeKey == mutation.targetNodeKey && !allowSelfLoop) {
                throw new OI_ValidationException('UpsertEdge mutation ' + mutation.edgeKey + ' is a self-loop without an explicit allowSelfLoop attribute.');
            }
        }
    }
}
