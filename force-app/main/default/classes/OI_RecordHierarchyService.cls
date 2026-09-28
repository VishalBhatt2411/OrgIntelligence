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
 *              lookup on the center record would otherwise mean one SOQL call each, risking the
 *              100-query-per-transaction ceiling on exactly the kind of hub object this feature
 *              exists to visualize. Parent lookups are batched per distinct target SObjectType
 *              (one query per type, not per field). Child relationships are batched into
 *              parent-to-children subqueries, up to CHILD_RELATIONSHIP_QUERY_BATCH_SIZE
 *              relationship types per SOQL call (Salesforce's documented per-query subquery
 *              ceiling, live-verified against this org), so MAX_RELATIONSHIP_TYPES can afford to
 *              be a generous safety ceiling rather than a tight bound driven by SOQL call count —
 *              a schema-heavy org with 200+ child relationship types on one object still costs
 *              roughly TYPES/20 queries, not TYPES queries. Rows per relationship are capped at
 *              MAX_CHILDREN_PER_RELATIONSHIP; both this cap and the (now rarely hit)
 *              MAX_RELATIONSHIP_TYPES cap surface as an honest hasMore = true rather than a
 *              silent truncation (CLAUDE.md "no silent caps").
 */
public with sharing class OI_RecordHierarchyService {
  private static final Integer MAX_CHILDREN_PER_RELATIONSHIP = 10;
  private static final Integer MAX_RELATIONSHIP_TYPES = 200;
  private static final Integer CHILD_RELATIONSHIP_QUERY_BATCH_SIZE = 20;
  private static final String PARENT_EDGE_TYPE_KEY = 'SalesforceRecord.LOOKUP_TO';
  private static final String CHILD_EDGE_TYPE_KEY = 'SalesforceRecord.CHILD_OF';

  public OI_RecordFragmentDTO getRecordFragment(
    String objectApiName,
    String recordId
  ) {
    Schema.DescribeSObjectResult describe = OI_RecordSchemaUtil.describeAccessibleObject(
      objectApiName
    );
    Id validatedRecordId = OI_RecordSchemaUtil.validateRecordIdForObject(
      describe,
      recordId
    );

    SObject centerRecord = queryCenterRecord(describe, validatedRecordId);
    if (centerRecord == null) {
      return new OI_RecordFragmentDTO(
        null,
        new List<OI_NodeSummaryDTO>(),
        new List<OI_EdgeSummaryDTO>(),
        false
      );
    }

    String centerKey = OI_RecordSchemaUtil.recordNodeKey(
      describe.getName(),
      String.valueOf(validatedRecordId)
    );
    List<OI_NodeSummaryDTO> nodes = new List<OI_NodeSummaryDTO>();
    List<OI_EdgeSummaryDTO> edges = new List<OI_EdgeSummaryDTO>();

    String centerNameField = OI_RecordSchemaUtil.resolveNameField(describe);
    String centerLabel = centerNameField == null
      ? recordId
      : OI_RecordSchemaUtil.labelFor(centerRecord, centerNameField);
    nodes.add(
      new OI_NodeSummaryDTO(
        centerKey,
        OI_RecordSchemaUtil.recordTypeKey(describe.getName()),
        centerLabel,
        describe.getName(),
        'Active'
      )
    );

    addParentLookups(describe, centerRecord, centerKey, nodes, edges);
    Boolean hasMore = addChildRelationships(
      describe,
      String.valueOf(validatedRecordId),
      centerKey,
      nodes,
      edges
    );
    OI_RecordOverviewDTO recordOverview = new OI_RecordOverviewDTO(
      resolveOwnerName(nodes, edges),
      datetimeValue(centerRecord, 'CreatedDate'),
      datetimeValue(centerRecord, 'LastModifiedDate')
    );

    return new OI_RecordFragmentDTO(
      centerKey,
      nodes,
      edges,
      hasMore,
      recordOverview
    );
  }

  /** One query, selecting every accessible reference field alongside the center row itself — never one query per lookup field. */
  private SObject queryCenterRecord(
    Schema.DescribeSObjectResult describe,
    String recordId
  ) {
    Set<String> selectFields = new Set<String>{ 'Id' };
    String nameField = OI_RecordSchemaUtil.resolveNameField(describe);
    if (nameField != null) {
      selectFields.add(nameField);
    }
    addAccessibleField(selectFields, describe, 'CreatedDate');
    addAccessibleField(selectFields, describe, 'LastModifiedDate');
    for (Schema.SObjectField field : describe.fields.getMap().values()) {
      Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
      if (
        fieldDescribe.getType() == Schema.DisplayType.REFERENCE &&
        fieldDescribe.isAccessible()
      ) {
        selectFields.add(fieldDescribe.getName());
      }
    }
    String soql =
      'SELECT ' +
      String.join(new List<String>(selectFields), ', ') +
      ' FROM ' +
      describe.getName() +
      ' WHERE Id = :recordId LIMIT 1';
    List<SObject> rows = Database.query(soql, AccessLevel.USER_MODE);
    return rows.isEmpty() ? null : rows[0];
  }

  /** Batched per distinct target SObjectType (resolved from the actual Id value, not the field's static referenceTo — correct for polymorphic lookups like OwnerId with zero special-casing), never one query per field. */
  private void addParentLookups(
    Schema.DescribeSObjectResult describe,
    SObject centerRecord,
    String centerKey,
    List<OI_NodeSummaryDTO> nodes,
    List<OI_EdgeSummaryDTO> edges
  ) {
    Map<Schema.SObjectType, Set<Id>> idsByType = new Map<Schema.SObjectType, Set<Id>>();
    Map<Id, Set<String>> fieldNamesByTargetId = new Map<Id, Set<String>>();
    for (Schema.SObjectField field : describe.fields.getMap().values()) {
      Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
      if (
        fieldDescribe.getType() != Schema.DisplayType.REFERENCE ||
        !fieldDescribe.isAccessible()
      ) {
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
      if (!fieldNamesByTargetId.containsKey(targetId)) {
        fieldNamesByTargetId.put(targetId, new Set<String>());
      }
      fieldNamesByTargetId.get(targetId).add(fieldDescribe.getName());
    }

    for (Schema.SObjectType targetType : idsByType.keySet()) {
      Schema.DescribeSObjectResult targetDescribe = targetType.getDescribe();
      if (!targetDescribe.isAccessible() || !targetDescribe.isQueryable()) {
        continue;
      }
      String targetNameField = OI_RecordSchemaUtil.resolveNameField(
        targetDescribe
      );
      if (targetNameField == null) {
        continue;
      }
      Set<Id> ids = idsByType.get(targetType);
      String soql =
        'SELECT Id, ' +
        targetNameField +
        ' FROM ' +
        targetDescribe.getName() +
        ' WHERE Id IN :ids';
      List<SObject> related;
      try {
        related = Database.query(soql, AccessLevel.USER_MODE);
      } catch (QueryException e) {
        /** A describe-listed field can still be unqueryable in practice (feature-gated objects, edition quirks) — CLAUDE.md §Metadata Assumptions: skip this one target type rather than fail the whole hierarchy. */
        continue;
      }
      for (SObject relatedRecord : related) {
        String relatedId = (String) relatedRecord.get('Id');
        String relatedKey = OI_RecordSchemaUtil.recordNodeKey(
          targetDescribe.getName(),
          relatedId
        );
        nodes.add(
          new OI_NodeSummaryDTO(
            relatedKey,
            OI_RecordSchemaUtil.recordTypeKey(targetDescribe.getName()),
            OI_RecordSchemaUtil.labelFor(relatedRecord, targetNameField),
            targetDescribe.getName(),
            'Active'
          )
        );
        for (
          String fieldApiName : fieldNamesByTargetId.get(
            (Id) relatedRecord.get('Id')
          )
        ) {
          OI_EdgeSummaryDTO parentEdge = new OI_EdgeSummaryDTO(
            centerKey + '::' + fieldApiName + '::' + relatedKey,
            PARENT_EDGE_TYPE_KEY,
            centerKey,
            relatedKey
          );
          parentEdge.viaFieldApiName = fieldApiName;
          edges.add(parentEdge);
        }
      }
    }
  }

  /**
   * Bounded on two axes at once (relationship types processed, rows per relationship) — see
   * class doc for why both bounds are load-bearing, not cosmetic. Returns true if either bound
   * was hit.
   *
   * Queries relationship types in batches of up to CHILD_RELATIONSHIP_QUERY_BATCH_SIZE using one
   * parent-to-children SOQL query per batch (a subquery per relationship type in that batch),
   * rather than the one-query-per-relationship-type approach this method used before. That
   * earlier approach forced MAX_RELATIONSHIP_TYPES down to 25 purely to bound SOQL call count —
   * which, in a schema-heavy org (this org's Account has 219 total child relationships, 123
   * eligible after describe-level accessibility filtering), silently buried near-universal
   * relationships like Contact (alphabetically 37th) behind describe metadata's platform-internal
   * ordering. Batching relationships into subqueries (live-verified against this org: 20
   * subqueries in one query succeeds — Salesforce's documented per-query subquery ceiling) means
   * covering all 123 eligible relationship types here costs ~7 SOQL calls instead of 123,
   * letting MAX_RELATIONSHIP_TYPES be raised to a generous safety ceiling that in practice is
   * never hit, rather than a heuristic prioritization standing in for real coverage.
   */
  private Boolean addChildRelationships(
    Schema.DescribeSObjectResult describe,
    String recordId,
    String centerKey,
    List<OI_NodeSummaryDTO> nodes,
    List<OI_EdgeSummaryDTO> edges
  ) {
    List<EligibleChildRelationship> eligible = new List<EligibleChildRelationship>();
    for (
      Schema.ChildRelationship relationship : describe.getChildRelationships()
    ) {
      String relationshipName = relationship.getRelationshipName();
      Schema.SObjectType childType = relationship.getChildSObject();
      Schema.SObjectField relationshipField = relationship.getField();
      if (
        relationshipName == null ||
        childType == null ||
        relationshipField == null
      ) {
        /** A relationship with no queryable relationship name (some system/junction relationships) can't be used in a subquery and was never resolvable by the prior single-query approach either. */
        continue;
      }
      Schema.DescribeSObjectResult childDescribe = childType.getDescribe();
      if (!childDescribe.isAccessible() || !childDescribe.isQueryable()) {
        continue;
      }
      String childNameField = OI_RecordSchemaUtil.resolveNameField(
        childDescribe
      );
      if (
        childNameField == null ||
        !relationshipField.getDescribe().isAccessible()
      ) {
        continue;
      }
      eligible.add(
        new EligibleChildRelationship(
          relationshipName,
          childDescribe,
          relationshipField,
          childNameField
        )
      );
    }

    Boolean hasMore = eligible.size() > MAX_RELATIONSHIP_TYPES;
    Integer typesToProcess = Math.min(eligible.size(), MAX_RELATIONSHIP_TYPES);
    Integer fetchLimit = MAX_CHILDREN_PER_RELATIONSHIP + 1;

    for (
      Integer batchStart = 0;
      batchStart < typesToProcess;
      batchStart += CHILD_RELATIONSHIP_QUERY_BATCH_SIZE
    ) {
      Integer batchEnd = Math.min(
        batchStart + CHILD_RELATIONSHIP_QUERY_BATCH_SIZE,
        typesToProcess
      );
      List<EligibleChildRelationship> batch = new List<EligibleChildRelationship>();
      List<String> subqueries = new List<String>();
      for (Integer i = batchStart; i < batchEnd; i++) {
        EligibleChildRelationship candidate = eligible[i];
        batch.add(candidate);
        subqueries.add(
          '(SELECT Id, ' +
            candidate.childNameField +
            ' FROM ' +
            candidate.relationshipName +
            ' LIMIT ' +
            fetchLimit +
            ')'
        );
      }
      String soql =
        'SELECT Id, ' +
        String.join(subqueries, ', ') +
        ' FROM ' +
        describe.getName() +
        ' WHERE Id = :recordId';
      List<SObject> parentRows;
      try {
        parentRows = Database.query(soql, AccessLevel.USER_MODE);
      } catch (QueryException e) {
        /** One relationship in this batch turning out not to be queryable in this org/edition (despite passing describe-level checks — CLAUDE.md §Metadata Assumptions) would otherwise take out the whole batch's data with it. Falling back to one query per relationship in just this batch isolates the bad relationship without losing the other (up to 19) good ones. */
        hasMore =
          addChildRelationshipsIndividually(
            batch,
            recordId,
            fetchLimit,
            centerKey,
            nodes,
            edges
          ) || hasMore;
        continue;
      }
      if (parentRows.isEmpty()) {
        continue;
      }
      SObject parentRow = parentRows[0];
      for (EligibleChildRelationship candidate : batch) {
        List<SObject> children;
        try {
          children = parentRow.getSObjects(candidate.relationshipName);
        } catch (Exception e) {
          continue;
        }
        if (children == null) {
          continue;
        }
        hasMore =
          appendChildEdges(children, candidate, centerKey, nodes, edges) ||
          hasMore;
      }
    }
    return hasMore;
  }

  /** Per-relationship fallback used only when a batched subquery for that relationship's batch fails — same one-query-per-relationship shape as this method used before batching existed. */
  private Boolean addChildRelationshipsIndividually(
    List<EligibleChildRelationship> batch,
    String recordId,
    Integer fetchLimit,
    String centerKey,
    List<OI_NodeSummaryDTO> nodes,
    List<OI_EdgeSummaryDTO> edges
  ) {
    Boolean hasMore = false;
    for (EligibleChildRelationship candidate : batch) {
      String soql =
        'SELECT Id, ' +
        candidate.childNameField +
        ' FROM ' +
        candidate.childDescribe.getName() +
        ' WHERE ' +
        candidate.relationshipField.getDescribe().getName() +
        ' = :recordId LIMIT :fetchLimit';
      List<SObject> children;
      try {
        children = Database.query(soql, AccessLevel.USER_MODE);
      } catch (QueryException e) {
        continue;
      }
      hasMore =
        appendChildEdges(children, candidate, centerKey, nodes, edges) ||
        hasMore;
    }
    return hasMore;
  }

  /** Shared node/edge construction for one relationship type's child rows, enforcing MAX_CHILDREN_PER_RELATIONSHIP. Returns true if this relationship type had more rows than the cap. */
  private Boolean appendChildEdges(
    List<SObject> children,
    EligibleChildRelationship candidate,
    String centerKey,
    List<OI_NodeSummaryDTO> nodes,
    List<OI_EdgeSummaryDTO> edges
  ) {
    Schema.DescribeSObjectResult childDescribe = candidate.childDescribe;
    String childNameField = candidate.childNameField;
    Boolean hasMore = false;
    Integer count = 0;
    for (SObject child : children) {
      if (count >= MAX_CHILDREN_PER_RELATIONSHIP) {
        hasMore = true;
        break;
      }
      String childId = (String) child.get('Id');
      String childKey = OI_RecordSchemaUtil.recordNodeKey(
        childDescribe.getName(),
        childId
      );
      nodes.add(
        new OI_NodeSummaryDTO(
          childKey,
          OI_RecordSchemaUtil.recordTypeKey(childDescribe.getName()),
          OI_RecordSchemaUtil.labelFor(child, childNameField),
          childDescribe.getName(),
          'Active'
        )
      );
      OI_EdgeSummaryDTO childEdge = new OI_EdgeSummaryDTO(
        centerKey + '::' + childKey,
        CHILD_EDGE_TYPE_KEY,
        centerKey,
        childKey
      );
      childEdge.viaFieldApiName = candidate.relationshipField.getDescribe()
        .getName();
      edges.add(childEdge);
      count++;
    }
    return hasMore;
  }

  /** One eligible child relationship type, pre-filtered for accessibility (describe-only — no SOQL cost) before batching into subqueries. */
  private class EligibleChildRelationship {
    private final String relationshipName;
    private final Schema.DescribeSObjectResult childDescribe;
    private final Schema.SObjectField relationshipField;
    private final String childNameField;

    private EligibleChildRelationship(
      String relationshipName,
      Schema.DescribeSObjectResult childDescribe,
      Schema.SObjectField relationshipField,
      String childNameField
    ) {
      this.relationshipName = relationshipName;
      this.childDescribe = childDescribe;
      this.relationshipField = relationshipField;
      this.childNameField = childNameField;
    }
  }

  private void addAccessibleField(
    Set<String> selectFields,
    Schema.DescribeSObjectResult describe,
    String fieldApiName
  ) {
    Schema.SObjectField field = describe.fields.getMap().get(fieldApiName);
    if (field != null && field.getDescribe().isAccessible()) {
      selectFields.add(fieldApiName);
    }
  }

  private Datetime datetimeValue(SObject recordValue, String fieldApiName) {
    try {
      Object rawValue = recordValue.get(fieldApiName);
      return rawValue instanceof Datetime ? (Datetime) rawValue : null;
    } catch (SObjectException e) {
      return null;
    }
  }

  private String resolveOwnerName(
    List<OI_NodeSummaryDTO> nodes,
    List<OI_EdgeSummaryDTO> edges
  ) {
    String ownerNodeKey;
    for (OI_EdgeSummaryDTO edge : edges) {
      if (
        edge.typeKey == PARENT_EDGE_TYPE_KEY &&
        edge.viaFieldApiName == 'OwnerId'
      ) {
        ownerNodeKey = edge.targetNodeKey;
        break;
      }
    }
    if (ownerNodeKey == null) {
      return null;
    }
    for (OI_NodeSummaryDTO node : nodes) {
      if (node.nodeKey == ownerNodeKey) {
        return node.label;
      }
    }
    return null;
  }
}
