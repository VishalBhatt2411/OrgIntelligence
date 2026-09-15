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

  private static final Set<String> NODE_TYPE_KEYS = new Set<String>{
    OBJECT_TYPE_KEY,
    FIELD_TYPE_KEY,
    APEX_CLASS_TYPE_KEY,
    APEX_TRIGGER_TYPE_KEY,
    FLOW_TYPE_KEY,
    PERMISSION_SET_TYPE_KEY
  };

  private final OI_GraphEngine graphEngine;

  public OI_OrgOverviewService() {
    this(new OI_GraphEngine());
  }

  public OI_OrgOverviewService(OI_GraphEngine graphEngine) {
    this.graphEngine = graphEngine;
  }

  public OI_OrgOverviewDTO getOrgOverview() {
    Map<String, Integer> nodeCounts = graphEngine.countCurrentNodesByType(
      NODE_TYPE_KEYS
    );

    OI_OrgOverviewDTO dto = new OI_OrgOverviewDTO();
    dto.objectCount = countOrZero(nodeCounts, OBJECT_TYPE_KEY);
    dto.fieldCount = countOrZero(nodeCounts, FIELD_TYPE_KEY);
    dto.apexClassCount = countOrZero(nodeCounts, APEX_CLASS_TYPE_KEY);
    dto.triggerCount = countOrZero(nodeCounts, APEX_TRIGGER_TYPE_KEY);
    dto.flowCount = countOrZero(nodeCounts, FLOW_TYPE_KEY);
    dto.permissionSetCount = countOrZero(nodeCounts, PERMISSION_SET_TYPE_KEY);
    dto.dependencyCount = graphEngine.countCurrentEdgesByType(
      OI_DependencyEngineService.DEPENDENCY_EDGE_TYPE_KEYS
    );
    dto.relationshipCount = graphEngine.countCurrentEdgesTotal();
    dto.lastScannedAt = resolveLastScannedAt();
    return dto;
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
