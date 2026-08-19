/**
 * Purpose: Discovers Flows as Discovery Model components (MetadataScanner.md §6) —
 *          componentKind "Flow" — and the exact record-triggered Flow -> Object dependency
 *          (EXECUTES_ON). Backlog DE-8, partial: see Limitations for precisely which half of
 *          DE-8 this delivers and which half genuinely cannot be delivered yet.
 * Responsibilities: Implement OI_IMetadataScanner.scan() via SOQL against FlowDefinitionView —
 *                    a standard, Apex-queryable view requiring NO Tooling API callout, and
 *                    therefore no Named Credential, no Remote Site Setting, and no new
 *                    external-callout surface for AppExchange Security Review. Stays
 *                    graph-blind (never constructs a typeKey, never touches OI_GraphEngine).
 * Dependencies: OI_ComponentKeyUtil, OI_ChecksumUtil, OI_ScannerObjectResolver.
 *
 * Why FlowDefinitionView rather than the Tooling API: Backlog MS-2 (`OI_ToolingApiAdapter`)
 * is marked P0 but has never actually been built — there is no adapter, Named Credential, or
 * Remote Site Setting anywhere in this package. Rather than block Flow coverage entirely on
 * that missing infrastructure, this scanner delivers everything FlowDefinitionView alone can
 * prove, which turns out to include the single most valuable Flow dependency: the object a
 * record-triggered Flow fires on. That edge is EXACT (declared configuration, not inferred),
 * putting it in the same confidence class as OI_ApexTriggerScanner's EXECUTES_ON rather than
 * the regex-heuristic REFERENCES class.
 *
 * Limitations: **Delivers the Flow -> Object trigger dependency ONLY.** A Flow's internal
 *              references — the fields it reads/updates, the Apex it invokes, the sub-flows it
 *              calls, the objects it queries in Get/Create/Update elements — live in the Flow's
 *              metadata definition, which FlowDefinitionView does not expose and which is
 *              reachable only via the Tooling/Metadata API. Those remain genuinely unbuilt and
 *              are blocked on MS-2, not silently dropped: a Flow that updates a field will NOT
 *              show up in that field's impact analysis today. This is the honest floor DE-8's
 *              full scope sits above.
 *              Screen/autolaunched/scheduled Flows have no trigger object at all and correctly
 *              produce a node with no EXECUTES_ON edge — absence of an edge here means "not
 *              record-triggered," never "scan failed."
 *              TriggerObjectOrEventId carries an object NAME for standard objects but an opaque
 *              Id for custom ones; the Id case resolves to null (no edge) rather than to a
 *              fabricated object — see OI_ScannerObjectResolver. Resolving those Ids needs
 *              EntityDefinition access, a named follow-up rather than a guess.
 *              One row per Flow DEFINITION (FlowDefinitionView is already latest-version-
 *              scoped), not one per version — version-level history is out of scope.
 *              Always a full snapshot; no incremental watermark yet, same documented state as
 *              every other scanner in this package.
 */
public inherited sharing class OI_FlowScanner implements OI_IMetadataScanner {
    private static final String COMPONENT_KIND = 'Flow';
    private static final String EXECUTES_ON_RELATIONSHIP_KIND = 'EXECUTES_ON';

    public OI_DiscoveryBatch scan(OI_ScanContext context) {
        List<FlowDefinitionView> flows = [
            SELECT ApiName, Label, Description, ProcessType, TriggerType, TriggerObjectOrEventId, IsActive, VersionNumber, NamespacePrefix, ManageableState
            FROM FlowDefinitionView
        ];

        List<OI_DiscoveredComponent> components = new List<OI_DiscoveredComponent>();
        List<OI_DiscoveredRelationship> relationships = new List<OI_DiscoveredRelationship>();

        for (FlowDefinitionView flow : flows) {
            OI_DiscoveredComponent component = toComponent(flow);
            components.add(component);

            String toComponentKey = OI_ScannerObjectResolver.toObjectComponentKey(flow.TriggerObjectOrEventId);
            if (toComponentKey != null) {
                relationships.add(
                    new OI_DiscoveredRelationship(
                        component.componentKey + '::' + EXECUTES_ON_RELATIONSHIP_KIND + '::' + toComponentKey,
                        EXECUTES_ON_RELATIONSHIP_KIND,
                        component.componentKey,
                        toComponentKey,
                        new Map<String, Object>{ 'triggerType' => flow.TriggerType }
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
            /** PARTIAL by design, not DEGRADED: the trigger-object edge this Scanner does emit is exact, and the internals it cannot see are a permanent boundary of FlowDefinitionView rather than a failure a retry or a permission change would fix. Stating that distinction matters — an admin should not go hunting for a misconfiguration that does not exist. */
            OI_ScanCoverage.partial(
                relationships.size(),
                'Only the object a record-triggered Flow fires on is detected. What a Flow reads or updates internally — ' +
                'its field references, Apex invocations, and subflow calls — requires the Flow metadata definition, which is not ' +
                'reachable without Tooling API access. Screen, scheduled, and autolaunched Flows have no trigger object and ' +
                'correctly produce no relationship.'
            )
        );
    }

    private OI_DiscoveredComponent toComponent(FlowDefinitionView flow) {
        String namespace = String.isBlank(flow.NamespacePrefix) ? null : flow.NamespacePrefix;
        String fullyQualifiedName = namespace == null ? flow.ApiName : namespace + '.' + flow.ApiName;
        Map<String, Object> attributes = new Map<String, Object>{
            'label' => flow.Label,
            'description' => flow.Description,
            'processType' => flow.ProcessType,
            'triggerType' => flow.TriggerType,
            'isActive' => flow.IsActive,
            'versionNumber' => flow.VersionNumber,
            'manageableState' => flow.ManageableState,
            /** The resolved, in-scope trigger object (null for non-record-triggered Flows, and for a custom object whose Id could not be resolved — see Limitations). Stored resolved rather than raw so the Detail Panel never displays an opaque durable Id to a user. */
            'triggerObjectApiName' => OI_ScannerObjectResolver.canonicalInScopeName(flow.TriggerObjectOrEventId)
        };
        return new OI_DiscoveredComponent(
            OI_ComponentKeyUtil.build(COMPONENT_KIND, namespace, fullyQualifiedName),
            COMPONENT_KIND,
            fullyQualifiedName,
            namespace,
            'SOQL',
            attributes,
            OI_ChecksumUtil.computeChecksum(COMPONENT_KIND, fullyQualifiedName, attributes),
            null,
            null
        );
    }
}
