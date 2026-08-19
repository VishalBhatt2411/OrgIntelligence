/**
 * Purpose: Live, non-persisted read of one record's parent lookups and child relationships
 *          (Record Analysis, ADR-0021 / Backlog RA-1) — never written to
 *          OI_Graph_Node__c/OI_Graph_Edge__c, and never routed through OI_GraphEngine.
 *          Persisting arbitrary record rows into the metadata graph would corrupt its
 *          versioning/volume assumptions (ADR-0021), so this is a deliberately separate,
 *          parallel read path.
 * Responsibilities: Resolve the center record's own populated lookup fields to their target
 *                    records (via runtime Id-based SObjectType resolution, so polymorphic
 *                    lookups like OwnerId resolve correctly without special-casing); resolve
 *                    the object's child relationships to a bounded sample of child records;
 *                    return the result shaped like a graph fragment. Every node's secondaryKey
 *                    is set to the record's own Object API name alone (never the record Id) —
 *                    oiGraphNode renders secondaryKey as the card's visible caption, so this is
 *                    what lets a user tell an Account card apart from a Contact card on sight;
 *                    the Id remains available via nodeKey and the detail panel.
 * Dependencies: OI_RecordSchemaUtil, OI_RecordFragmentDTO, OI_NodeSummaryDTO,
 *               OI_EdgeSummaryDTO.
 * Limitations: Governor-limit bounded by design, not merely by accident — every populated
 *              lookup on the center record and every one of an object's child relationships
 *              (Account alone can have 60+) would otherwise mean one SOQL call each,
 *              risking the 100-query-per-transaction ceiling on exactly the kind of hub
 *              object this feature exists to visualize. Parent lookups are batched per
 *              distinct target SObjectType (one query per type, not per field). Child
 *              relationships are capped at MAX_RELATIONSHIP_TYPES processed and
 *              MAX_CHILDREN_PER_RELATIONSHIP rows each; both caps surface as an honest
 *              hasMore = true rather than a silent truncation (CLAUDE.md "no silent caps").
 */
