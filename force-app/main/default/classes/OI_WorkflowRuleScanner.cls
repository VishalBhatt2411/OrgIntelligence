/**
 * Purpose: Discovers Workflow Rules as Discovery Model components (MetadataScanner.md §6) —
 *          componentKind "WorkflowRule" — and the Workflow Rule -> Object edge it applies to
 *          (APPLIES_TO, the same edge kind OI_ApprovalProcessScanner already registers). Puts
 *          Workflow Rule into the Object Intelligence Panel's Automation section, alongside
 *          Apex Triggers, Flows, Validation Rules, and Approval Processes.
 * Responsibilities: Implement OI_IMetadataScanner.scan() via one Tooling API query against
 *                    WorkflowRule (Id, Name, NamespacePrefix, TableEnumOrId, Metadata), resolve
 *                    each rule's parent object through OI_ScannerObjectResolver, and report
 *                    active/description/triggerType from the compound Metadata field. Stays
 *                    graph-blind (never constructs a typeKey, never touches OI_GraphEngine).
 * Dependencies: OI_ToolingApiAdapter, OI_ComponentKeyUtil, OI_ChecksumUtil,
 *               OI_ScannerObjectResolver.
 *
 * Why TableEnumOrId, not a relationship field: confirmed against the official Tooling API
 * reference — WorkflowRule carries no EntityDefinition-style lookup the way ValidationRule and
 * WorkflowAlert do. TableEnumOrId is the exact same opaque durable/entity-Id-or-name field
 * OI_ApexTriggerScanner and OI_ApprovalProcessScanner already resolve through
 * OI_ScannerObjectResolver, so this scanner inherits that same accepted limitation rather than
 * introducing a new one.
 *
 * Limitations: TableEnumOrId carries an object NAME for standard objects but an opaque Id for
 *              custom ones; the Id case resolves to null (no edge) rather than a fabricated
 *              object — see OI_ScannerObjectResolver. A rule's criteria and its downstream
 *              actions (field updates, email alerts, tasks, outbound messages) live inside the
 *              rule's Metadata.actions/formula, which this scanner stores verbatim for display
 *              only — it does NOT parse action references (e.g. which Email Alert a rule fires)
 *              into dependency edges; that correlation is a named, not-yet-built follow-up, same
 *              posture OI_ValidationRuleScanner takes on errorConditionFormula. A Tooling API
 *              failure reports OI_ScanCoverage.degraded rather than throwing, consistent with
 *              every other Tooling-backed scanner in this codebase (CLAUDE.md §Metadata
 *              Assumptions).
 */
public with sharing class OI_WorkflowRuleScanner implements OI_IMetadataScanner {
  private static final String COMPONENT_KIND = 'WorkflowRule';
  private static final String APPLIES_TO_RELATIONSHIP_KIND = 'APPLIES_TO';
  private static final String QUERY = 'SELECT Id, Name, NamespacePrefix, TableEnumOrId, Metadata FROM WorkflowRule';

  private final OI_ToolingApiAdapter toolingApiAdapter;

  public OI_WorkflowRuleScanner() {
    this(new OI_ToolingApiAdapter());
  }

  /** DI seam for tests (CodingStandards.md's DI-based-fake convention for Adapter dependencies) — the orchestrator (OI_ScanOrchestratorQueueable) always instantiates via the zero-arg constructor above. */
  public OI_WorkflowRuleScanner(OI_ToolingApiAdapter toolingApiAdapter) {
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
          'Workflow Rules could not be retrieved from the Tooling API this run (permission or availability issue on the OI_Self_Callout Named Credential) — retry once resolved.'
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

      String tableEnumOrId = (String) row.get('TableEnumOrId');
      String toComponentKey = String.isBlank(tableEnumOrId)
        ? null
        : OI_ScannerObjectResolver.toObjectComponentKey(tableEnumOrId);
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
        'The object each Workflow Rule applies to, and whether it is active, is detected. The rule\'s criteria formula and the actions it fires (field updates, email alerts, tasks, outbound messages) are not resolved into dependency edges — the raw definition is shown for reference only.'
      )
    );
  }

  private OI_DiscoveredComponent toComponent(Map<String, Object> row) {
    String ruleName = (String) row.get('Name');
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
    String tableEnumOrId = (String) row.get('TableEnumOrId');
    Map<String, Object> attributes = new Map<String, Object>{
      'objectApiName' => String.isBlank(tableEnumOrId)
        ? null
        : OI_ScannerObjectResolver.canonicalInScopeName(tableEnumOrId),
      'active' => metadata.get('active'),
      'description' => metadata.get('description'),
      'triggerType' => metadata.get('triggerType'),
      'formula' => metadata.get('formula')
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
}
