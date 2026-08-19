/**
 * Purpose: Query construction for OI_Hierarchy_Relationship__c — the only class that writes
 *          SOQL against this object (CodingStandards.md §4).
 * Responsibilities: Bulk reads keyed by definition, by child, by parent, or by a pre-matched
 *                    record-Id candidate set — the access patterns OI_HierarchyValidationService
 *                    (circular detection), OI_HierarchyQueryService (ancestors/descendants/path),
 *                    and OI_HierarchySearchService (FR-011) each need. Runs with sharing
 *                    (ADR-0022).
 * Dependencies: OI_Hierarchy_Relationship__c.
 * Limitations: Every method is bulk-shaped. selectActiveByDefinitionId loads the full
 *              current-relationship set for one definition into memory — acceptable for
 *              circular-relationship detection (bounded by realistic hierarchy sizes, never
 *              the metadata graph's own tens-of-thousands-of-rows scale) but not a pattern to
 *              reuse for anything that could grow unbounded.
 */
public with sharing class OI_HierarchyRelationshipSelector {
    private static final List<String> RELATIONSHIP_FIELDS = new List<String>{
        'Id',
        'Name',
        'Hierarchy_Definition__c',
        'Hierarchy_Level__c',
        'Parent_Object_Api_Name__c',
        'Parent_Record_Id__c',
        'Child_Object_Api_Name__c',
        'Child_Record_Id__c',
        'Effective_Start_Date__c',
        'Effective_End_Date__c',
        'Is_Active__c',
        'Relationship_Type__c',
        'Relationship_Key__c'
    };

    public OI_Hierarchy_Relationship__c selectByKey(String relationshipKey) {
        if (String.isBlank(relationshipKey)) {
            return null;
        }
        List<OI_Hierarchy_Relationship__c> rows = Database.query(
            'SELECT ' + String.join(RELATIONSHIP_FIELDS, ', ') + ' FROM OI_Hierarchy_Relationship__c WHERE Relationship_Key__c = :relationshipKey LIMIT 1'
        );
        return rows.isEmpty() ? null : rows[0];
    }

    /** The full current (active or inactive) relationship set for one definition — used by OI_HierarchyValidationService's in-memory circular-relationship walk (never per-row recursive SOQL). */
    public List<OI_Hierarchy_Relationship__c> selectAllByDefinitionId(Id definitionId) {
        if (definitionId == null) {
            return new List<OI_Hierarchy_Relationship__c>();
        }
        return Database.query('SELECT ' + String.join(RELATIONSHIP_FIELDS, ', ') + ' FROM OI_Hierarchy_Relationship__c WHERE Hierarchy_Definition__c = :definitionId');
    }

    /** Every active relationship where the given record is the CHILD — a record's current parent(s) within one definition (FR-004: more than one only when Allow_Multiple_Parents__c is true). */
    public List<OI_Hierarchy_Relationship__c> selectActiveByChild(Id definitionId, String childObjectApiName, String childRecordId) {
        if (definitionId == null || String.isBlank(childRecordId)) {
            return new List<OI_Hierarchy_Relationship__c>();
        }
        return Database.query(
            'SELECT ' +
            String.join(RELATIONSHIP_FIELDS, ', ') +
            ' FROM OI_Hierarchy_Relationship__c WHERE Hierarchy_Definition__c = :definitionId AND Child_Object_Api_Name__c = :childObjectApiName AND Child_Record_Id__c = :childRecordId AND Is_Active__c = true'
        );
    }

    /** Every active relationship where the given record is the PARENT — a record's current direct children within one definition (descendant traversal, one hop at a time). */
    public List<OI_Hierarchy_Relationship__c> selectActiveByParent(Id definitionId, String parentObjectApiName, String parentRecordId) {
        if (definitionId == null || String.isBlank(parentRecordId)) {
            return new List<OI_Hierarchy_Relationship__c>();
        }
        return Database.query(
            'SELECT ' +
            String.join(RELATIONSHIP_FIELDS, ', ') +
            ' FROM OI_Hierarchy_Relationship__c WHERE Hierarchy_Definition__c = :definitionId AND Parent_Object_Api_Name__c = :parentObjectApiName AND Parent_Record_Id__c = :parentRecordId AND Is_Active__c = true'
        );
    }

    /** Bulk ring-fetch for descendant traversal (OI_HierarchyQueryService.getDescendants) — every active child of ANY record in parentRecordIds, in one query per ring rather than one query per node (CLAUDE.md's bulkification rule). Filters by record Id membership only, not object API name, since Salesforce record Ids are globally unique across objects by their key prefix — safe even across a multi-object hierarchy level. */
    public List<OI_Hierarchy_Relationship__c> selectActiveByParentIds(Id definitionId, Set<String> parentRecordIds) {
        if (definitionId == null || parentRecordIds == null || parentRecordIds.isEmpty()) {
            return new List<OI_Hierarchy_Relationship__c>();
        }
        return Database.query(
            'SELECT ' +
            String.join(RELATIONSHIP_FIELDS, ', ') +
            ' FROM OI_Hierarchy_Relationship__c WHERE Hierarchy_Definition__c = :definitionId AND Parent_Record_Id__c IN :parentRecordIds AND Is_Active__c = true'
        );
    }

    /** Root-level relationships (no parent) within one definition — the starting frontier for a full-hierarchy tree render. */
    public List<OI_Hierarchy_Relationship__c> selectActiveRootsByDefinitionId(Id definitionId) {
        if (definitionId == null) {
            return new List<OI_Hierarchy_Relationship__c>();
        }
        return Database.query(
            'SELECT ' +
            String.join(RELATIONSHIP_FIELDS, ', ') +
            ' FROM OI_Hierarchy_Relationship__c WHERE Hierarchy_Definition__c = :definitionId AND Parent_Record_Id__c = null AND Is_Active__c = true'
        );
    }

    /** Every relationship within one definition where any of the given record Ids appears as Parent OR Child (FR-011: Hierarchy Search) — a single OR'd query is safe here, unlike selectActiveByRecordAcrossDefinitions, because recordIds is already a small, pre-matched candidate set (bounded by OI_HierarchySearchService's own result cap), not an unbounded scan. hierarchyLevelId/includeInactive are optional narrowing facets (FR-011's "Hierarchy Level"/"Status"); both default to unfiltered when null/false. */
    public List<OI_Hierarchy_Relationship__c> selectByDefinitionAndRecordIds(Id definitionId, Set<String> recordIds, Id hierarchyLevelId, Boolean includeInactive) {
        if (definitionId == null || recordIds == null || recordIds.isEmpty()) {
            return new List<OI_Hierarchy_Relationship__c>();
        }
        String soql =
            'SELECT ' +
            String.join(RELATIONSHIP_FIELDS, ', ') +
            ' FROM OI_Hierarchy_Relationship__c' +
            ' WHERE Hierarchy_Definition__c = :definitionId' +
            ' AND (Parent_Record_Id__c IN :recordIds OR Child_Record_Id__c IN :recordIds)';
        if (hierarchyLevelId != null) {
            soql += ' AND Hierarchy_Level__c = :hierarchyLevelId';
        }
        if (includeInactive != true) {
            soql += ' AND Is_Active__c = true';
        }
        return Database.query(soql);
    }

    /** Every active relationship a record participates in across ALL definitions, as either parent or child — "which hierarchies does this record belong to" (FR-008's Record 360 view). Two queries, never one OR'd query per CLAUDE.md's bulk-safety-over-cleverness precedent elsewhere in this codebase (e.g. OI_GraphTraversal.collectRing). */
    public List<OI_Hierarchy_Relationship__c> selectActiveByRecordAcrossDefinitions(String objectApiName, String recordId) {
        if (String.isBlank(recordId)) {
            return new List<OI_Hierarchy_Relationship__c>();
        }
        Map<Id, OI_Hierarchy_Relationship__c> byId = new Map<Id, OI_Hierarchy_Relationship__c>(
            (List<OI_Hierarchy_Relationship__c>) Database.query(
                'SELECT ' +
                String.join(RELATIONSHIP_FIELDS, ', ') +
                ' FROM OI_Hierarchy_Relationship__c WHERE Child_Object_Api_Name__c = :objectApiName AND Child_Record_Id__c = :recordId AND Is_Active__c = true'
            )
        );
        byId.putAll(
            (List<OI_Hierarchy_Relationship__c>) Database.query(
                'SELECT ' +
                String.join(RELATIONSHIP_FIELDS, ', ') +
                ' FROM OI_Hierarchy_Relationship__c WHERE Parent_Object_Api_Name__c = :objectApiName AND Parent_Record_Id__c = :recordId AND Is_Active__c = true'
            )
        );
        return byId.values();
    }
}
