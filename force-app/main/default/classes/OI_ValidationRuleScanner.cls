/**
 * Purpose: Discovers Validation Rules as Discovery Model components (MetadataScanner.md §6) —
 *          componentKind "ValidationRule" — and the exact Validation Rule -> Object edge it
 *          validates (VALIDATES). Unblocks Backlog DE-10, previously hard-blocked on MS-2 (the
 *          Tooling API adapter, now built — see ADR-0029): ValidationRule has no Apex-queryable
 *          standard-object equivalent (unlike Flow's FlowDefinitionView), so this scanner is the
 *          first in this package to require OI_ToolingApiAdapter as its ONLY source.
 * Responsibilities: Implement OI_IMetadataScanner.scan() via one Tooling API query against
 *                    ValidationRule (Id, ValidationName, NamespacePrefix, EntityDefinitionId,
 *                    EntityDefinition.QualifiedApiName, Metadata), resolve each rule's parent
 *                    object through OI_ScannerObjectResolver, and report Active/errorMessage/
 *                    errorConditionFormula/errorDisplayField from the compound Metadata field.
 *                    Stays graph-blind (never constructs a typeKey, never touches
 *                    OI_GraphEngine).
 * Dependencies: OI_ToolingApiAdapter, OI_ComponentKeyUtil, OI_ChecksumUtil,
 *               OI_ScannerObjectResolver.
 * Limitations: A rule whose parent object cannot be resolved to an in-scope node (see
 *              OI_ScannerObjectResolver — Platform Events, Big Objects, and similarly
 *              out-of-scope objects) still produces a ValidationRule component, just with no
 *              VALIDATES edge, exactly like OI_FlowScanner's screen-Flow case: absence of an edge
 *              here means "parent object out of this platform's scan scope," never "scan
 *              failed." errorConditionFormula is stored verbatim for display only — this
 *              scanner does NOT parse it for field references; that is the Field dependency
 *              scanner's job (a separate, not-yet-built capability), and conflating the two
 *              here would silently misrepresent a formula's mere presence as a resolved field
 *              dependency. A Tooling API failure (permission not granted to the OI_Self_Callout
 *              Named Credential's Run As user, or the callout endpoint unavailable) reports
 *              OI_ScanCoverage.degraded rather than throwing, consistent with every other
 *              service in this codebase that treats Tooling API unavailability as a coverage
 *              gap, never a hard failure (CLAUDE.md §Metadata Assumptions).
 */
public with sharing class OI_ValidationRuleScanner implements OI_IMetadataScanner {
  private static final String COMPONENT_KIND = 'ValidationRule';
  private static final String VALIDATES_RELATIONSHIP_KIND = 'VALIDATES';
  private static final String QUERY =
    'SELECT Id, ValidationName, NamespacePrefix, EntityDefinitionId, ' +
    'EntityDefinition.QualifiedApiName, Metadata FROM ValidationRule';

  private final OI_ToolingApiAdapter toolingApiAdapter;

  public OI_ValidationRuleScanner() {
    this(new OI_ToolingApiAdapter());
  }

  /** DI seam for tests (CodingStandards.md's DI-based-fake convention for Adapter dependencies) — the orchestrator (OI_ScanOrchestratorQueueable) always instantiates via the zero-arg constructor above. */
  public OI_ValidationRuleScanner(OI_ToolingApiAdapter toolingApiAdapter) {
    this.toolingApiAdapter = toolingApiAdapter;
  }

  public OI_DiscoveryBatch scan(OI_ScanContext context) {
    List<Map<String, Object>> rawRows;
    try {
      rawRows = toolingApiAdapter.query(QUERY);
    } catch (Exception e) {
      return new OI_DiscoveryBatch(
        context.scanTaskId,
        COMPONENT_KIND,
        new List<OI_DiscoveredComponent>(),
        new List<OI_DiscoveredRelationship>(),
        false,
        1,
        OI_ScanCoverage.degraded(
          0,
          'Validation Rules could not be retrieved from the Tooling API this run (permission or availability issue on the OI_Self_Callout Named Credential) — retry once resolved.'
        )
      );
    }

    List<OI_DiscoveredComponent> components = new List<OI_DiscoveredComponent>();
    List<OI_DiscoveredRelationship> relationships = new List<OI_DiscoveredRelationship>();

    for (Map<String, Object> row : rawRows) {
      OI_DiscoveredComponent component = toComponent(row);
      if (component == null) {
        continue;
      }
      components.add(component);

      String objectApiName = objectApiNameOf(row);
      String toComponentKey = objectApiName == null
        ? null
        : OI_ScannerObjectResolver.toObjectComponentKey(objectApiName);
      if (toComponentKey != null) {
        relationships.add(
          new OI_DiscoveredRelationship(
            component.componentKey +
              '::' +
              VALIDATES_RELATIONSHIP_KIND +
              '::' +
              toComponentKey,
            VALIDATES_RELATIONSHIP_KIND,
            component.componentKey,
            toComponentKey,
            new Map<String, Object>()
          )
        );
      }
    }

    return new OI_DiscoveryBatch(
      context.scanTaskId,
      COMPONENT_KIND,
      components,
      relationships,
      true,
      1,
      OI_ScanCoverage.partial(
        relationships.size(),
        'The object each Validation Rule validates, and whether it is active, is detected. The specific fields a rule\'s formula references are not resolved into dependency edges — the raw formula text is shown for reference only.'
      )
    );
  }

  private OI_DiscoveredComponent toComponent(Map<String, Object> row) {
    String ruleName = (String) row.get('ValidationName');
    if (String.isBlank(ruleName)) {
      return null;
    }
    String namespace = String.isBlank((String) row.get('NamespacePrefix'))
      ? null
      : (String) row.get('NamespacePrefix');
    String fullyQualifiedName = namespace == null
      ? ruleName
      : namespace + '.' + ruleName;
    Map<String, Object> metadata = (Map<String, Object>) row.get('Metadata');
    if (metadata == null) {
      metadata = new Map<String, Object>();
    }
    Map<String, Object> attributes = new Map<String, Object>{
      'objectApiName' => objectApiNameOf(row),
      'active' => metadata.get('active'),
      'description' => metadata.get('description'),
      'errorConditionFormula' => metadata.get('errorConditionFormula'),
      'errorDisplayField' => metadata.get('errorDisplayField'),
      'errorMessage' => metadata.get('errorMessage')
    };
    return new OI_DiscoveredComponent(
      OI_ComponentKeyUtil.build(COMPONENT_KIND, namespace, fullyQualifiedName),
      COMPONENT_KIND,
      fullyQualifiedName,
      namespace,
      'Tooling',
      attributes,
      OI_ChecksumUtil.computeChecksum(
        COMPONENT_KIND,
        fullyQualifiedName,
        attributes
      ),
      null,
      null
    );
  }

  /** EntityDefinition is a nested relationship map on the raw Tooling API row (JSON.deserializeUntyped never gives back a typed sObject) — absent when the rule's parent object could not be resolved by the Tooling API itself (a describe-restricted entity), handled the same as any other unresolvable candidate: null, never guessed. */
  private String objectApiNameOf(Map<String, Object> row) {
    Object entityDefinitionRaw = row.get('EntityDefinition');
    if (!(entityDefinitionRaw instanceof Map<String, Object>)) {
      return null;
    }
    Map<String, Object> entityDefinition = (Map<String, Object>) entityDefinitionRaw;
    return (String) entityDefinition.get('QualifiedApiName');
  }
}
