/**
 * Purpose: Immutable domain value object representing one version of a graph node
 *          (GraphEngine.md §2).
 * Responsibilities: Carry node identity/content fields with zero Salesforce-metadata knowledge —
 *                    the Graph Engine's genericity requirement (GraphEngine.md §1) applies here
 *                    directly. "Changing" a node never mutates this instance; it returns a new one.
 * Dependencies: None — no Database.*, no Http*, no @AuraEnabled (Architecture.md §2).
 * Limitations: attributes is a shallow Map<String, Object> — the engine never inspects its
 *              contents (GraphEngine.md §2's schemaless-attribute-bag trade-off).
 */
public class OI_Node {
    public final String nodeKey;
    public final Integer versionNumber;
    public final String versionKey;
    public final String typeKey;
    public final String label;
    public final String secondaryKey;
    public final String parentKey;
    public final Map<String, Object> attributes;
    public final String checksum;
    public final String graphScope;
    public final String state;
    public final Id firstSeenRunId;
    public final Id lastSeenRunId;
    public final Boolean isCurrent;

    public OI_Node(
        String nodeKey,
        Integer versionNumber,
        String versionKey,
        String typeKey,
        String label,
        String secondaryKey,
        String parentKey,
        Map<String, Object> attributes,
        String checksum,
        String graphScope,
        String state,
        Id firstSeenRunId,
        Id lastSeenRunId,
        Boolean isCurrent
    ) {
        this.nodeKey = nodeKey;
        this.versionNumber = versionNumber;
        this.versionKey = versionKey;
        this.typeKey = typeKey;
        this.label = label;
        this.secondaryKey = secondaryKey;
        this.parentKey = parentKey;
        this.attributes = attributes == null ? new Map<String, Object>() : attributes;
        this.checksum = checksum;
        this.graphScope = graphScope;
        this.state = state;
        this.firstSeenRunId = firstSeenRunId;
        this.lastSeenRunId = lastSeenRunId;
        this.isCurrent = isCurrent;
    }

    /**
     * Returns a new OI_Node identical to this one except for lastSeenRunId — the one
     * narrow, engine-owned bookkeeping change (GraphEngine.md §2) that never implies a
     * new version. Never mutates this instance.
     */
    public OI_Node withLastSeenRun(Id runId) {
        return new OI_Node(
            this.nodeKey,
            this.versionNumber,
            this.versionKey,
            this.typeKey,
            this.label,
            this.secondaryKey,
            this.parentKey,
            this.attributes,
            this.checksum,
            this.graphScope,
            this.state,
            this.firstSeenRunId,
            runId,
            this.isCurrent
        );
    }

    /**
     * Returns a new OI_Node identical to this one except for isCurrent — set false on the
     * row being superseded by OI_GraphRepository.commitVersion. Never mutates this instance.
     */
    public OI_Node withIsCurrent(Boolean isCurrentFlag) {
        return new OI_Node(
            this.nodeKey,
            this.versionNumber,
            this.versionKey,
            this.typeKey,
            this.label,
            this.secondaryKey,
            this.parentKey,
            this.attributes,
            this.checksum,
            this.graphScope,
            this.state,
            this.firstSeenRunId,
            this.lastSeenRunId,
            isCurrentFlag
        );
    }
}
