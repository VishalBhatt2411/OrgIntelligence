/**
 * Purpose: The Object panel's reworked Relationships section (outgoing side, GraphUI.md §42
 *          item 14 follow-up) — replaces the flat "Outgoing Lookups — N" / "Outgoing
 *          Master-Detail — N" counts with the actual fields behind them, since those counts
 *          are read from the exact same LOOKUP_TO/MASTER_DETAIL_TO edges the canvas already
 *          renders (low marginal value next to the graph). This service surfaces relationship
 *          *quality* data the graph does not show instead: required-ness, cascade-delete
 *          behavior where knowable, and a live per-target-object record count.
 * Responsibilities: Read this object's own HAS_FIELD members from the persisted graph (same
 *                    source OI_GraphController.getFieldSummaries already uses — never a live
 *                    Describe re-scan), filter to reference fields, classify each as Lookup or
 *                    Master-Detail from the field's own scanned 'masterDetail' attribute
 *                    (OI_FieldScanner), and attach a live, non-cacheable COUNT() per distinct
 *                    target object — the one piece of this payload that must never be scanned
 *                    data, since record counts change constantly and a scanned figure would go
 *                    stale immediately (same rationale as OI_RecordSharingService).
 * Dependencies: OI_GraphEngine, OI_RelationshipFieldDTO, OI_RelationshipFieldDetailDTO.
 * Limitations: Outgoing relationships only — the object's own fields are what Describe/the graph
 *              scan can answer without a second, cross-object query; incoming relationships
 *              (other objects' fields that reference this one) keep their existing aggregate
 *              count treatment in the panel, unchanged, since a per-field breakdown there would
 *              mean enumerating every other object in the org, a materially larger capability
 *              not built here. A Lookup field's configured delete constraint
 *              (Clear/Restrict/Cascade-on-special-lookups) is Metadata/Tooling API-only
 *              information with no Apex Describe accessor — left null, never guessed (see
 *              OI_RelationshipFieldDTO's own doc comment). Bounded at
 *              MAX_TARGET_OBJECTS_FOR_CARDINALITY distinct target objects per call (a
 *              polymorphic field like Task/Event's WhatId can reference dozens of objects);
 *              rows beyond that bound still appear, just without a record count, and
 *              cardinalityTruncated is set rather than the excess being silently dropped.
 */
public with sharing class OI_RelationshipFieldDetailService {
  private static final String HAS_FIELD_EDGE_TYPE_KEY = 'SalesforceMetadata.HAS_FIELD';
  private static final Integer MAX_TARGET_OBJECTS_FOR_CARDINALITY = 50;

  public OI_RelationshipFieldDetailDTO getRelationshipFieldDetail(
    String objectNodeKey
  ) {
    List<OI_VersionRecord> fieldVersions = new OI_GraphEngine()
      .getMembersByEdgeType(objectNodeKey, HAS_FIELD_EDGE_TYPE_KEY);

    List<OI_RelationshipFieldDTO> rows = new List<OI_RelationshipFieldDTO>();
    Set<String> distinctTargetObjects = new Set<String>();
    for (OI_VersionRecord fieldVersion : fieldVersions) {
      List<String> referenceTo = toStringList(
        fieldVersion.attributes.get('referenceTo')
      );
      if (referenceTo == null || referenceTo.isEmpty()) {
        continue;
      }
      Boolean isMasterDetail =
        fieldVersion.attributes.get('masterDetail') == true;
      Object nillableRaw = fieldVersion.attributes.get('nillable');
      Boolean isRequired = nillableRaw instanceof Boolean
        ? !((Boolean) nillableRaw)
        : null;
      distinctTargetObjects.addAll(referenceTo);
      rows.add(
        new OI_RelationshipFieldDTO(
          fieldVersion.key,
          fieldVersion.label,
          fieldVersion.secondaryKey,
          isMasterDetail ? 'Master-Detail' : 'Lookup',
          isRequired,
          isMasterDetail ? 'Cascade' : null,
          toCardinalityRows(referenceTo, new Map<String, Integer>())
        )
      );
    }

    Boolean cardinalityTruncated =
      distinctTargetObjects.size() > MAX_TARGET_OBJECTS_FOR_CARDINALITY;
    Map<String, Integer> countsByObject = resolveRecordCounts(
      distinctTargetObjects
    );
    for (OI_RelationshipFieldDTO row : rows) {
      for (
        OI_RelationshipFieldDTO.TargetObjectCardinality target : row.targetObjects
      ) {
        target.recordCount = countsByObject.get(target.objectApiName);
      }
    }

    return new OI_RelationshipFieldDetailDTO(rows, cardinalityTruncated);
  }

  private List<OI_RelationshipFieldDTO.TargetObjectCardinality> toCardinalityRows(
    List<String> objectApiNames,
    Map<String, Integer> countsByObject
  ) {
    List<OI_RelationshipFieldDTO.TargetObjectCardinality> rows = new List<OI_RelationshipFieldDTO.TargetObjectCardinality>();
    for (String objectApiName : objectApiNames) {
      rows.add(
        new OI_RelationshipFieldDTO.TargetObjectCardinality(
          objectApiName,
          countsByObject.get(objectApiName)
        )
      );
    }
    return rows;
  }

  /** One COUNT() per DISTINCT target object across every relationship field on this object, never per field — a polymorphic field's several targets, or two fields sharing a target, must not multiply query count. */
  private Map<String, Integer> resolveRecordCounts(Set<String> objectApiNames) {
    Map<String, Integer> counts = new Map<String, Integer>();
    Integer processed = 0;
    for (String objectApiName : objectApiNames) {
      if (processed >= MAX_TARGET_OBJECTS_FOR_CARDINALITY) {
        break;
      }
      processed++;
      Schema.SObjectType sObjectType = Schema.getGlobalDescribe()
        .get(objectApiName);
      if (sObjectType == null) {
        continue;
      }
      Schema.DescribeSObjectResult describe = sObjectType.getDescribe();
      if (!describe.isAccessible() || !describe.isQueryable()) {
        continue;
      }
      try {
        Integer count = Database.countQuery(
          'SELECT COUNT() FROM ' + describe.getName(),
          AccessLevel.USER_MODE
        );
        counts.put(objectApiName, count);
      } catch (Exception e) {
        /** A describe-accessible object can still be uncountable in practice (edition/feature gating) — CLAUDE.md §Metadata Assumptions: leave this one target's count unresolved rather than fail the whole section. */
      }
    }
    return counts;
  }

  /** JSON.deserializeUntyped hands back a raw List<Object> for a JSON array — never assumed to already be List<String>. */
  private List<String> toStringList(Object rawValue) {
    if (!(rawValue instanceof List<Object>)) {
      return null;
    }
    List<String> result = new List<String>();
    for (Object item : (List<Object>) rawValue) {
      if (item != null) {
        result.add(String.valueOf(item));
      }
    }
    return result;
  }
}
