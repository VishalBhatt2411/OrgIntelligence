/**
 * Purpose: Discovers Salesforce SObjects (standard and custom) as Discovery Model
 *          components (MetadataScanner.md §6) — componentKind "CustomObject".
 * Responsibilities: Implement OI_IMetadataScanner.scan() using Schema Describe — the
 *                    lightest native mechanism (CLAUDE.md API Selection Priority) capable
 *                    of enumerating every object without Tooling/Metadata API or a
 *                    callout. Stays graph-blind: never constructs a typeKey, never touches
 *                    OI_GraphEngine/OI_MutationGenerator.
 * Dependencies: OI_ObjectScopeFilter, OI_ComponentKeyUtil, OI_ChecksumUtil. Attribute
 *              selection is intentionally limited to what Schema.DescribeSObjectResult's
 *              Apex surface actually exposes — sharing model and trigger-ability are
 *              Metadata/Tooling API concepts with no Apex Describe accessor, and pulling
 *              them in would violate the "Describe only" mechanism choice this class
 *              documents above.
 * Limitations: Always a full snapshot — Schema.getGlobalDescribe() has no reliable
 *              modstamp to filter by, so incremental scanning (MetadataScanner.md §8)
 *              is not meaningful for this componentKind; every scan is effectively full,
 *              consistent with §9's "full is the only mode for types without a reliable
 *              modstamp." Processes the entire global describe within a single scan()
 *              call, chunked at the platform's 100-per-call Schema.describeSObjects
 *              ceiling — sized correctly for realistic org object counts (hundreds to a
 *              few thousand); an org with an extreme object count (~5000+) could approach
 *              Queueable heap/CPU limits in one hop, which would need the Batch-Apex-
 *              within-scanner chunking ADR-0004 already allows for large types — not
 *              built this sprint, flagged as a known limitation (Sprint 8 report).
 */
public class OI_ObjectScanner implements OI_IMetadataScanner {
    private static final String COMPONENT_KIND = 'CustomObject';
    private static final Integer DESCRIBE_CHUNK_SIZE = 100;

    public OI_DiscoveryBatch scan(OI_ScanContext context) {
        List<String> apiNames = new List<String>(Schema.getGlobalDescribe().keySet());
        apiNames.sort();

        List<OI_DiscoveredComponent> components = new List<OI_DiscoveredComponent>();
        Integer apiCallsConsumed = 0;

        for (Integer startIndex = 0; startIndex < apiNames.size(); startIndex += DESCRIBE_CHUNK_SIZE) {
            Integer endIndex = Math.min(startIndex + DESCRIBE_CHUNK_SIZE, apiNames.size());
            List<String> chunk = new List<String>();
            for (Integer i = startIndex; i < endIndex; i++) {
                chunk.add(apiNames[i]);
            }
            for (Schema.DescribeSObjectResult describeResult : Schema.describeSObjects(chunk)) {
                if (OI_ObjectScopeFilter.isInScope(describeResult)) {
                    components.add(toComponent(describeResult));
                }
            }
            apiCallsConsumed++;
        }

        return new OI_DiscoveryBatch(context.scanTaskId, COMPONENT_KIND, components, new List<OI_DiscoveredRelationship>(), true, apiCallsConsumed);
    }

    private OI_DiscoveredComponent toComponent(Schema.DescribeSObjectResult describeResult) {
        String apiName = describeResult.getName();
        String namespace = describeResult.isCustom() ? OI_ComponentKeyUtil.extractNamespaceFromApiName(apiName) : null;
        Map<String, Object> attributes = new Map<String, Object>{
            'label' => describeResult.getLabel(),
            'pluralLabel' => describeResult.getLabelPlural(),
            'custom' => describeResult.isCustom(),
            'namespace' => namespace,
            'keyPrefix' => describeResult.getKeyPrefix(),
            'queryable' => describeResult.isQueryable(),
            'createable' => describeResult.isCreateable(),
            'updateable' => describeResult.isUpdateable(),
            'deletable' => describeResult.isDeletable(),
            'feedEnabled' => describeResult.isFeedEnabled()
        };
        return new OI_DiscoveredComponent(
            OI_ComponentKeyUtil.build(COMPONENT_KIND, namespace, apiName),
            COMPONENT_KIND,
            apiName,
            namespace,
            'Describe',
            attributes,
            OI_ChecksumUtil.computeChecksum(COMPONENT_KIND, apiName, attributes),
            null,
            null
        );
    }
}
