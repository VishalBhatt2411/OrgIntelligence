/**
 * Purpose: Query construction for OI_Graph_Node__c — the only class that writes SOQL
 *          against this object (CodingStandards.md §4).
 * Responsibilities: Bulk, key-set-shaped reads; centralizes the Is_Current__c = true
 *                    predicate (GraphEngine.md §13/§15/§21) so no caller can omit it by
 *                    accident. Returns sObjects/projections only, never a domain shape —
 *                    that mapping is OI_GraphRepository's job (GraphRepository.md §12).
 * Dependencies: OI_Graph_Node__c.
 * Limitations: Every method is bulk-shaped; there is no single-key overload that issues
 *              its own query (CodingStandards.md §4).
 */
public with sharing class OI_NodeSelector {
    private static final List<String> DETAIL_FIELDS = new List<String>{
        'Id',
        'Node_Key__c',
        'Node_Version_Key__c',
        'Version_Number__c',
        'Node_Type__c',
        'Label__c',
        'Secondary_Key__c',
        'Parent_Key__c',
        'Attributes_Json__c',
        'Checksum__c',
        'State__c',
        'Graph_Scope__c',
        'First_Seen_Run__c',
        'Last_Seen_Run__c',
        'Is_Current__c'
    };

    /**
     * Bulk lookup of the current version row for each key in the set. Keys with no
     * current version are simply absent from the result — not an error
     * (GraphRepository.md §2).
     */
    public List<OI_Graph_Node__c> selectCurrentByKeys(Set<String> nodeKeys) {
        if (nodeKeys == null || nodeKeys.isEmpty()) {
            return new List<OI_Graph_Node__c>();
        }
        String query =
            'SELECT ' +
            String.join(DETAIL_FIELDS, ', ') +
            ' FROM OI_Graph_Node__c WHERE Node_Key__c IN :nodeKeys AND Is_Current__c = true';
        return Database.query(query);
    }

    /**
     * Minimal node lookup by label/secondaryKey prefix (Sprint 10) — a deliberately small
     * substitute for the full, unbuilt SearchEngine.md epic (no SOSL multi-domain ranking,
     * no record search, no provider abstraction), sufficient only for oiSearchBar to find
     * a starting node for the graph. LIKE, not SOSL, since this is a simple prefix match
     * over two fields on one object, not the multi-object relevance search SearchEngine.md
     * specifies for a future sprint.
     */
    public List<OI_Graph_Node__c> selectCurrentByLabelOrSecondaryKeyPrefix(String queryTerm, Integer maxResults) {
        String likeTerm = String.escapeSingleQuotes(queryTerm) + '%';
        Integer effectiveMax = maxResults == null ? 20 : maxResults;
        String query =
            'SELECT ' +
            String.join(DETAIL_FIELDS, ', ') +
            ' FROM OI_Graph_Node__c WHERE Is_Current__c = true AND (Label__c LIKE :likeTerm OR Secondary_Key__c LIKE :likeTerm) ' +
            'ORDER BY Label__c ASC LIMIT :effectiveMax';
        return Database.query(query);
    }

    /**
     * Keyset-paginated, key-only projection of every currently-Active key for a given
     * typeKey — the enumeration retire-detection needs (GraphRepository.md §2, §9, §12).
     * Deliberately field-minimal: no Attributes_Json__c, no Label__c.
     */
    public List<OI_Graph_Node__c> selectCurrentKeysByType(String typeKey, String cursorVersionKey, Integer pageSize) {
        Integer effectivePageSize = pageSize == null ? 200 : pageSize;
        String query =
            'SELECT Id, Node_Key__c, Node_Version_Key__c FROM OI_Graph_Node__c ' +
            'WHERE Node_Type__c = :typeKey AND Is_Current__c = true AND State__c = \'Active\'';
        if (String.isNotBlank(cursorVersionKey)) {
            query += ' AND Node_Version_Key__c > :cursorVersionKey';
        }
        query += ' ORDER BY Node_Version_Key__c ASC LIMIT :effectivePageSize';
        return Database.query(query);
    }
}
