/**
 * Purpose: Org Health's Org Overview section (ADR-0026 Tier 1 — live, unpersisted) —
 *          ProductSpecs.md Phase 4 "Org Overview": Objects, Fields, Apex, Triggers, Flows,
 *          Permission Sets, dependencies, relationships.
 * Responsibilities: Read node/edge counts exclusively through OI_GraphEngine (never
 *                    OI_NodeSelector/OI_EdgeSelector directly — ADR-0013), resolve scan
 *                    freshness, assemble the DTO. "Dependencies" reuses
 *                    OI_DependencyEngineService.DEPENDENCY_EDGE_TYPE_KEYS as its exact
 *                    definition rather than a second, drifting one; "Relationships" is the
 *                    unfiltered total current edge count.
 * Dependencies: OI_GraphEngine, OI_Scan_Run__c.
 *              "Fields" (ADR-0031): the scan persists only relationship fields, so the KPI
 *              sums each object node's scan-time fieldCount attribute (live Describe count).
 *              A graph scanned before that attribute existed — any object without it — falls
 *              back to the persisted field-node count, which was then the full field count.
 *              "Permission Sets": no scanner persists PermissionSet nodes yet, so when the graph
 *              has none the KPI falls back to one live COUNT() via OI_PermissionSetSelector —
 *              otherwise the tile would read 0 in every org while Security Health lists them.
 * Limitations: Node type keys are hardcoded Salesforce-metadata-domain constants, matching
 *              the same narrow, documented exception OI_GraphController.HAS_FIELD_EDGE_TYPE_KEY
 *              already establishes for this Engine's otherwise-fully-generic callers.
 */
public with sharing class OI_OrgOverviewService {
  private static final String OBJECT_TYPE_KEY = 'SalesforceMetadata.CustomObject';
  private static final String FIELD_TYPE_KEY = 'SalesforceMetadata.CustomField';
  private static final String APEX_CLASS_TYPE_KEY = 'SalesforceMetadata.ApexClass';
  private static final String APEX_TRIGGER_TYPE_KEY = 'SalesforceMetadata.ApexTrigger';
  private static final String FLOW_TYPE_KEY = 'SalesforceMetadata.Flow';
  private static final String PERMISSION_SET_TYPE_KEY = 'SalesforceMetadata.PermissionSet';

  /** Object-row bound for the fieldCount sum; ADR-0031 keeps in-scope objects in the tens-to-hundreds. */
  private static final Integer OBJECT_ROW_CEILING = 2000;

  private static final Set<String> NODE_TYPE_KEYS = new Set<String>{
    OBJECT_TYPE_KEY,
    FIELD_TYPE_KEY,
    APEX_CLASS_TYPE_KEY,
    APEX_TRIGGER_TYPE_KEY,
    FLOW_TYPE_KEY,
    PERMISSION_SET_TYPE_KEY
  };

  private final OI_GraphEngine graphEngine;
  private final OI_PermissionSetSelector permissionSetSelector;

  public OI_OrgOverviewService() {
    this(new OI_GraphEngine());
  }

  public OI_OrgOverviewService(OI_GraphEngine graphEngine) {
    this(graphEngine, new OI_PermissionSetSelector());
  }

  public OI_OrgOverviewService(
    OI_GraphEngine graphEngine,
    OI_PermissionSetSelector permissionSetSelector
  ) {
    this.graphEngine = graphEngine;
    this.permissionSetSelector = permissionSetSelector;
  }

  public OI_OrgOverviewDTO getOrgOverview() {
    Map<String, Integer> nodeCounts = graphEngine.countCurrentNodesByType(
      NODE_TYPE_KEYS
    );

    OI_OrgOverviewDTO dto = new OI_OrgOverviewDTO();
    dto.objectCount = countOrZero(nodeCounts, OBJECT_TYPE_KEY);
    dto.fieldCount = resolveFieldCount(countOrZero(nodeCounts, FIELD_TYPE_KEY));
    dto.apexClassCount = countOrZero(nodeCounts, APEX_CLASS_TYPE_KEY);
    dto.triggerCount = countOrZero(nodeCounts, APEX_TRIGGER_TYPE_KEY);
    dto.flowCount = countOrZero(nodeCounts, FLOW_TYPE_KEY);
    dto.permissionSetCount = resolvePermissionSetCount(
      countOrZero(nodeCounts, PERMISSION_SET_TYPE_KEY)
    );
    dto.dependencyCount = graphEngine.countCurrentEdgesByType(
      OI_DependencyEngineService.DEPENDENCY_EDGE_TYPE_KEYS
    );
    dto.relationshipCount = graphEngine.countCurrentEdgesTotal();
    dto.lastScannedAt = resolveLastScannedAt();
    return dto;
  }

  /** Sum of the objects' scanned fieldCount attributes; the persisted field-node count when any object predates the attribute. */
  private Integer resolveFieldCount(Integer persistedFieldNodeCount) {
    List<OI_Graph_Node__c> objects = graphEngine.selectCurrentNodesByTypeBounded(
      OBJECT_TYPE_KEY,
      OBJECT_ROW_CEILING
    );
    if (objects.isEmpty()) {
      return persistedFieldNodeCount;
    }
    Integer total = 0;
    for (OI_Graph_Node__c obj : objects) {
      Integer scannedCount = OI_JsonUtil.readInteger(
        obj.Attributes_Json__c,
        'fieldCount'
      );
      if (scannedCount == null) {
        return persistedFieldNodeCount;
      }
      total += scannedCount;
    }
    return total;
  }

  /** Graph count when PermissionSet nodes exist; otherwise the live standalone count, since the graph simply hasn't scanned them. */
  private Integer resolvePermissionSetCount(Integer persistedCount) {
    if (persistedCount > 0) {
      return persistedCount;
    }
    return permissionSetSelector.countStandalonePermissionSets();
  }

  private Integer countOrZero(Map<String, Integer> counts, String typeKey) {
    Integer count = counts.get(typeKey);
    return count == null ? 0 : count;
  }

  /** When the graph was last successfully refreshed. Null when no scan has ever completed — mirrors OI_NodeIntelligenceService.resolveLastScannedAt's exact query and "never scanned" contract. */
  private Datetime resolveLastScannedAt() {
    List<OI_Scan_Run__c> runs = [
      SELECT LastModifiedDate
      FROM OI_Scan_Run__c
      WHERE Status__c = 'Completed'
      ORDER BY LastModifiedDate DESC
      LIMIT 1
    ];
    return runs.isEmpty() ? null : runs[0].LastModifiedDate;
  }
}
