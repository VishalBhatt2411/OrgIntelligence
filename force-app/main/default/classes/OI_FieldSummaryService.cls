/**
 * Purpose: Builds an object's full field list for oiNodeDetailPanel's field browser
 *          (ADR-0031). The scan persists only relationship-bearing fields as graph nodes,
 *          so the complete list comes from live Schema Describe, joined to whichever fields
 *          do have a graph node so those rows stay navigable.
 * Responsibilities: Resolve the object's API name from its graph node, describe its
 *                    fields, and attach the persisted field node key (if any) to each row.
 *                    Persisted fields that Describe no longer returns (deleted since the
 *                    last scan) are still listed so the graph and the list agree.
 * Dependencies: OI_GraphEngine, OI_FieldSummaryDTO.
 * Inputs: An object node key. Outputs: one OI_FieldSummaryDTO per field.
 * Limitations: When the object node is missing, or its object no longer exists in the org,
 *              only the persisted field nodes are returned — the pre-ADR-0031 behaviour. A
 *              field whose own describe throws (licence-gated industry-cloud fields, see
 *              OI_FieldScanner) is skipped, exactly as the scanner skips it. Field-level
 *              security is not applied: this lists schema metadata, not record data, the
 *              same visibility the scanned graph already gives an OI_View_Graph user.
 */
public with sharing class OI_FieldSummaryService {
  private static final String HAS_FIELD_EDGE_TYPE_KEY = 'SalesforceMetadata.HAS_FIELD';
  private final OI_GraphEngine engine;

  public OI_FieldSummaryService() {
    this(new OI_GraphEngine());
  }

  @TestVisible
  private OI_FieldSummaryService(OI_GraphEngine engine) {
    this.engine = engine;
  }

  public List<OI_FieldSummaryDTO> getFieldSummaries(String objectNodeKey) {
    Map<String, OI_VersionRecord> persistedByApiName = new Map<String, OI_VersionRecord>();
    for (
      OI_VersionRecord fieldVersion : engine.getMembersByEdgeType(
        objectNodeKey,
        HAS_FIELD_EDGE_TYPE_KEY
      )
    ) {
      if (fieldVersion.secondaryKey != null) {
        persistedByApiName.put(
          fieldVersion.secondaryKey.toLowerCase(),
          fieldVersion
        );
      }
    }

    Schema.DescribeSObjectResult objectDescribe = describeObjectOf(
      objectNodeKey
    );
    List<OI_FieldSummaryDTO> summaries = new List<OI_FieldSummaryDTO>();
    if (objectDescribe != null) {
      String objectApiName = objectDescribe.getName();
      for (
        Schema.SObjectField field : objectDescribe.fields.getMap().values()
      ) {
        Schema.DescribeFieldResult fieldDescribe;
        try {
          fieldDescribe = field.getDescribe();
        } catch (System.SObjectException describeException) {
          continue;
        }
        String qualifiedName = objectApiName + '.' + fieldDescribe.getName();
        OI_VersionRecord persisted = persistedByApiName.remove(
          qualifiedName.toLowerCase()
        );
        summaries.add(
          new OI_FieldSummaryDTO(
            fieldDescribe,
            qualifiedName,
            persisted == null ? null : persisted.key
          )
        );
      }
    }
    for (OI_VersionRecord leftover : persistedByApiName.values()) {
      summaries.add(new OI_FieldSummaryDTO(leftover));
    }
    return summaries;
  }

  private Schema.DescribeSObjectResult describeObjectOf(String objectNodeKey) {
    OI_VersionRecord objectVersion = String.isBlank(objectNodeKey)
      ? null
      : engine.getNodeDetail(objectNodeKey);
    if (objectVersion == null || String.isBlank(objectVersion.secondaryKey)) {
      return null;
    }
    Schema.SObjectType objectType = Schema.getGlobalDescribe()
      .get(objectVersion.secondaryKey);
    return objectType == null ? null : objectType.getDescribe();
  }
}
