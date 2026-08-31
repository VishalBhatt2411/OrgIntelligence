/**
 * Purpose: Discovers Permission Sets as Discovery Model components (MetadataScanner.md §6) —
 *          componentKind "PermissionSet" — plus the access grants that make them a real
 *          dependency: which objects and which Apex classes each one grants access to
 *          (GRANTS_ACCESS_TO). Backlog DE-11.
 * Responsibilities: Implement OI_IMetadataScanner.scan() via SOQL against the standard,
 *                    Apex-queryable PermissionSet / ObjectPermissions / SetupEntityAccess
 *                    objects — no Tooling API callout, therefore no Named Credential, no
 *                    Remote Site Setting, no new external-callout surface for AppExchange
 *                    Security Review. Stays graph-blind.
 * Dependencies: OI_ComponentKeyUtil, OI_ChecksumUtil, OI_ScannerObjectResolver.
 *
 * Why these edges matter for Impact Analysis specifically: every other dependency edge in this
 * platform answers "what code breaks?" These answer "who loses access?" — a question an
 * architect asks constantly before deleting an object or an Apex class, and one no other
 * scanner can answer. Both edge kinds are EXACT (they are stored grants, not inferred),
 * placing them in the same confidence class as EXECUTES_ON rather than the regex-heuristic
 * REFERENCES class.
 *
 * Profile-owned permission sets: every Profile has an implicit, system-owned PermissionSet
 * (IsOwnedByProfile = true). Those are deliberately EXCLUDED — including them would double-
 * count every profile grant under a synthetic name no admin recognizes from Setup, and would
 * mean a "Permission Set" node the user cannot find or manage as one. Profiles warrant their
 * own componentKind and scanner (Backlog MS-7), which is where those grants belong.
 *
 * Limitations: **Object and Apex-class grants only — FIELD-level grants are deliberately not
 *              scanned.** FieldPermissions is the highest-cardinality table in this entire
 *              domain (permission sets x fields, routinely hundreds of thousands of rows in a
 *              mature org), and a scanner that naively queried it would hit the 50k SOQL row
 *              limit and fail the whole scan. Doing it safely needs Batch Apex chunking, which
 *              ADR-0004 already anticipates for large types but which no scanner in this
 *              package implements yet — named as the follow-up, not silently skipped. The
 *              practical consequence, stated plainly: "which permission sets grant access to
 *              THIS FIELD" is not answerable today, while the same question about an object or
 *              an Apex class is.
 *              Only grants that actually confer access are emitted — an ObjectPermissions row
 *              with every flag false is a stored no-op, not a dependency, and emitting it would
 *              inflate impact results with grants that grant nothing.
 *              SetupEntityAccess covers ApexClass entities only here; Visualforce pages, Apex
 *              pages, Connected Apps and Custom Permissions also live in that table and are out
 *              of scope until their own componentKinds exist (an edge toward a componentKind no
 *              scanner produces would dangle — the same rule OI_ScannerObjectResolver enforces
 *              for objects).
 *              Always a full snapshot; no incremental watermark yet.
 */
