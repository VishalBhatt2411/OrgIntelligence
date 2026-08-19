/**
 * Purpose: The generic version record both node-flavored and edge-flavored Repository calls
 *          pass through OI_GraphRepository's contract (GraphRepository.md §2).
 * Responsibilities: Carry graph-mechanics fields only (key/version/checksum/state/lifecycle) —
 *                    domain-agnostic by design (GraphRepository.md §1). sourceKey/targetKey are
 *                    populated only when this record is edge-flavored; isEdge() is the one
 *                    graph-theory-vocabulary dispatch condition Storage Providers use
 *                    (GraphRepository.md §5) — never a Salesforce-specific type check.
 * Dependencies: None.
 * Limitations: A single shape for both flavors, deliberately, to avoid duplicating the
 *              five-operation Repository contract a second time (GraphRepository.md §23).
 */
public class OI_VersionRecord {
    public final String key;
    public final String versionKey;
    public final Integer versionNumber;
    public final String typeKey;
    public final String label;
    public final String secondaryKey;
    public final String parentKey;
    public final Map<String, Object> attributes;
    public final String checksum;
    public final String state;
    public final String graphScope;
    public final Id firstSeenRunId;
    public final Id lastSeenRunId;
    public final Boolean isCurrent;
    public final String sourceKey;
    public final String targetKey;

    public OI_VersionRecord(
        String key,
        String versionKey,
        Integer versionNumber,
        String typeKey,
        String label,
        String secondaryKey,
        String parentKey,
        Map<String, Object> attributes,
        String checksum,
        String state,
        String graphScope,
        Id firstSeenRunId,
        Id lastSeenRunId,
        Boolean isCurrent,
        String sourceKey,
        String targetKey
    ) {
        this.key = key;
        this.versionKey = versionKey;
        this.versionNumber = versionNumber;
        this.typeKey = typeKey;
        this.label = label;
        this.secondaryKey = secondaryKey;
        this.parentKey = parentKey;
        this.attributes = attributes == null ? new Map<String, Object>() : attributes;
        this.checksum = checksum;
        this.state = state;
        this.graphScope = graphScope;
        this.firstSeenRunId = firstSeenRunId;
        this.lastSeenRunId = lastSeenRunId;
        this.isCurrent = isCurrent;
        this.sourceKey = sourceKey;
        this.targetKey = targetKey;
    }

    /** True iff this record carries endpoint references — the edge/node dispatch condition. */
    public Boolean isEdge() {
        return this.sourceKey != null && this.targetKey != null;
    }
}
