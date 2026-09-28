/**
 * Purpose: Discovers Email Alerts as Discovery Model components (MetadataScanner.md §6) —
 *          componentKind "EmailAlert" — and the Email Alert -> Object edge it is defined against
 *          (APPLIES_TO, the same edge kind OI_ApprovalProcessScanner and OI_WorkflowRuleScanner
 *          already register). Puts Email Alert into the Object Intelligence Panel's Automation
 *          section.
 * Responsibilities: Implement OI_IMetadataScanner.scan() via one Tooling API query against
 *                    WorkflowAlert (Id, DeveloperName, NamespacePrefix, Description, CcEmails,
 *                    SenderType, TemplateId, EntityDefinitionId, EntityDefinition.QualifiedApiName,
 *                    Metadata), resolve each alert's object through the EntityDefinition
 *                    relationship (a real lookup, unlike WorkflowRule's TableEnumOrId), and
 *                    report senderType/ccEmails/description. Stays graph-blind (never constructs
 *                    a typeKey, never touches OI_GraphEngine).
 * Dependencies: OI_ToolingApiAdapter, OI_ComponentKeyUtil, OI_ChecksumUtil,
 *               OI_ScannerObjectResolver.
 *
 * Confirmed directly against the official Tooling API reference: WorkflowAlert exposes NO
 * "Recipients" field at all — CcEmails ("Additional CC email addresses") is the only
 * recipient-adjacent field the Tooling API queries. The actual recipient list (users, roles,
 * public groups, the record owner, and so on) is defined inside the alert's Metadata.recipients
 * array in a shape the Tooling API does not surface as queryable columns, so this scanner does
 * NOT claim to report who an alert notifies — only that it exists, what object it is defined
 * against, and its CC addresses. This is a permanent Tooling API boundary, not a parsing gap this
 * scanner chose not to close.
 *
 * Limitations: An alert whose EntityDefinition cannot be resolved to an in-scope object (Platform
 *              Events, Big Objects, and similarly out-of-scope objects — see
 *              OI_ScannerObjectResolver) still produces an EmailAlert component, just with no
 *              APPLIES_TO edge. The email TEMPLATE an alert sends (TemplateId) is stored as a raw
 *              Id for reference only — this scanner does not resolve it to a Template component,
 *              since no Template scanner exists yet. A Tooling API failure reports
 *              OI_ScanCoverage.degraded rather than throwing, consistent with every other
 *              Tooling-backed scanner in this codebase (CLAUDE.md §Metadata Assumptions).
 */
public with sharing class OI_EmailAlertScanner implements OI_IMetadataScanner {
  private static final String COMPONENT_KIND = 'EmailAlert';
  private static final String APPLIES_TO_RELATIONSHIP_KIND = 'APPLIES_TO';
  private static final String QUERY =
    'SELECT Id, DeveloperName, NamespacePrefix, Description, CcEmails, SenderType, TemplateId, ' +
    'EntityDefinitionId, EntityDefinition.QualifiedApiName, Metadata FROM WorkflowAlert';

  private final OI_ToolingApiAdapter toolingApiAdapter;

  public OI_EmailAlertScanner() {
    this(new OI_ToolingApiAdapter());
  }

  /** DI seam for tests (CodingStandards.md's DI-based-fake convention for Adapter dependencies) — the orchestrator (OI_ScanOrchestratorQueueable) always instantiates via the zero-arg constructor above. */
  public OI_EmailAlertScanner(OI_ToolingApiAdapter toolingApiAdapter) {
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
          'Email Alerts could not be retrieved from the Tooling API this run (permission or availability issue on the OI_Self_Callout Named Credential) — retry once resolved.'
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
              APPLIES_TO_RELATIONSHIP_KIND +
              '::' +
              toComponentKey,
            APPLIES_TO_RELATIONSHIP_KIND,
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
        'The object each Email Alert is defined against, its sender type, and its CC addresses are detected. The actual recipient list (users, roles, groups, record owner) is not exposed by the Tooling API and cannot be shown.'
      )
    );
  }

  private OI_DiscoveredComponent toComponent(Map<String, Object> row) {
    String developerName = (String) row.get('DeveloperName');
    if (String.isBlank(developerName)) {
      return null;
    }
    String namespace = String.isBlank((String) row.get('NamespacePrefix'))
      ? null
      : (String) row.get('NamespacePrefix');
    String fullyQualifiedName = namespace == null
      ? developerName
      : namespace + '.' + developerName;
    Map<String, Object> attributes = new Map<String, Object>{
      'objectApiName' => objectApiNameOf(row),
      'description' => row.get('Description'),
      'ccEmails' => row.get('CcEmails'),
      'senderType' => row.get('SenderType'),
      'templateId' => row.get('TemplateId')
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

  /** EntityDefinition is a nested relationship map on the raw Tooling API row (JSON.deserializeUntyped never gives back a typed sObject) — absent when the alert's parent object could not be resolved by the Tooling API itself. */
  private String objectApiNameOf(Map<String, Object> row) {
    Object entityDefinitionRaw = row.get('EntityDefinition');
    if (!(entityDefinitionRaw instanceof Map<String, Object>)) {
      return null;
    }
    Map<String, Object> entityDefinition = (Map<String, Object>) entityDefinitionRaw;
    return (String) entityDefinition.get('QualifiedApiName');
  }
}
