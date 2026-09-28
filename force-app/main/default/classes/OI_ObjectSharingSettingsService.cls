/**
 * Purpose: Live read of one object's own Sharing Settings (OWD) — the Object panel's Sharing
 *          Settings section, and the deliberate follow-up to OI_ObjectScanner's own documented
 *          gap ("sharing model [...] has no Apex Describe accessor"). This is the first service
 *          in the codebase to read that fact, via Tooling API's EntityDefinition, exactly the
 *          concept a security architect needs beside the Object panel's existing (Describe-
 *          sourced) permission-set grants.
 * Responsibilities: Validate the object exists and is accessible (OI_RecordSchemaUtil, the same
 *                    validation every other object-scoped service in this codebase already
 *                    uses), issue exactly one Tooling API query through OI_ToolingApiAdapter for
 *                    that object's EntityDefinition row, and map it to
 *                    OI_ObjectSharingSettingsDTO — reporting unsupported rather than throwing
 *                    whenever Tooling API cannot answer (CLAUDE.md §Metadata Assumptions: never
 *                    assume org configuration; same convention as
 *                    OI_RecordSharingService/OI_RelationshipFieldDetailService).
 * Dependencies: OI_RecordSchemaUtil, OI_ToolingApiAdapter, OI_ObjectSharingSettingsDTO.
 * Limitations: See OI_ObjectSharingSettingsDTO's own doc comment (sharing MODEL only, never
 *              cached). EntityDefinition is a synthetic Tooling entity with query-shape
 *              restrictions on some editions/object types (Big Objects, external objects) — a
 *              query that fails or returns zero rows is reported through unavailableReason
 *              exactly like every other coverage gap in this codebase, never surfaced as a hard
 *              failure of the whole panel.
 */
public with sharing class OI_ObjectSharingSettingsService {
  private final OI_ToolingApiAdapter toolingApiAdapter;

  public OI_ObjectSharingSettingsService() {
    this(new OI_ToolingApiAdapter());
  }

  /** DI seam for tests (CodingStandards.md's DI-based-fake convention for Adapter dependencies) — production code always uses the zero-arg constructor above. */
  public OI_ObjectSharingSettingsService(
    OI_ToolingApiAdapter toolingApiAdapter
  ) {
    this.toolingApiAdapter = toolingApiAdapter;
  }

  public OI_ObjectSharingSettingsDTO getObjectSharingSettings(
    String objectApiName
  ) {
    Schema.DescribeSObjectResult describe = OI_RecordSchemaUtil.describeAccessibleObject(
      objectApiName
    );
    String soql =
      'SELECT InternalSharingModel, ExternalSharingModel FROM EntityDefinition WHERE QualifiedApiName = \'' +
      String.escapeSingleQuotes(describe.getName()) +
      '\'';

    List<Map<String, Object>> records;
    try {
      records = toolingApiAdapter.query(soql);
    } catch (Exception e) {
      /** CLAUDE.md §Metadata Assumptions: a Tooling API failure (permission, availability) reports unsupported rather than failing the whole panel — same convention as OI_RecordSharingService's own QueryException handling. */
      return new OI_ObjectSharingSettingsDTO(
        false,
        'Sharing settings could not be retrieved for this object.',
        null,
        null
      );
    }

    if (records.isEmpty()) {
      return new OI_ObjectSharingSettingsDTO(
        false,
        'No sharing model information was found for this object.',
        null,
        null
      );
    }

    Map<String, Object> row = records[0];
    return new OI_ObjectSharingSettingsDTO(
      true,
      null,
      (String) row.get('InternalSharingModel'),
      (String) row.get('ExternalSharingModel')
    );
  }
}
