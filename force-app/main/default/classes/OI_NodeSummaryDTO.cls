/**
 * Purpose: The @AuraEnabled wire shape for OI_NodeSummary (API.md §2.1) — Controllers
 *          never return the plain Graph Engine domain class directly across the LWC
 *          boundary.
 * Responsibilities: Carry exactly key/typeKey/label/secondaryKey/state — mirrors
 *                    OI_NodeSummary's own deliberate lazy-attribute-load rule
 *                    (GraphEngine.md §10); never the full attributes blob.
 * Dependencies: OI_NodeSummary.
 * Limitations: None.
 */
public class OI_NodeSummaryDTO {
    @AuraEnabled
    public String nodeKey;
    @AuraEnabled
    public String typeKey;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String secondaryKey;
    @AuraEnabled
    public String state;

    public OI_NodeSummaryDTO(OI_NodeSummary summary) {
        this.nodeKey = summary.nodeKey;
        this.typeKey = summary.typeKey;
        this.label = summary.label;
        this.secondaryKey = summary.secondaryKey;
        this.state = summary.state;
    }

    /** Sprint 10 — the minimal search path (OI_SearchController) maps directly from the Selector's sObject row, never exposing OI_Graph_Node__c itself across the LWC boundary. */
    public OI_NodeSummaryDTO(OI_Graph_Node__c node) {
        this.nodeKey = node.Node_Key__c;
        this.typeKey = node.Node_Type__c;
        this.label = node.Label__c;
        this.secondaryKey = node.Secondary_Key__c;
        this.state = node.State__c;
    }

    /** Record Analysis (ADR-0021) — records are never persisted as OI_Graph_Node__c rows, so OI_RecordHierarchyService builds this wire shape directly from a live query result; oiGraphCanvas/oiGraphNode render it unchanged either way. */
    public OI_NodeSummaryDTO(String nodeKey, String typeKey, String label, String secondaryKey, String state) {
        this.nodeKey = nodeKey;
        this.typeKey = typeKey;
        this.label = label;
        this.secondaryKey = secondaryKey;
        this.state = state;
    }
}