public inherited sharing class OI_PermissionSetScanner implements OI_IMetadataScanner {
    private static final String COMPONENT_KIND = 'PermissionSet';
    private static final String APEX_CLASS_COMPONENT_KIND = 'ApexClass';
    private static final String GRANTS_ACCESS_RELATIONSHIP_KIND = 'GRANTS_ACCESS_TO';
    /** A defensive ceiling on grant rows read in one scan hop. Object/Apex grants are far lower-cardinality than field grants (see Limitations), so this is a safety net against a pathological org rather than an expected boundary — but it is a real cap, and a scan that hits it is reported as truncated rather than silently returning partial data as if complete. */
    private static final Integer MAX_GRANT_ROWS = 20000;

    public OI_DiscoveryBatch scan(OI_ScanContext context) {
        List<PermissionSet> permissionSets = [
            SELECT Id, Name, Label, Description, NamespacePrefix, IsCustom, License.Name
            FROM PermissionSet
            WHERE IsOwnedByProfile = false
        ];

        List<OI_DiscoveredComponent> components = new List<OI_DiscoveredComponent>();
        Map<Id, String> componentKeyByPermissionSetId = new Map<Id, String>();
        for (PermissionSet permissionSet : permissionSets) {
            OI_DiscoveredComponent component = toComponent(permissionSet);
            components.add(component);
            componentKeyByPermissionSetId.put(permissionSet.Id, component.componentKey);
        }

        List<OI_DiscoveredRelationship> relationships = new List<OI_DiscoveredRelationship>();
        relationships.addAll(buildObjectGrants(componentKeyByPermissionSetId));
        relationships.addAll(buildApexClassGrants(componentKeyByPermissionSetId));

        return new OI_DiscoveryBatch(
            context.scanTaskId,
            COMPONENT_KIND,
            components,
            relationships,
            true,
            1,
            /** PARTIAL: object and Apex-class grants are exact and complete, but field-level grants are deliberately not scanned (FieldPermissions volume needs Batch Apex chunking). Named explicitly so "which permission sets expose this FIELD" reads as a known gap rather than an empty answer. */
            OI_ScanCoverage.partial(
                relationships.size(),
                'Object-level and Apex-class grants are fully detected. Field-level grants are not scanned yet, so ' +
                '"which permission sets expose this field" cannot be answered. Profile-owned permission sets are ' +
                'excluded by design and are reported separately once Profile scanning exists.'
            )
        );
    }

    /**
     * PermissionSet -> CustomObject grants. Every candidate object goes through
     * OI_ScannerObjectResolver, so a grant on an object OI_ObjectScanner does not create a node
     * for (a Platform Event, a __mdt type, a companion History object — all of which really do
     * appear in ObjectPermissions) produces no edge instead of a dangling one.
     */
    private List<OI_DiscoveredRelationship> buildObjectGrants(Map<Id, String> componentKeyByPermissionSetId) {
        List<OI_DiscoveredRelationship> found = new List<OI_DiscoveredRelationship>();
        if (componentKeyByPermissionSetId.isEmpty()) {
            return found;
        }
        for (ObjectPermissions grant : [
            SELECT ParentId, SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete, PermissionsViewAllRecords, PermissionsModifyAllRecords
            FROM ObjectPermissions
            WHERE ParentId IN :componentKeyByPermissionSetId.keySet()
            LIMIT :MAX_GRANT_ROWS
        ]) {
            List<String> grantedPermissions = describeObjectPermissions(grant);
            if (grantedPermissions.isEmpty()) {
                continue;
            }
            String fromComponentKey = componentKeyByPermissionSetId.get(grant.ParentId);
            String toComponentKey = OI_ScannerObjectResolver.toObjectComponentKey(grant.SobjectType);
            if (fromComponentKey == null || toComponentKey == null) {
                continue;
            }
            found.add(
                new OI_DiscoveredRelationship(
                    fromComponentKey + '::' + GRANTS_ACCESS_RELATIONSHIP_KIND + '::' + toComponentKey,
                    GRANTS_ACCESS_RELATIONSHIP_KIND,
                    fromComponentKey,
                    toComponentKey,
                    new Map<String, Object>{ 'grantedPermissions' => grantedPermissions }
                )
            );
        }
        return found;
    }

    /**
     * PermissionSet -> ApexClass grants, via SetupEntityAccess. SetupEntityId is the ApexClass
     * Id, so the class NAME (which componentKey needs) requires a second query — done as one
     * bulk lookup over the collected Ids, never per row.
     */
    private List<OI_DiscoveredRelationship> buildApexClassGrants(Map<Id, String> componentKeyByPermissionSetId) {
        List<OI_DiscoveredRelationship> found = new List<OI_DiscoveredRelationship>();
        if (componentKeyByPermissionSetId.isEmpty()) {
            return found;
        }
        List<SetupEntityAccess> grants = [
            SELECT ParentId, SetupEntityId
            FROM SetupEntityAccess
            WHERE ParentId IN :componentKeyByPermissionSetId.keySet() AND SetupEntityType = 'ApexClass'
            LIMIT :MAX_GRANT_ROWS
        ];
        if (grants.isEmpty()) {
            return found;
        }

        Set<Id> apexClassIds = new Set<Id>();
        for (SetupEntityAccess grant : grants) {
            apexClassIds.add(grant.SetupEntityId);
        }
        Map<Id, String> componentKeyByApexClassId = new Map<Id, String>();
        for (ApexClass apexClass : [SELECT Id, Name, NamespacePrefix FROM ApexClass WHERE Id IN :apexClassIds]) {
            String namespace = String.isBlank(apexClass.NamespacePrefix) ? null : apexClass.NamespacePrefix;
            String fullyQualifiedName = namespace == null ? apexClass.Name : namespace + '.' + apexClass.Name;
            componentKeyByApexClassId.put(apexClass.Id, OI_ComponentKeyUtil.build(APEX_CLASS_COMPONENT_KIND, namespace, fullyQualifiedName));
        }

        for (SetupEntityAccess grant : grants) {
            String fromComponentKey = componentKeyByPermissionSetId.get(grant.ParentId);
            String toComponentKey = componentKeyByApexClassId.get(grant.SetupEntityId);
            /** A SetupEntityId whose ApexClass row is not visible/queryable to the running user yields no edge — skip-never-fabricate, matching this package's established discipline. */
            if (fromComponentKey == null || toComponentKey == null) {
                continue;
            }
            found.add(
                new OI_DiscoveredRelationship(
                    fromComponentKey + '::' + GRANTS_ACCESS_RELATIONSHIP_KIND + '::' + toComponentKey,
                    GRANTS_ACCESS_RELATIONSHIP_KIND,
                    fromComponentKey,
                    toComponentKey,
                    new Map<String, Object>{ 'grantedPermissions' => new List<String>{ 'execute' } }
                )
            );
        }
        return found;
    }

    /** The grant's actual conferred permissions, as display-ready tokens. An empty list means the row confers nothing — see Limitations for why such a row is skipped rather than edged. */
    @TestVisible
    private List<String> describeObjectPermissions(ObjectPermissions grant) {
        List<String> granted = new List<String>();
        if (grant.PermissionsRead == true) {
            granted.add('read');
        }
        if (grant.PermissionsCreate == true) {
            granted.add('create');
        }
        if (grant.PermissionsEdit == true) {
            granted.add('edit');
        }
        if (grant.PermissionsDelete == true) {
            granted.add('delete');
        }
        if (grant.PermissionsViewAllRecords == true) {
            granted.add('view all');
        }
        if (grant.PermissionsModifyAllRecords == true) {
            granted.add('modify all');
        }
        return granted;
    }

    private OI_DiscoveredComponent toComponent(PermissionSet permissionSet) {
        String namespace = String.isBlank(permissionSet.NamespacePrefix) ? null : permissionSet.NamespacePrefix;
        String fullyQualifiedName = namespace == null ? permissionSet.Name : namespace + '.' + permissionSet.Name;
        Map<String, Object> attributes = new Map<String, Object>{
            'label' => permissionSet.Label,
            'description' => permissionSet.Description,
            'isCustom' => permissionSet.IsCustom,
            'license' => permissionSet.License == null ? null : permissionSet.License.Name
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
