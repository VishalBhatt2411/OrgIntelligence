/**
 * Purpose: Discovers fields on every in-scope SObject as Discovery Model components
 *          (MetadataScanner.md §6) — componentKind "CustomField" — plus the HAS_FIELD
 *          structural relationship and any LOOKUP_TO/MASTER_DETAIL_TO relationships a
 *          reference field genuinely exposes (Sprint 8 objective §5/§6).
 * Responsibilities: Implement OI_IMetadataScanner.scan() using Schema Describe, mirroring
 *                    OI_ObjectScanner's object-scope filter exactly (OI_ObjectScopeFilter)
 *                    so a field never exists for an object that has no corresponding
 *                    CustomObject node, and vice versa. Populates parentComponentKey on
 *                    every field so OI_MutationGenerator can resolve Object -> Field
 *                    without a cross-scanner lookup (MetadataScanner.md §5). Distinguishes
 *                    Master-Detail from Lookup via getRelationshipOrder() (non-null only
 *                    for Master-Detail) — the standard, documented Describe-API mechanism,
 *                    not a heuristic. Stays graph-blind.
 * Dependencies: OI_ObjectScopeFilter, OI_ComponentKeyUtil, OI_ChecksumUtil, OI_HashUtil.
 * Limitations: Always a full snapshot, for the same reason as OI_ObjectScanner (no
 *              reliable per-field modstamp via Describe). Processes every in-scope
 *              object's full field map within a single scan() call — the real governor-
 *              limit risk this sprint's design accepts: a typical org (hundreds of
 *              objects, tens of fields each) stays well within Queueable heap/CPU limits,
 *              but an org with a very large total field count (tens of thousands+) could
 *              approach them in one hop. Multi-hop chunking within this Scanner (ADR-0004's
 *              "Batch Apex within their own scanner" allowance) is flagged as a Sprint 9
 *              follow-up, not built here. Polymorphic reference fields (e.g. OwnerId ->
 *              User/Group) emit one relationship per referenced object, all captured
 *              faithfully — none invented beyond what getReferenceTo() actually returns.
 */
public class OI_FieldScanner implements OI_IMetadataScanner {
    private static final String COMPONENT_KIND = 'CustomField';
    private static final String PARENT_KIND = 'CustomObject';
    private static final String HAS_FIELD_RELATIONSHIP_KIND = 'HAS_FIELD';
    private static final Integer DESCRIBE_CHUNK_SIZE = 100;

    public OI_DiscoveryBatch scan(OI_ScanContext context) {
        List<String> apiNames = new List<String>(Schema.getGlobalDescribe().keySet());
        if (context.scopedApiNames != null) {
            apiNames = filterToScope(apiNames, context.scopedApiNames);
        }
        apiNames.sort();

        List<OI_DiscoveredComponent> components = new List<OI_DiscoveredComponent>();
        List<OI_DiscoveredRelationship> relationships = new List<OI_DiscoveredRelationship>();
        Integer apiCallsConsumed = 0;

        for (Integer startIndex = 0; startIndex < apiNames.size(); startIndex += DESCRIBE_CHUNK_SIZE) {
            Integer endIndex = Math.min(startIndex + DESCRIBE_CHUNK_SIZE, apiNames.size());
            List<String> chunk = new List<String>();
            for (Integer i = startIndex; i < endIndex; i++) {
                chunk.add(apiNames[i]);
            }
            for (Schema.DescribeSObjectResult objectDescribe : Schema.describeSObjects(chunk)) {
                if (OI_ObjectScopeFilter.isInScope(objectDescribe)) {
                    scanFieldsForObject(objectDescribe, components, relationships);
                }
            }
            apiCallsConsumed++;
        }

        return new OI_DiscoveryBatch(context.scanTaskId, COMPONENT_KIND, components, relationships, true, apiCallsConsumed);
    }

    /** Case-insensitive narrowing of the global describe key set to a caller-supplied scope (OI_ScanContext.scopedApiNames) — the only path that skips the full org-wide Describe, so no real orchestrator call (which always leaves scopedApiNames null) is affected. */
    private List<String> filterToScope(List<String> apiNames, Set<String> scopedApiNames) {
        Set<String> scopeLower = new Set<String>();
        for (String scopedName : scopedApiNames) {
            scopeLower.add(scopedName.toLowerCase());
        }
        List<String> filtered = new List<String>();
        for (String apiName : apiNames) {
            if (scopeLower.contains(apiName.toLowerCase())) {
                filtered.add(apiName);
            }
        }
        return filtered;
    }

