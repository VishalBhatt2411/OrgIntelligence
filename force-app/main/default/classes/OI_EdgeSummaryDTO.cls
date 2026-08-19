/**
 * Purpose: The @AuraEnabled wire shape for OI_EdgeSummary (API.md §2.1).
 * Responsibilities: Carry exactly key/typeKey/sourceNodeKey/targetNodeKey.
 * Dependencies: OI_EdgeSummary.
 * Limitations: None.
 */
public class OI_EdgeSummaryDTO {
    @AuraEnabled
    public String edgeKey;
    @AuraEnabled
    public String typeKey;
    @AuraEnabled
    public String sourceNodeKey;
    @AuraEnabled
    public String targetNodeKey;

    public OI_EdgeSummaryDTO(OI_EdgeSummary summary) {
        this.edgeKey = summary.edgeKey;
        this.typeKey = summary.typeKey;
        this.sourceNodeKey = summary.sourceNodeKey;
        this.targetNodeKey = summary.targetNodeKey;
    }

    /** Record Analysis (ADR-0021) — same rationale as OI_NodeSummaryDTO's raw-field constructor. */
    public OI_EdgeSummaryDTO(String edgeKey, String typeKey, String sourceNodeKey, String targetNodeKey) {
        this.edgeKey = edgeKey;
        this.typeKey = typeKey;
        this.sourceNodeKey = sourceNodeKey;
        this.targetNodeKey = targetNodeKey;
    }
}
