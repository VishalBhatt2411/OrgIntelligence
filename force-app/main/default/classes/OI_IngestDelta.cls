/**
 * Purpose: What an ingest actually CHANGED, as opposed to what it merely observed — the value
 *          object OI_GraphBuilder returns so downstream consumers (today: Impact Analysis cache
 *          invalidation, DE-7) can react to real change without re-deriving it.
 * Responsibilities: Carry the node keys and edge keys that genuinely got a new version during
 *                    one ingest, plus the derived set of nodes whose IMPACT results those
 *                    changes invalidate. Pure data; no behavior beyond that derivation.
 *
 * Why this exists at all — the distinction that makes DE-7 correct rather than merely wired:
 * OI_MutationGenerator.translateAndIngest already returned the *observed* node keys, and it is
 * tempting to invalidate the impact cache against those. That would be wrong in both
 * directions at once:
 *   - Too broad: a full scan observes EVERY node of a type, almost all unchanged. Invalidating
 *     on observation flushes the entire cache on every scan, which makes the cache pointless
 *     (its whole purpose is surviving scans that changed nothing relevant).
 *   - Too narrow: it misses the case that matters most. Only OI_GraphBuilder knows which
 *     observations produced a new version (a real content change) versus a mere liveness touch
 *     (checksum identical) — see its applyUpserts three-way decision.
 *
 * Why edge changes drive NODE invalidation (impactedNodeKeys) — the subtle half:
 * Impact Analysis is a traversal over EDGES, so an edge change alters impact results for nodes
 * whose own content never changed. Concretely: class A starts calling class B. A's body changed
 * so A's node re-versions, but B's node is byte-identical — nothing about B changed. Yet B's
 * reverse-impact answer ("what depends on B?") is now different and its cached row is stale.
 * Invalidating only changed NODES would leave B serving a wrong answer indefinitely. So every
 * changed edge contributes BOTH of its endpoints to impactedNodeKeys. This is the specific
 * defect class DE-7 exists to prevent, and the reason this object reports a derived set rather
 * than just handing callers the raw changed keys.
 *
 * Limitations: A retired EDGE cannot contribute its endpoints, because OI_GraphMutation.
 *              retireEdge carries only an edgeKey — the endpoints are not on the mutation.
 *              This is currently harmless: nothing in the package emits retireEdge (cascading
 *              edge retirement is explicitly unbuilt, see OI_MutationGenerator's own
 *              Limitations), so no such delta can occur today. If cascading edge retirement is
 *              built, retireEdge must start carrying its endpoints or this invalidation will
 *              silently under-cover that case — recorded here rather than discovered later.
 */
public class OI_IngestDelta {
    /** Node keys that received a genuinely new version this ingest (content change, first discovery, or retirement) — never a liveness-only touch. */
    public final Set<String> changedNodeKeys;
    /** Edge keys that received a genuinely new version this ingest. */
    public final Set<String> changedEdgeKeys;
    /** Nodes whose cached Impact Analysis results are invalidated by this delta: every changed node, plus both endpoints of every changed edge (see this class's doc comment for why the second half is essential). */
    public final Set<String> impactedNodeKeys;

    public OI_IngestDelta() {
        this(new Set<String>(), new Set<String>(), new Set<String>());
    }

    public OI_IngestDelta(Set<String> changedNodeKeys, Set<String> changedEdgeKeys, Set<String> impactedNodeKeys) {
        this.changedNodeKeys = changedNodeKeys == null ? new Set<String>() : changedNodeKeys;
        this.changedEdgeKeys = changedEdgeKeys == null ? new Set<String>() : changedEdgeKeys;
        this.impactedNodeKeys = impactedNodeKeys == null ? new Set<String>() : impactedNodeKeys;
    }

    /** True when this ingest changed nothing at all — the common case for a rescan of an unchanged org, and the signal a caller uses to skip invalidation work entirely. */
    public Boolean isEmpty() {
        return changedNodeKeys.isEmpty() && changedEdgeKeys.isEmpty();
    }

    /** Merges another delta into this one — needed because a caller may ingest in several chunks across one logical scan task and must invalidate once against the union, not once per chunk. */
    public void addAll(OI_IngestDelta other) {
        if (other == null) {
            return;
        }
        this.changedNodeKeys.addAll(other.changedNodeKeys);
        this.changedEdgeKeys.addAll(other.changedEdgeKeys);
        this.impactedNodeKeys.addAll(other.impactedNodeKeys);
    }
}
