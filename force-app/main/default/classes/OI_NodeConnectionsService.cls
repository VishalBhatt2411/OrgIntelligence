/**
 * Purpose: Answers "show me exactly the N things behind that number" — the paginated drill-down
 *          behind every count the Intelligence panel displays.
 * Responsibilities: For one (node, direction, edge type) selection, return a bounded page of
 *                    display-ready rows plus the exact total, resolving neighbour labels and
 *                    relationship wording through the Presentation Registry.
 * Dependencies: OI_EdgeSelector, OI_NodeSelector, OI_Edge_Type_Descriptor__mdt,
 *               OI_Node_Type_Descriptor__mdt.
 *
 * The contract that makes the drill-down trustworthy: a category here is exactly a
 * (direction, edgeTypeKey) pair — the same pair the panel's summary already displays as
 * "Outgoing — Has Field 22". Both the count and these rows go through
 * OI_EdgeSelector's single shared scope predicate, so the drill-down cannot show a different
 * set than the number that opened it. A count that disagrees with its own detail would
 * discredit every other figure on the panel, so this is enforced structurally rather than by
 * convention.
 *
 * Why the node side is queried first when searching: an edge row carries keys, not labels, so
 * "search these connections by name" cannot be expressed as a filter on the edge query alone.
 * Loading every edge and filtering in memory is not an option either (an object can have tens of
 * thousands of field edges). So a search narrows the NODE side first — bounded — and the edge
 * query is then restricted to those keys. The reported total becomes the filtered total, and the
 * payload flags itself as filtered so the UI never presents it as the unfiltered whole.
 *
 * Limitations: Sorting is deliberately NOT done here. Ordering is by edge key, which is what
 *              makes keyset pagination stable and constant-cost at any depth; a server-side sort
 *              by neighbour label would require ordering by a field on a different object than
 *              the one being paged. The client sorts within the rows it has loaded and says so,
 *              which is honest, rather than implying a global ordering it does not have.
 *              Field-specific columns (data type, referenced object) are populated from the
 *              neighbour node's own scanned attributes and are null for non-field rows — never
 *              blank placeholders, so the table can omit columns that carry no meaning.
 */
