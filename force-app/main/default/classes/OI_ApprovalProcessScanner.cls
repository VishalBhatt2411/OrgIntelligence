/**
 * Purpose: Discovers Approval Processes as Discovery Model components (MetadataScanner.md §6) —
 *          componentKind "ApprovalProcess" — and the exact Approval Process -> Object dependency
 *          (APPLIES_TO). Puts Approval Process into the Object Intelligence Panel's Automation
 *          section (OI_Node_Type_Descriptor__mdt's Intelligence_Category__c), alongside Apex
 *          Triggers, Flows, and Validation Rules.
 * Responsibilities: Implement OI_IMetadataScanner.scan() via SOQL against the standard
 *                    ProcessDefinition object (Type = 'Approval') — a standard, Apex-queryable
 *                    object requiring NO Tooling API callout, and therefore no Named Credential,
 *                    no Remote Site Setting, and no new external-callout surface for AppExchange
 *                    Security Review. Stays graph-blind (never constructs a typeKey, never
 *                    touches OI_GraphEngine).
 * Dependencies: OI_ComponentKeyUtil, OI_ChecksumUtil, OI_ScannerObjectResolver.
 *
 * Why ProcessDefinition rather than the Tooling API's ApprovalProcess object: the same
 * lightest-capable-API reasoning OI_FlowScanner already established for FlowDefinitionView.
 * ProcessDefinition is a standard, always-queryable object (verified directly against a live
 * org: Id, Name, DeveloperName, Type, Description, TableEnumOrId, State) that requires no
 * Tooling API adapter, no Named Credential, and no additional callout surface to justify in
 * AppExchange Security Review. It also carries the ONE most valuable Approval Process fact: the
 * object it applies to (TableEnumOrId) and its Active/Inactive/Obsolete State — both EXACT
 * (declared configuration, not inferred), same confidence class as OI_FlowScanner's
 * EXECUTES_ON.
 *
 * ProcessDefinition rows are not exclusively Approval Processes — the same object also carries
 * other internal process-definition kinds (e.g. Knowledge/Entitlement state machines, Type =
 * 'State'). Filtering WHERE Type = 'Approval' scopes this scanner to real Approval Processes
 * only, verified against real org data during development (both kinds were present).
 *
 * Limitations: **Delivers the Approval Process -> Object relationship and its Active/Inactive/
 *              Obsolete status ONLY.** Entry criteria, approval steps, approvers, and actions
 *              live in the Approval Process's metadata definition, which ProcessDefinition does
 *              not expose and which is reachable only via the Tooling/Metadata API's
 *              ApprovalProcess object (the same permanent boundary OI_FlowScanner documents for
 *              Flow internals) — a named, not-yet-built follow-up, never silently dropped.
 *              ProcessDefinition exposes no NamespacePrefix field (unlike FlowDefinitionView or
 *              ValidationRule's Tooling API row); rather than guess a namespace from
 *              DeveloperName's naming convention, this scanner reports namespace as null for
 *              every Approval Process component — "never guess" (CLAUDE.md) over a best-effort
 *              parse this platform cannot verify.
 *              TableEnumOrId carries an object NAME for standard objects but an opaque Id for
 *              custom ones, exactly like ApexTrigger.TableEnumOrId and Flow's
 *              TriggerObjectOrEventId; the Id case resolves to null (no edge) rather than a
 *              fabricated object — see OI_ScannerObjectResolver.
 *              One row per Approval Process DEFINITION (ProcessDefinition is already the
 *              definition record, not a version history), no incremental watermark yet — the
 *              same documented state as every other scanner in this package.
 */
public inherited sharing class OI_ApprovalProcessScanner implements OI_IMetadataScanner {
  private static final String COMPONENT_KIND = 'ApprovalProcess';
  private static final String APPROVAL_TYPE = 'Approval';
  private static final String APPLIES_TO_RELATIONSHIP_KIND = 'APPLIES_TO';

  public OI_DiscoveryBatch scan(OI_ScanContext context) {
    List<ProcessDefinition> approvalProcesses = [
      SELECT Id, Name, DeveloperName, Description, TableEnumOrId, State
      FROM ProcessDefinition
      WHERE Type = :APPROVAL_TYPE
    ];

    List<OI_DiscoveredComponent> components = new List<OI_DiscoveredComponent>();
    List<OI_DiscoveredRelationship> relationships = new List<OI_DiscoveredRelationship>();

    for (ProcessDefinition approvalProcess : approvalProcesses) {
      OI_DiscoveredComponent component = toComponent(approvalProcess);
      components.add(component);

      String toComponentKey = OI_ScannerObjectResolver.toObjectComponentKey(
        approvalProcess.TableEnumOrId
      );
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
      /** PARTIAL by design, not DEGRADED: the applies-to-object edge and status this Scanner does emit are exact, and the step/criteria/approver internals it cannot see are a permanent boundary of ProcessDefinition rather than a failure a retry or a permission change would fix. */
      OI_ScanCoverage.partial(
        relationships.size(),
        'Only the object an Approval Process applies to, and whether it is Active, Inactive, or Obsolete, is detected. Its entry criteria, ' +
        'approval steps, approvers, and actions require the Approval Process metadata definition, which is not reachable without Tooling API access.'
      )
    );
  }

  private OI_DiscoveredComponent toComponent(
    ProcessDefinition approvalProcess
  ) {
    String fullyQualifiedName = approvalProcess.DeveloperName;
    Map<String, Object> attributes = new Map<String, Object>{
      'label' => approvalProcess.Name,
      'description' => approvalProcess.Description,
      'state' => approvalProcess.State,
      /** The resolved, in-scope object (null for a custom object whose Id could not be resolved — see Limitations). Stored resolved rather than raw so the Detail Panel never displays an opaque durable Id to a user. */
      'objectApiName' => OI_ScannerObjectResolver.canonicalInScopeName(
        approvalProcess.TableEnumOrId
      )
    };
    return new OI_DiscoveredComponent(
      OI_ComponentKeyUtil.build(COMPONENT_KIND, null, fullyQualifiedName),
      COMPONENT_KIND,
      fullyQualifiedName,
      null,
      'SOQL',
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
