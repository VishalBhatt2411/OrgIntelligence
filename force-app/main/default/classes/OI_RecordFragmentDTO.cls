/**
 * Purpose: The @AuraEnabled wire shape for a record's live hierarchy fragment (Record
 *          Analysis, ADR-0021 / Backlog RA-2) — deliberately shaped like OI_GraphFragmentDTO
 *          (same field names) rather than reusing it, since a record fragment is never a
 *          metadata graph fragment: it is a separate class so oiGraphCanvas/oiGraphNode can
 *          render it unchanged without this platform's Graph Engine ever being involved.
 * Responsibilities: Carry centerNodeKey/nodes/edges/hasMore — nothing else.
 * Dependencies: OI_NodeSummaryDTO, OI_EdgeSummaryDTO.
 * Limitations: No pageCursor/frontier — record hierarchy pagination is a per-relationship
 *              "more of this type exists" signal (hasMore), not a resumable cursor.
 */
public class OI_RecordFragmentDTO {
    @AuraEnabled
    public String centerNodeKey;
    @AuraEnabled
    public List<OI_NodeSummaryDTO> nodes;
    @AuraEnabled
    public List<OI_EdgeSummaryDTO> edges;
    @AuraEnabled
    public Boolean hasMore;

    public OI_RecordFragmentDTO(String centerNodeKey, List<OI_NodeSummaryDTO> nodes, List<OI_EdgeSummaryDTO> edges, Boolean hasMore) {
        this.centerNodeKey = centerNodeKey;
        this.nodes = nodes;
        this.edges = edges;
        this.hasMore = hasMore;
    }
}
