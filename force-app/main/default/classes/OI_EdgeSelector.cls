/**
 * Purpose: Query construction for OI_Graph_Edge__c — the only class that writes SOQL
 *          against this object (CodingStandards.md §4).
 * Responsibilities: Mirrors OI_NodeSelector exactly, for edges.
 * Dependencies: OI_Graph_Edge__c.
 * Limitations: Every method is bulk-shaped.
 */
public with sharing class OI_EdgeSelector {
    private static final List<String> DETAIL_FIELDS = new List<String>{
        'Id',
        'Edge_Key__c',
        'Edge_Version_Key__c',
        'Version_Number__c',
        'Edge_Type__c',
        'Source_Node_Key__c',
        'Target_Node_Key__c',
        'Weight__c',
        'Attributes_Json__c',
        'State__c',
        'Graph_Scope__c',
        'First_Seen_Run__c',
        'Last_Seen_Run__c',
        'Is_Current__c'
    };

    /** Bulk lookup of the current version row for each edge key in the set. */
    public List<OI_Graph_Edge__c> selectCurrentByKeys(Set<String> edgeKeys) {
        if (edgeKeys == null || edgeKeys.isEmpty()) {
            return new List<OI_Graph_Edge__c>();
        }
        String query =
            'SELECT ' +
            String.join(DETAIL_FIELDS, ', ') +
            ' FROM OI_Graph_Edge__c WHERE Edge_Key__c IN :edgeKeys AND Is_Current__c = true';
        return Database.query(query);
    }

    /** Keyset-paginated, key-only projection of every currently-Active edge key for a typeKey. */
    public List<OI_Graph_Edge__c> selectCurrentKeysByType(String typeKey, String cursorVersionKey, Integer pageSize) {
        Integer effectivePageSize = pageSize == null ? 200 : pageSize;
        String query =
            'SELECT Id, Edge_Key__c, Edge_Version_Key__c FROM OI_Graph_Edge__c ' +
            'WHERE Edge_Type__c = :typeKey AND Is_Current__c = true AND State__c = \'Active\'';
        if (String.isNotBlank(cursorVersionKey)) {
            query += ' AND Edge_Version_Key__c > :cursorVersionKey';
        }
        query += ' ORDER BY Edge_Version_Key__c ASC LIMIT :effectivePageSize';
        return Database.query(query);
    }

    /** Bulk lookup of current edges by source node key — used for neighbor expansion. */
    public List<OI_Graph_Edge__c> selectCurrentBySourceKeys(Set<String> sourceNodeKeys) {
        if (sourceNodeKeys == null || sourceNodeKeys.isEmpty()) {
            return new List<OI_Graph_Edge__c>();
        }
        String query =
            'SELECT ' +
            String.join(DETAIL_FIELDS, ', ') +
            ' FROM OI_Graph_Edge__c WHERE Source_Node_Key__c IN :sourceNodeKeys AND Is_Current__c = true';
        return Database.query(query);
    }

    /** Bulk lookup of current edges by target node key — used for reverse neighbor expansion. */
    public List<OI_Graph_Edge__c> selectCurrentByTargetKeys(Set<String> targetNodeKeys) {
        if (targetNodeKeys == null || targetNodeKeys.isEmpty()) {
            return new List<OI_Graph_Edge__c>();
        }
        String query =
            'SELECT ' +
            String.join(DETAIL_FIELDS, ', ') +
            ' FROM OI_Graph_Edge__c WHERE Target_Node_Key__c IN :targetNodeKeys AND Is_Current__c = true';
        return Database.query(query);
    }

    /**
     * Aggregate outgoing edge counts by Edge_Type__c for one node — a single GROUP BY query,
     * never full row loads, backing the Detail Panel's structural relationship summary
     * (OI_RelationshipCounts) without the cost of selectCurrentBySourceKeys' full-row shape.
     */
    public Map<String, Integer> countCurrentBySourceKeyGroupedByType(String sourceNodeKey) {
        return countGroupedByType('Source_Node_Key__c', sourceNodeKey);
    }

    /** Aggregate incoming edge counts by Edge_Type__c for one node — mirrors countCurrentBySourceKeyGroupedByType. */
    public Map<String, Integer> countCurrentByTargetKeyGroupedByType(String targetNodeKey) {
        return countGroupedByType('Target_Node_Key__c', targetNodeKey);
    }

    /** keyField is always one of the two literal column names above — never caller-supplied, so this dynamic SOQL carries no injection risk. */
    private Map<String, Integer> countGroupedByType(String keyField, String nodeKey) {
        Map<String, Integer> counts = new Map<String, Integer>();
        if (String.isBlank(nodeKey)) {
            return counts;
        }
        String query =
            'SELECT Edge_Type__c typeKey, COUNT(Id) total FROM OI_Graph_Edge__c WHERE ' +
            keyField +
            ' = :nodeKey AND Is_Current__c = true GROUP BY Edge_Type__c';
        for (AggregateResult row : Database.query(query)) {
            counts.put((String) row.get('typeKey'), (Integer) row.get('total'));
        }
        return counts;
    }
}
