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
            EDGE_SCOPE_PREDICATE +
            ' GROUP BY Edge_Type__c';
        for (AggregateResult row : Database.query(query)) {
            counts.put((String) row.get('typeKey'), (Integer) row.get('total'));
        }
        return counts;
    }

    /**
     * The single scope predicate every per-node edge read shares, extracted as one constant
     * precisely so a summary COUNT and its drill-down ROW SET can never disagree.
     *
     * This matters more than it looks: the Intelligence panel promises that clicking
     * "Outgoing — Has Field 22" shows exactly those 22 rows. If the count query and the row
     * query each spelled their own WHERE clause, one could later gain an `AND State__c =
     * 'Active'` (or lose `Is_Current__c`) and the product would start lying — a count that does
     * not match its own detail is worse than no drill-down at all, because it silently
     * undermines every other number on the panel. Sharing the text makes that drift impossible
     * rather than merely unlikely.
     */
    private static final String EDGE_SCOPE_PREDICATE = ' = :nodeKey AND Is_Current__c = true';

    /** Outgoing edges of exactly one type for one node, keyset-paginated. Same scope as countCurrentBySourceKeyGroupedByType by construction. */
    public List<OI_Graph_Edge__c> selectCurrentPageBySourceKeyAndType(String nodeKey, String edgeTypeKey, Set<String> neighbourKeyFilter, String cursor, Integer pageSize) {
        return selectCurrentPageByType('Source_Node_Key__c', 'Target_Node_Key__c', nodeKey, edgeTypeKey, neighbourKeyFilter, cursor, pageSize);
    }

    /** Incoming edges of exactly one type for one node, keyset-paginated. Same scope as countCurrentByTargetKeyGroupedByType by construction. */
    public List<OI_Graph_Edge__c> selectCurrentPageByTargetKeyAndType(String nodeKey, String edgeTypeKey, Set<String> neighbourKeyFilter, String cursor, Integer pageSize) {
        return selectCurrentPageByType('Target_Node_Key__c', 'Source_Node_Key__c', nodeKey, edgeTypeKey, neighbourKeyFilter, cursor, pageSize);
    }

    /**
     * Keyset pagination on Edge_Key__c rather than OFFSET: OFFSET is capped at 2000 in SOQL and
     * degrades as it grows, whereas an indexed key cursor stays constant-cost at any depth — the
     * same technique selectCurrentKeysByType already uses. Ordering by Edge_Key__c also makes
     * paging stable across requests even as the graph is rescanned, since it does not depend on
     * a mutable field.
     *
     * neighbourKeyFilter, when supplied, restricts to a pre-resolved set of neighbour node keys.
     * That is how searching by neighbour LABEL is achieved without loading every edge: the label
     * lives on the node row, not the edge row, so the node side is narrowed first and the edge
     * query is then bounded by its result (see OI_NodeConnectionsService).
     */
    private List<OI_Graph_Edge__c> selectCurrentPageByType(
        String anchorKeyField,
        String neighbourKeyField,
        String nodeKey,
        String edgeTypeKey,
        Set<String> neighbourKeyFilter,
        String cursor,
        Integer pageSize
    ) {
        if (String.isBlank(nodeKey) || String.isBlank(edgeTypeKey)) {
            return new List<OI_Graph_Edge__c>();
        }
        Integer effectivePageSize = pageSize == null || pageSize <= 0 ? 200 : pageSize;
        String query =
            'SELECT ' +
            String.join(DETAIL_FIELDS, ', ') +
            ' FROM OI_Graph_Edge__c WHERE ' +
            anchorKeyField +
            EDGE_SCOPE_PREDICATE +
            ' AND Edge_Type__c = :edgeTypeKey';
        if (neighbourKeyFilter != null) {
            query += ' AND ' + neighbourKeyField + ' IN :neighbourKeyFilter';
        }
        if (String.isNotBlank(cursor)) {
            query += ' AND Edge_Key__c > :cursor';
        }
        query += ' ORDER BY Edge_Key__c ASC LIMIT :effectivePageSize';
        return Database.query(query);
    }

    /** Exact count for one (direction, edgeType) pair, optionally narrowed to a neighbour set — the filtered total a searching drill-down reports. Same scope predicate as the row query above. */
    public Integer countCurrentByKeyAndType(Boolean isOutgoing, String nodeKey, String edgeTypeKey, Set<String> neighbourKeyFilter) {
        if (String.isBlank(nodeKey) || String.isBlank(edgeTypeKey)) {
            return 0;
        }
        String anchorKeyField = isOutgoing == true ? 'Source_Node_Key__c' : 'Target_Node_Key__c';
        String neighbourKeyField = isOutgoing == true ? 'Target_Node_Key__c' : 'Source_Node_Key__c';
        String query =
            'SELECT COUNT() FROM OI_Graph_Edge__c WHERE ' +
            anchorKeyField +
            EDGE_SCOPE_PREDICATE +
            ' AND Edge_Type__c = :edgeTypeKey';
        if (neighbourKeyFilter != null) {
            query += ' AND ' + neighbourKeyField + ' IN :neighbourKeyFilter';
        }
        return Database.countQuery(query);
    }
}