public inherited sharing class OI_NodeConnectionsService {
    public static final String DIRECTION_OUTGOING = 'outgoing';
    public static final String DIRECTION_INCOMING = 'incoming';
    private static final Integer DEFAULT_PAGE_SIZE = 100;
    private static final Integer MAX_PAGE_SIZE = 500;
    /** Ceiling on how many label-matching nodes a search resolves before restricting the edge query. Bounded so a one-character search cannot become an unbounded scan; the UI reports the result as filtered, so a truncated candidate set never masquerades as complete. */
    private static final Integer SEARCH_CANDIDATE_CEILING = 2000;

    private final OI_EdgeSelector edgeSelector;
    private final OI_NodeSelector nodeSelector;

    public OI_NodeConnectionsService() {
        this(new OI_EdgeSelector(), new OI_NodeSelector());
    }

    public OI_NodeConnectionsService(OI_EdgeSelector edgeSelector, OI_NodeSelector nodeSelector) {
        this.edgeSelector = edgeSelector;
        this.nodeSelector = nodeSelector;
    }

    public OI_ConnectionPageDTO getConnections(String nodeKey, String direction, String edgeTypeKey, Integer pageSize, String cursor, String searchTerm) {
        if (String.isBlank(nodeKey)) {
            throw new OI_ValidationException('A node key is required to load connections.');
        }
        if (String.isBlank(edgeTypeKey)) {
            throw new OI_ValidationException('A relationship type is required to load connections.');
        }
        Boolean isOutgoing = resolveIsOutgoing(direction);
        Integer effectivePageSize = Math.min(pageSize == null || pageSize <= 0 ? DEFAULT_PAGE_SIZE : pageSize, MAX_PAGE_SIZE);

        Boolean isFiltered = String.isNotBlank(searchTerm);
        Set<String> neighbourKeyFilter = isFiltered ? resolveSearchCandidateKeys(searchTerm) : null;
        /** A search that matched nothing must short-circuit: passing an empty set into an IN clause would return everything on some platforms and nothing on others — neither is a defensible answer, so it is decided here explicitly. */
        if (isFiltered && neighbourKeyFilter.isEmpty()) {
            return new OI_ConnectionPageDTO(new List<OI_ConnectionPageDTO.Row>(), 0, false, null, true);
        }

        Integer totalCount = edgeSelector.countCurrentByKeyAndType(isOutgoing, nodeKey, edgeTypeKey, neighbourKeyFilter);
        List<OI_Graph_Edge__c> edges = isOutgoing
            ? edgeSelector.selectCurrentPageBySourceKeyAndType(nodeKey, edgeTypeKey, neighbourKeyFilter, cursor, effectivePageSize + 1)
            : edgeSelector.selectCurrentPageByTargetKeyAndType(nodeKey, edgeTypeKey, neighbourKeyFilter, cursor, effectivePageSize + 1);

        /** Fetching one extra row is how hasMore is known without a second COUNT against a moving target — the extra row is trimmed, never rendered. */
        Boolean hasMore = edges.size() > effectivePageSize;
        if (hasMore) {
            edges.remove(edges.size() - 1);
        }

        List<OI_ConnectionPageDTO.Row> rows = buildRows(edges, isOutgoing, edgeTypeKey);
        String nextCursor = hasMore && !edges.isEmpty() ? edges[edges.size() - 1].Edge_Key__c : null;
        return new OI_ConnectionPageDTO(rows, totalCount, hasMore, nextCursor, isFiltered);
    }

    private Boolean resolveIsOutgoing(String direction) {
        if (DIRECTION_OUTGOING.equalsIgnoreCase(direction)) {
            return true;
        }
        if (DIRECTION_INCOMING.equalsIgnoreCase(direction)) {
            return false;
        }
        throw new OI_ValidationException('Direction must be either "outgoing" or "incoming".');
    }

    /** Node keys whose label or API name matches the search term — the bounded first half of a label search (see the class doc comment). */
    private Set<String> resolveSearchCandidateKeys(String searchTerm) {
        Set<String> keys = new Set<String>();
        for (OI_Graph_Node__c node : nodeSelector.selectCurrentByLabelOrSecondaryKeyContains(searchTerm, SEARCH_CANDIDATE_CEILING)) {
            keys.add(node.Node_Key__c);
        }
        return keys;
    }

    /**
     * Turns edge rows into display-ready rows: one bulk read for every neighbour node (never one
     * per row), then relationship wording resolved from the registry so no Salesforce-specific
     * label is hardcoded here.
     */
    private List<OI_ConnectionPageDTO.Row> buildRows(List<OI_Graph_Edge__c> edges, Boolean isOutgoing, String edgeTypeKey) {
        List<OI_ConnectionPageDTO.Row> rows = new List<OI_ConnectionPageDTO.Row>();
        if (edges.isEmpty()) {
            return rows;
        }

        Set<String> neighbourKeys = new Set<String>();
        for (OI_Graph_Edge__c edge : edges) {
            neighbourKeys.add(isOutgoing ? edge.Target_Node_Key__c : edge.Source_Node_Key__c);
        }
        Map<String, OI_Graph_Node__c> nodeByKey = new Map<String, OI_Graph_Node__c>();
        for (OI_Graph_Node__c node : nodeSelector.selectCurrentByKeys(neighbourKeys)) {
            nodeByKey.put(node.Node_Key__c, node);
        }

        EdgeDisplay edgeDisplay = loadEdgeDisplay(edgeTypeKey);
        Map<String, String> nodeTypeLabels = loadNodeTypeLabels();

        for (OI_Graph_Edge__c edge : edges) {
            String neighbourKey = isOutgoing ? edge.Target_Node_Key__c : edge.Source_Node_Key__c;
            OI_Graph_Node__c neighbour = nodeByKey.get(neighbourKey);
            /**
             * A neighbour the running user cannot read, or one whose node row is genuinely
             * missing, is skipped rather than rendered as a placeholder row. Showing "(not
             * visible)" here would leak the existence of metadata the user has no access to; the
             * total count is deliberately left as the unfiltered graph count so the UI can show
             * fewer rows than the total rather than silently under-reporting the graph itself.
             */
            if (neighbour == null) {
                continue;
            }
            OI_ConnectionPageDTO.Row row = new OI_ConnectionPageDTO.Row(
                neighbour.Node_Key__c,
                neighbour.Label__c,
                neighbour.Secondary_Key__c,
                nodeTypeLabels.containsKey(neighbour.Node_Type__c) ? nodeTypeLabels.get(neighbour.Node_Type__c) : neighbour.Node_Type__c
            );
            row.relationshipLabel = edgeDisplay.displayLabel;
            /** The role is stated from the NEIGHBOUR's perspective: on an outgoing edge the neighbour is the target, so it carries the target role. Getting this backwards would tell a user "this object references the trigger", which is the opposite of the truth. */
            row.roleLabel = isOutgoing ? edgeDisplay.targetRole : edgeDisplay.sourceRole;
            row.direction = isOutgoing ? DIRECTION_OUTGOING : DIRECTION_INCOMING;
            applyNeighbourAttributes(row, neighbour);
            rows.add(row);
        }
        return rows;
    }

    /** Field-specific context, read from the neighbour's own scanned attributes. Left null for anything that is not a field, so the table can hide columns rather than show blanks. */
    private void applyNeighbourAttributes(OI_ConnectionPageDTO.Row row, OI_Graph_Node__c neighbour) {
        if (String.isBlank(neighbour.Attributes_Json__c)) {
            return;
        }
        try {
            Map<String, Object> attributes = (Map<String, Object>) JSON.deserializeUntyped(neighbour.Attributes_Json__c);
            row.dataType = stringOrNull(attributes.get('type'));
            row.referencedObject = stringOrNull(attributes.get('referenceTo'));
            row.viaFieldApiName = stringOrNull(attributes.get('relationshipName'));
            Object custom = attributes.get('custom');
            row.isCustom = custom instanceof Boolean ? (Boolean) custom : null;
        } catch (Exception ignored) {
            /** Malformed stored attributes must never break a drill-down — the row is still useful without its optional context columns. */
        }
    }

    private String stringOrNull(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private EdgeDisplay loadEdgeDisplay(String edgeTypeKey) {
        for (OI_Edge_Type_Descriptor__mdt descriptor : [
            SELECT Display_Label__c, Source_Role_Label__c, Target_Role_Label__c
            FROM OI_Edge_Type_Descriptor__mdt
            WHERE Type_Key__c = :edgeTypeKey
            LIMIT 1
        ]) {
            return new EdgeDisplay(descriptor.Display_Label__c, descriptor.Source_Role_Label__c, descriptor.Target_Role_Label__c);
        }
        /** An unregistered edge type degrades to a generic, non-technical wording rather than exposing the raw key — the same generic-default rule the rest of the registry follows (ADR-0011). */
        return new EdgeDisplay('Related', 'Related To', 'Related To');
    }

    private Map<String, String> loadNodeTypeLabels() {
        Map<String, String> labels = new Map<String, String>();
        for (OI_Node_Type_Descriptor__mdt descriptor : [SELECT Type_Key__c, Display_Label__c FROM OI_Node_Type_Descriptor__mdt]) {
            labels.put(descriptor.Type_Key__c, descriptor.Display_Label__c);
        }
        return labels;
    }

    private class EdgeDisplay {
        private final String displayLabel;
        private final String sourceRole;
        private final String targetRole;

        private EdgeDisplay(String displayLabel, String sourceRole, String targetRole) {
            this.displayLabel = String.isBlank(displayLabel) ? 'Related' : displayLabel;
            this.sourceRole = String.isBlank(sourceRole) ? 'Related To' : sourceRole;
            this.targetRole = String.isBlank(targetRole) ? 'Related To' : targetRole;
        }
    }
}