    private void scanFieldsForObject(
        Schema.DescribeSObjectResult objectDescribe,
        List<OI_DiscoveredComponent> components,
        List<OI_DiscoveredRelationship> relationships
    ) {
        String objectApiName = objectDescribe.getName();
        String objectNamespace = objectDescribe.isCustom() ? OI_ComponentKeyUtil.extractNamespaceFromApiName(objectApiName) : null;
        String objectComponentKey = OI_ComponentKeyUtil.build(PARENT_KIND, objectNamespace, objectApiName);

        for (Schema.SObjectField field : objectDescribe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            String fullyQualifiedName = objectApiName + '.' + fieldDescribe.getName();
            String fieldNamespace = fieldDescribe.isCustom() ? OI_ComponentKeyUtil.extractNamespaceFromApiName(fieldDescribe.getName()) : objectNamespace;
            String fieldComponentKey = OI_ComponentKeyUtil.build(COMPONENT_KIND, fieldNamespace, fullyQualifiedName);

            List<Schema.SObjectType> referenceTo = fieldDescribe.getReferenceTo();
            Map<String, Object> attributes = new Map<String, Object>{
                'label' => fieldDescribe.getLabel(),
                'type' => String.valueOf(fieldDescribe.getType()),
                'length' => fieldDescribe.getLength(),
                'precision' => fieldDescribe.getPrecision(),
                'scale' => fieldDescribe.getScale(),
                'custom' => fieldDescribe.isCustom(),
                'nillable' => fieldDescribe.isNillable(),
                'unique' => fieldDescribe.isUnique(),
                'externalId' => fieldDescribe.isExternalId(),
                'calculated' => fieldDescribe.isCalculated(),
                'createable' => fieldDescribe.isCreateable(),
                'updateable' => fieldDescribe.isUpdateable()
            };
            if (!referenceTo.isEmpty()) {
                List<String> referencedObjectNames = new List<String>();
                for (Schema.SObjectType referencedType : referenceTo) {
                    referencedObjectNames.add(referencedType.getDescribe().getName());
                }
                attributes.put('referenceTo', referencedObjectNames);
                attributes.put('relationshipName', fieldDescribe.getRelationshipName());
            }

            components.add(
                new OI_DiscoveredComponent(
                    fieldComponentKey,
                    COMPONENT_KIND,
                    fullyQualifiedName,
                    fieldNamespace,
                    'Describe',
                    attributes,
                    OI_ChecksumUtil.computeChecksum(COMPONENT_KIND, fullyQualifiedName, attributes),
                    null,
                    objectComponentKey
                )
            );

            relationships.add(
                new OI_DiscoveredRelationship(
                    OI_HashUtil.hash(objectComponentKey + '::' + HAS_FIELD_RELATIONSHIP_KIND + '::' + fieldComponentKey),
                    HAS_FIELD_RELATIONSHIP_KIND,
                    objectComponentKey,
                    fieldComponentKey,
                    new Map<String, Object>()
                )
            );

            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                addReferenceRelationships(fieldDescribe, fieldComponentKey, referenceTo, relationships);
            }
        }
    }

    private void addReferenceRelationships(
        Schema.DescribeFieldResult fieldDescribe,
        String fieldComponentKey,
        List<Schema.SObjectType> referenceTo,
        List<OI_DiscoveredRelationship> relationships
    ) {
        String relationshipKind = fieldDescribe.getRelationshipOrder() != null ? 'MASTER_DETAIL_TO' : 'LOOKUP_TO';
        for (Schema.SObjectType referencedType : referenceTo) {
            Schema.DescribeSObjectResult referencedDescribe = referencedType.getDescribe();
            String referencedApiName = referencedDescribe.getName();
            String referencedNamespace = referencedDescribe.isCustom() ? OI_ComponentKeyUtil.extractNamespaceFromApiName(referencedApiName) : null;
            String referencedComponentKey = OI_ComponentKeyUtil.build(PARENT_KIND, referencedNamespace, referencedApiName);
            relationships.add(
                new OI_DiscoveredRelationship(
                    OI_HashUtil.hash(fieldComponentKey + '::' + relationshipKind + '::' + referencedComponentKey),
                    relationshipKind,
                    fieldComponentKey,
                    referencedComponentKey,
                    new Map<String, Object>{ 'relationshipName' => fieldDescribe.getRelationshipName() }
                )
            );
        }
    }
}
