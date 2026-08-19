/**
 * Purpose: Read-only hierarchy traversal — ancestors, descendants, path, and a record's
 *          cross-definition hierarchy membership (FR-008/009/010/012). Never writes.
 * Responsibilities: getAncestors — walk upward one relationship row at a time (a record has
 *                    at most one active parent per hierarchy unless Allow_Multiple_Parents__c,
 *                    in which case the first found is followed — full multi-parent ancestor
 *                    fan-out is a documented Limitation, not attempted this pass).
 *                    getDescendants — bulk, ring-based BFS (one query per ring, never per
 *                    node), bounded by both Max_Levels__c and a node-count ceiling.
 *                    getPath — the ancestor chain, root-first, joined into a display string
 *                    (FR-012). getHierarchyMembership — every active relationship a record
 *                    participates in across ALL definitions (FR-008's Record 360 view).
 * Dependencies: OI_HierarchyDefinitionSelector, OI_HierarchyRelationshipSelector.
 * Limitations: getAncestors follows a single parent chain even when Allow_Multiple_Parents__c
 *              is true — a record with genuinely multiple concurrent parents has multiple
 *              ancestor chains, and this method surfaces only one (the first relationship row
 *              found); a full multi-parent ancestor fan-out is real, undesigned future work,
 *              not silently broken today (a single valid chain is still returned, never an
 *              error). getDescendants' node-count ceiling mirrors the Graph Engine's own
 *              "no silent caps" honesty principle (GraphUI.md §26) — hitting it is reported,
 *              not silently truncated.
 */
public with sharing class OI_HierarchyQueryService {
    private static final Integer DEFAULT_MAX_LEVELS = 10;
    private static final Integer MAX_DESCENDANT_NODE_COUNT = 500;

    private final OI_HierarchyDefinitionSelector definitionSelector;
    private final OI_HierarchyRelationshipSelector relationshipSelector;

    public OI_HierarchyQueryService() {
        this(new OI_HierarchyDefinitionSelector(), new OI_HierarchyRelationshipSelector());
    }

    public OI_HierarchyQueryService(OI_HierarchyDefinitionSelector definitionSelector, OI_HierarchyRelationshipSelector relationshipSelector) {
        this.definitionSelector = definitionSelector;
        this.relationshipSelector = relationshipSelector;
    }

    /** FR-009: every ancestor of a record, nearest first, within one definition — bounded by Max_Levels__c. */
    public List<OI_Hierarchy_Relationship__c> getAncestors(Id definitionId, String childObjectApiName, String childRecordId) {
        OI_Hierarchy_Definition__c definition = requireDefinition(definitionId);
        List<OI_Hierarchy_Relationship__c> ancestors = new List<OI_Hierarchy_Relationship__c>();
        String currentObjectApiName = childObjectApiName;
        String currentRecordId = childRecordId;
        Integer hops = 0;
        Integer maxLevels = safeMaxLevels(definition);
        while (hops < maxLevels) {
            List<OI_Hierarchy_Relationship__c> ownRow = relationshipSelector.selectActiveByChild(definitionId, currentObjectApiName, currentRecordId);
            if (ownRow.isEmpty() || String.isBlank(ownRow[0].Parent_Record_Id__c)) {
                break;
            }
            OI_Hierarchy_Relationship__c link = ownRow[0];
            ancestors.add(link);
            currentObjectApiName = link.Parent_Object_Api_Name__c;
            currentRecordId = link.Parent_Record_Id__c;
            hops++;
        }
        return ancestors;
    }

    /**
     * FR-010: every descendant of a record within one definition — a bulk, ring-based BFS
     * (one query per ring via selectActiveByParentIds, never one query per node), bounded by
     * both Max_Levels__c and MAX_DESCENDANT_NODE_COUNT. hasMore is honestly reported, never a
     * silent truncation.
     */
    public OI_HierarchyDescendantsResult getDescendants(Id definitionId, String parentRecordId) {
        OI_Hierarchy_Definition__c definition = requireDefinition(definitionId);
        List<OI_Hierarchy_Relationship__c> descendants = new List<OI_Hierarchy_Relationship__c>();
        Set<String> currentRing = new Set<String>{ parentRecordId };
        Set<String> visited = new Set<String>{ parentRecordId };
        Integer hops = 0;
        Integer maxLevels = safeMaxLevels(definition);
        Boolean hasMore = false;

        while (!currentRing.isEmpty() && hops < maxLevels) {
            List<OI_Hierarchy_Relationship__c> ring = relationshipSelector.selectActiveByParentIds(definitionId, currentRing);
            Set<String> nextRing = new Set<String>();
            for (OI_Hierarchy_Relationship__c link : ring) {
                if (visited.contains(link.Child_Record_Id__c)) {
                    continue;
                }
                descendants.add(link);
                visited.add(link.Child_Record_Id__c);
                nextRing.add(link.Child_Record_Id__c);
                if (descendants.size() >= MAX_DESCENDANT_NODE_COUNT) {
                    hasMore = true;
                    return new OI_HierarchyDescendantsResult(descendants, true);
                }
            }
            currentRing = nextRing;
            hops++;
        }
        return new OI_HierarchyDescendantsResult(descendants, hasMore || !currentRing.isEmpty());
    }

    /** FR-012: the root-first path for one record, e.g. "Global Enterprise / North America / USA / ABC Motors" — reuses getAncestors, just reversed and rendered. */
    public List<OI_Hierarchy_Relationship__c> getPath(Id definitionId, String childObjectApiName, String childRecordId) {
        List<OI_Hierarchy_Relationship__c> ancestors = getAncestors(definitionId, childObjectApiName, childRecordId);
        List<OI_Hierarchy_Relationship__c> rootFirst = new List<OI_Hierarchy_Relationship__c>();
        for (Integer i = ancestors.size() - 1; i >= 0; i--) {
            rootFirst.add(ancestors[i]);
        }
        return rootFirst;
    }

    /** FR-008: every hierarchy (across all definitions) this record currently participates in — the Record 360 view. */
    public List<OI_Hierarchy_Relationship__c> getHierarchyMembership(String objectApiName, String recordId) {
        return relationshipSelector.selectActiveByRecordAcrossDefinitions(objectApiName, recordId);
    }

    private OI_Hierarchy_Definition__c requireDefinition(Id definitionId) {
        OI_Hierarchy_Definition__c definition = definitionSelector.selectById(definitionId);
        if (definition == null) {
            throw new OI_ValidationException('Unknown hierarchy definition.');
        }
        return definition;
    }

    private Integer safeMaxLevels(OI_Hierarchy_Definition__c definition) {
        return definition.Max_Levels__c == null ? DEFAULT_MAX_LEVELS : Integer.valueOf(definition.Max_Levels__c);
    }
}
