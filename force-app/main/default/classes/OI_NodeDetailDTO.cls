/**
 * Purpose: The @AuraEnabled wire shape for a single node's full detail (API.md §2.1) —
 *          backs oiNodeDetailPanel's getNodeDetail call, the only path that ever carries
 *          full attributes across the LWC boundary (GraphEngine.md §10).
 * Responsibilities: Map OI_VersionRecord's node-flavored fields into a DTO.
 * Dependencies: OI_VersionRecord.
 * Limitations: Constructed only from a node-flavored OI_VersionRecord (isEdge() == false);
 *              the caller is responsible for that check.
 */
public class OI_NodeDetailDTO {
    @AuraEnabled
    public String nodeKey;
    @AuraEnabled
    public String typeKey;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String secondaryKey;
    @AuraEnabled
    public String parentKey;
    @AuraEnabled
    public Map<String, Object> attributes;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Id lastSeenRunId;
    @AuraEnabled
    public Map<String, Integer> outgoingRelationshipCounts;
    @AuraEnabled
    public Map<String, Integer> incomingRelationshipCounts;
    @AuraEnabled
    public Integer directConnectionCount;

    public OI_NodeDetailDTO(OI_VersionRecord version) {
        this.nodeKey = version.key;
        this.typeKey = version.typeKey;
        this.label = version.label;
        this.secondaryKey = version.secondaryKey;
        this.parentKey = version.parentKey;
        this.attributes = version.attributes;
        this.state = version.state;
        this.lastSeenRunId = version.lastSeenRunId;
    }

    /** Sprint (Hierarchy Visualizer realignment): adds the honest, structural-edges-only relationship summary (OI_RelationshipCounts) alongside the base node detail. */
    public OI_NodeDetailDTO(OI_VersionRecord version, OI_RelationshipCounts relationshipCounts) {
        this(version);
        this.outgoingRelationshipCounts = relationshipCounts.outgoingByType;
        this.incomingRelationshipCounts = relationshipCounts.incomingByType;
        this.directConnectionCount = relationshipCounts.total();
    }
}
