/**
 * Purpose: Aggregate structural edge-count-by-type summary for one node, split by direction
 *          (GraphUI.md §7) — backs the Detail Panel's relationship summary and the honest,
 *          structural-edges-only "directly connected" count used in place of a real
 *          Impact/Dependency Engine (Roadmap Phase 4, not yet built — see
 *          OI_GraphEngine.getRelationshipCounts).
 * Responsibilities: Carry outgoing/incoming edge counts grouped by Edge_Type__c; total().
 * Dependencies: None.
 * Limitations: Counts reflect only currently-Active structural edges this platform has
 *              actually scanned (HAS_FIELD/LOOKUP_TO/MASTER_DETAIL_TO today) — never Apex,
 *              Flow, or Trigger dependencies, which no scanner discovers yet.
 */
public class OI_RelationshipCounts {
    @AuraEnabled
    public Map<String, Integer> outgoingByType;
    @AuraEnabled
    public Map<String, Integer> incomingByType;

    public OI_RelationshipCounts(Map<String, Integer> outgoingByType, Map<String, Integer> incomingByType) {
        this.outgoingByType = outgoingByType == null ? new Map<String, Integer>() : outgoingByType;
        this.incomingByType = incomingByType == null ? new Map<String, Integer>() : incomingByType;
    }

    public Integer total() {
        Integer sum = 0;
        for (Integer count : outgoingByType.values()) {
            sum += count;
        }
        for (Integer count : incomingByType.values()) {
            sum += count;
        }
        return sum;
    }
}
