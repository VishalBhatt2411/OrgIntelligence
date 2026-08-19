/**
 * Purpose: The generic ingestion contract OI_GraphBuilder consumes (GraphEngine.md §7) —
 *          an observation, never a storage instruction.
 * Responsibilities: Represent exactly one of UpsertNode/RetireNode/UpsertEdge/RetireEdge via
 *                    named static factories, keeping the Builder's input shape stable
 *                    regardless of which per-type Scanner or OI_MutationGenerator produced it.
 * Dependencies: None.
 * Limitations: Field population differs by mutationType — callers use the matching factory
 *              rather than the constructor directly, and OI_GraphBuilder branches on
 *              mutationType, never on which fields happen to be populated.
 *              scanRunId (Sprint 8 addition): GraphEngine.md §2 requires the Builder to
 *              stamp firstSeenRunId/lastSeenRunId on every version it writes, but neither
 *              GraphEngine.md §7's Mutation table nor the Sprint 7 shape of this class
 *              carried a run identifier for it to use — a real, if narrow, contract gap.
 *              scanRunId closes it: OI_MutationGenerator populates it from the
 *              OI_Scan_Task__c -> OI_Scan_Run__c the Discovery Batch belongs to.
 */
public class OI_GraphMutation {
    public enum MutationType {
        UPSERT_NODE,
        RETIRE_NODE,
        UPSERT_EDGE,
        RETIRE_EDGE
    }

    public final MutationType mutationType;
    public final String nodeKey;
    public final String edgeKey;
    public final String typeKey;
    public final String label;
    public final String secondaryKey;
    public final String parentKey;
    public final String sourceNodeKey;
    public final String targetNodeKey;
    public final Map<String, Object> attributes;
    public final String checksum;
    public final Decimal weight;
    public final String graphScope;
    public final Id scanRunId;

    private OI_GraphMutation(
        MutationType mutationType,
        String nodeKey,
        String edgeKey,
        String typeKey,
        String label,
        String secondaryKey,
        String parentKey,
        String sourceNodeKey,
        String targetNodeKey,
        Map<String, Object> attributes,
        String checksum,
        Decimal weight,
        String graphScope,
        Id scanRunId
    ) {
        this.mutationType = mutationType;
        this.nodeKey = nodeKey;
        this.edgeKey = edgeKey;
        this.typeKey = typeKey;
        this.label = label;
        this.secondaryKey = secondaryKey;
        this.parentKey = parentKey;
        this.sourceNodeKey = sourceNodeKey;
        this.targetNodeKey = targetNodeKey;
        this.attributes = attributes == null ? new Map<String, Object>() : attributes;
        this.checksum = checksum;
        this.weight = weight;
        this.graphScope = graphScope;
        this.scanRunId = scanRunId;
    }

    public static OI_GraphMutation upsertNode(
        String nodeKey,
        String typeKey,
        String label,
        String secondaryKey,
        String parentKey,
        Map<String, Object> attributes,
        String checksum,
        String graphScope,
        Id scanRunId
    ) {
        return new OI_GraphMutation(
            MutationType.UPSERT_NODE,
            nodeKey,
            null,
            typeKey,
            label,
            secondaryKey,
            parentKey,
            null,
            null,
            attributes,
            checksum,
            null,
            graphScope,
            scanRunId
        );
    }

    public static OI_GraphMutation retireNode(String nodeKey, Id scanRunId) {
        return new OI_GraphMutation(
            MutationType.RETIRE_NODE,
            nodeKey,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            scanRunId
        );
    }

    public static OI_GraphMutation upsertEdge(
        String edgeKey,
        String typeKey,
        String sourceNodeKey,
        String targetNodeKey,
        Map<String, Object> attributes,
        String checksum,
        Decimal weight,
        String graphScope,
        Id scanRunId
    ) {
        return new OI_GraphMutation(
            MutationType.UPSERT_EDGE,
            null,
            edgeKey,
            typeKey,
            null,
            null,
            null,
            sourceNodeKey,
            targetNodeKey,
            attributes,
            checksum,
            weight,
            graphScope,
            scanRunId
        );
    }

    public static OI_GraphMutation retireEdge(String edgeKey, Id scanRunId) {
        return new OI_GraphMutation(
            MutationType.RETIRE_EDGE,
            null,
            edgeKey,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            scanRunId
        );
    }
}
