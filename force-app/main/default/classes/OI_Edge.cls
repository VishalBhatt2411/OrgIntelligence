/**
 * Purpose: Immutable domain value object representing one version of a graph edge
 *          (GraphEngine.md §3).
 * Responsibilities: Carry edge identity/content fields. Edges are always directed
 *                    (GraphEngine.md §3) — a symmetric relationship is two OI_Edge instances,
 *                    never a "symmetric" flag on one.
 * Dependencies: None.
 * Limitations: sourceNodeKey/targetNodeKey reference the logical OI_Node.nodeKey, never a
 *              specific node version (GraphEngine.md §3).
 */
public class OI_Edge {
    public final String edgeKey;
    public final Integer versionNumber;
    public final String versionKey;
    public final String typeKey;
    public final String sourceNodeKey;
    public final String targetNodeKey;
    public final Map<String, Object> attributes;
    public final Decimal weight;
    public final String state;
    public final String graphScope;
    public final Id firstSeenRunId;
    public final Id lastSeenRunId;
    public final Boolean isCurrent;

    public OI_Edge(
        String edgeKey,
        Integer versionNumber,
        String versionKey,
        String typeKey,
        String sourceNodeKey,
        String targetNodeKey,
        Map<String, Object> attributes,
        Decimal weight,
        String state,
        String graphScope,
        Id firstSeenRunId,
        Id lastSeenRunId,
        Boolean isCurrent
    ) {
        this.edgeKey = edgeKey;
        this.versionNumber = versionNumber;
        this.versionKey = versionKey;
        this.typeKey = typeKey;
        this.sourceNodeKey = sourceNodeKey;
        this.targetNodeKey = targetNodeKey;
        this.attributes = attributes == null ? new Map<String, Object>() : attributes;
        this.weight = weight;
        this.state = state;
        this.graphScope = graphScope;
        this.firstSeenRunId = firstSeenRunId;
        this.lastSeenRunId = lastSeenRunId;
        this.isCurrent = isCurrent;
    }

    /** Returns a new OI_Edge identical to this one except for lastSeenRunId. */
    public OI_Edge withLastSeenRun(Id runId) {
        return new OI_Edge(
            this.edgeKey,
            this.versionNumber,
            this.versionKey,
            this.typeKey,
            this.sourceNodeKey,
            this.targetNodeKey,
            this.attributes,
            this.weight,
            this.state,
            this.graphScope,
            this.firstSeenRunId,
            runId,
            this.isCurrent
        );
    }

    /** Returns a new OI_Edge identical to this one except for isCurrent. */
    public OI_Edge withIsCurrent(Boolean isCurrentFlag) {
        return new OI_Edge(
            this.edgeKey,
            this.versionNumber,
            this.versionKey,
            this.typeKey,
            this.sourceNodeKey,
            this.targetNodeKey,
            this.attributes,
            this.weight,
            this.state,
            this.graphScope,
            this.firstSeenRunId,
            this.lastSeenRunId,
            isCurrentFlag
        );
    }
}