public with sharing class OI_RecordHierarchyService {
    private static final Integer MAX_CHILDREN_PER_RELATIONSHIP = 10;
    private static final Integer MAX_RELATIONSHIP_TYPES = 25;
    private static final String PARENT_EDGE_TYPE_KEY = 'SalesforceRecord.LOOKUP_TO';
    private static final String CHILD_EDGE_TYPE_KEY = 'SalesforceRecord.CHILD_OF';

    public OI_RecordFragmentDTO getRecordFragment(String objectApiName, String recordId) {
        Schema.DescribeSObjectResult describe = OI_RecordSchemaUtil.describeAccessibleObject(objectApiName);
        Id validatedRecordId = OI_RecordSchemaUtil.validateRecordIdForObject(describe, recordId);

        SObject centerRecord = queryCenterRecord(describe, validatedRecordId);
        if (centerRecord == null) {
            return new OI_RecordFragmentDTO(null, new List<OI_NodeSummaryDTO>(), new List<OI_EdgeSummaryDTO>(), false);
        }

        String centerKey = OI_RecordSchemaUtil.recordNodeKey(describe.getName(), String.valueOf(validatedRecordId));
        List<OI_NodeSummaryDTO> nodes = new List<OI_NodeSummaryDTO>();
        List<OI_EdgeSummaryDTO> edges = new List<OI_EdgeSummaryDTO>();

        String centerNameField = OI_RecordSchemaUtil.resolveNameField(describe);
        String centerLabel = centerNameField == null ? recordId : OI_RecordSchemaUtil.labelFor(centerRecord, centerNameField);
        nodes.add(new OI_NodeSummaryDTO(centerKey, OI_RecordSchemaUtil.recordTypeKey(describe.getName()), centerLabel, describe.getName(), 'Active'));

        addParentLookups(describe, centerRecord, centerKey, nodes, edges);
        Boolean hasMore = addChildRelationships(describe, String.valueOf(validatedRecordId), centerKey, nodes, edges);

        return new OI_RecordFragmentDTO(centerKey, nodes, edges, hasMore);
    }

    /** One query, selecting every accessible reference field alongside the center row itself — never one query per lookup field. */
    private SObject queryCenterRecord(Schema.DescribeSObjectResult describe, String recordId) {
        Set<String> selectFields = new Set<String>{ 'Id' };
        String nameField = OI_RecordSchemaUtil.resolveNameField(describe);
        if (nameField != null) {
            selectFields.add(nameField);
        }
        for (Schema.SObjectField field : describe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE && fieldDescribe.isAccessible()) {
                selectFields.add(fieldDescribe.getName());
            }
        }
        String soql = 'SELECT ' + String.join(new List<String>(selectFields), ', ') + ' FROM ' + describe.getName() + ' WHERE Id = :recordId LIMIT 1';
        List<SObject> rows = Database.query(soql, AccessLevel.USER_MODE);
        return rows.isEmpty() ? null : rows[0];
    }

    /** Batched per distinct target SObjectType (resolved from the actual Id value, not the field's static referenceTo — correct for polymorphic lookups like OwnerId with zero special-casing), never one query per field. */
    private void addParentLookups(Schema.DescribeSObjectResult describe, SObject centerRecord, String centerKey, List<OI_NodeSummaryDTO> nodes, List<OI_EdgeSummaryDTO> edges) {
        Map<Schema.SObjectType, Set<Id>> idsByType = new Map<Schema.SObjectType, Set<Id>>();
        for (Schema.SObjectField field : describe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (fieldDescribe.getType() != Schema.DisplayType.REFERENCE || !fieldDescribe.isAccessible()) {
                continue;
            }
            Object rawValue;
            try {
                rawValue = centerRecord.get(fieldDescribe.getName());
            } catch (SObjectException e) {
                continue;
            }
            if (rawValue == null) {
                continue;
            }
            Id targetId = (Id) rawValue;
            Schema.SObjectType targetType = targetId.getSObjectType();
            if (targetType == null) {
                continue;
            }
            if (!idsByType.containsKey(targetType)) {
                idsByType.put(targetType, new Set<Id>());
            }
            idsByType.get(targetType).add(targetId);
        }

        for (Schema.SObjectType targetType : idsByType.keySet()) {
            Schema.DescribeSObjectResult targetDescribe = targetType.getDescribe();
            if (!targetDescribe.isAccessible() || !targetDescribe.isQueryable()) {
                continue;
            }
            String targetNameField = OI_RecordSchemaUtil.resolveNameField(targetDescribe);
            if (targetNameField == null) {
                continue;
            }
            Set<Id> ids = idsByType.get(targetType);
            String soql = 'SELECT Id, ' + targetNameField + ' FROM ' + targetDescribe.getName() + ' WHERE Id IN :ids';
            List<SObject> related;
            try {
                related = Database.query(soql, AccessLevel.USER_MODE);
            } catch (QueryException e) {
                /** A describe-listed field can still be unqueryable in practice (feature-gated objects, edition quirks) — CLAUDE.md §Metadata Assumptions: skip this one target type rather than fail the whole hierarchy. */
                continue;
            }
            for (SObject relatedRecord : related) {
                String relatedId = (String) relatedRecord.get('Id');
                String relatedKey = OI_RecordSchemaUtil.recordNodeKey(targetDescribe.getName(), relatedId);
                nodes.add(
                    new OI_NodeSummaryDTO(
                        relatedKey,
                        OI_RecordSchemaUtil.recordTypeKey(targetDescribe.getName()),
                        OI_RecordSchemaUtil.labelFor(relatedRecord, targetNameField),
                        targetDescribe.getName(),
                        'Active'
                    )
                );
                edges.add(new OI_EdgeSummaryDTO(centerKey + '::' + relatedKey, PARENT_EDGE_TYPE_KEY, centerKey, relatedKey));
            }
        }
    }

    /** Bounded on two axes at once (relationship types processed, rows per relationship) — see class doc for why both bounds are load-bearing, not cosmetic. Returns true if either bound was hit. */
    private Boolean addChildRelationships(Schema.DescribeSObjectResult describe, String recordId, String centerKey, List<OI_NodeSummaryDTO> nodes, List<OI_EdgeSummaryDTO> edges) {
        List<Schema.ChildRelationship> relationships = describe.getChildRelationships();
        Boolean hasMore = relationships.size() > MAX_RELATIONSHIP_TYPES;
        Integer relationshipsProcessed = 0;

        for (Schema.ChildRelationship relationship : relationships) {
            if (relationshipsProcessed >= MAX_RELATIONSHIP_TYPES) {
                break;
            }
            Schema.SObjectType childType = relationship.getChildSObject();
            Schema.SObjectField relationshipField = relationship.getField();
            if (childType == null || relationshipField == null) {
                continue;
            }
            Schema.DescribeSObjectResult childDescribe = childType.getDescribe();
            if (!childDescribe.isAccessible() || !childDescribe.isQueryable()) {
                continue;
            }
            String childNameField = OI_RecordSchemaUtil.resolveNameField(childDescribe);
            if (childNameField == null || !relationshipField.getDescribe().isAccessible()) {
                continue;
            }
            relationshipsProcessed++;

            Integer fetchLimit = MAX_CHILDREN_PER_RELATIONSHIP + 1;
            String soql =
                'SELECT Id, ' +
                childNameField +
                ' FROM ' +
                childDescribe.getName() +
                ' WHERE ' +
                relationshipField.getDescribe().getName() +
                ' = :recordId LIMIT :fetchLimit';
            List<SObject> children;
            try {
                children = Database.query(soql, AccessLevel.USER_MODE);
            } catch (QueryException e) {
                /** Same rationale as addParentLookups' catch — a relationship listed in describe metadata is not a guarantee it's actually queryable in this org/edition (CLAUDE.md §Metadata Assumptions). */
                continue;
            }

            Integer count = 0;
            for (SObject child : children) {
                if (count >= MAX_CHILDREN_PER_RELATIONSHIP) {
                    hasMore = true;
                    break;
                }
                String childId = (String) child.get('Id');
                String childKey = OI_RecordSchemaUtil.recordNodeKey(childDescribe.getName(), childId);
                nodes.add(
                    new OI_NodeSummaryDTO(
                        childKey,
                        OI_RecordSchemaUtil.recordTypeKey(childDescribe.getName()),
                        OI_RecordSchemaUtil.labelFor(child, childNameField),
                        childDescribe.getName(),
                        'Active'
                    )
                );
                edges.add(new OI_EdgeSummaryDTO(centerKey + '::' + childKey, CHILD_EDGE_TYPE_KEY, centerKey, childKey));
                count++;
            }
        }
        return hasMore;
    }
}
