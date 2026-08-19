/**
 * Purpose: Discovers Apex classes as Discovery Model components (MetadataScanner.md §6) —
 *          componentKind "ApexClass" — and, as of the Dependency Engine epic (DE-0), a
 *          best-effort REFERENCES relationship between classes.
 * Responsibilities: Implement OI_IMetadataScanner.scan() via a plain SOQL query against the
 *                    standard ApexClass object — lighter than both Tooling API (the
 *                    conventional source for Apex introspection) and Describe, and
 *                    explicitly permitted by CLAUDE.md's API Selection Priority ("choose
 *                    the lightest solution capable of solving the problem"), since the
 *                    standard object already exposes every attribute this sprint needs.
 *                    Stays graph-blind. When Body is accessible, emits one "REFERENCES"
 *                    OI_DiscoveredRelationship per other known class whose (unqualified)
 *                    name appears as an identifier token in this class's own Body — the
 *                    minimum-viable data source the Dependency Engine (DE-1..DE-7) needs to
 *                    have anything real to traverse, without the materially larger lift of a
 *                    Tooling API MetadataComponentDependency integration.
 * Dependencies: OI_ComponentKeyUtil, OI_ChecksumUtil.
 * Limitations: DOES NOT select Body when the running user lacks the "Author Apex" system
 *              permission — degrades gracefully to component discovery only (no
 *              relationships), exactly as before this change, rather than turning into a
 *              hard scan failure. Reference extraction is a REGEX HEURISTIC, NOT A SYMBOL
 *              TABLE — a deliberate, documented trade-off (see Impact Analysis's
 *              coverageCaveat, surfaced in the UI, not just here): it will (a) miss dynamic
 *              Apex (Type.forName, reflection), (b) miss interface-based indirection where
 *              the concrete implementing class is never named in the calling code, (c)
 *              occasionally false-positive when a comment or string literal happens to
 *              contain another class's exact name, and (d) can misattribute a namespaced
 *              external reference (NS.ClassName) to an unrelated local class that happens to
 *              share the same unqualified name, since this pass matches bare identifiers,
 *              not fully-qualified dotted paths. This is a floor, not a ceiling — a true
 *              Tooling API dependency integration remains a named future item (roadmap-
 *              adjacent to MS-9), not attempted here. Flow/Trigger/PermissionSet dependency
 *              edges are out of scope for this scanner entirely (separate, larger scanner
 *              work, Backlog MS-6/MS-7). Always a full snapshot — LastModifiedDate is
 *              available but not yet wired as an incremental watermark filter (documented,
 *              not built, this sprint).
 */
public inherited sharing class OI_ApexClassScanner implements OI_IMetadataScanner {
    private static final String COMPONENT_KIND = 'ApexClass';
    private static final String REFERENCES_RELATIONSHIP_KIND = 'REFERENCES';
    private static final Pattern IDENTIFIER_PATTERN = Pattern.compile('[A-Za-z_][A-Za-z0-9_]*');

    public OI_DiscoveryBatch scan(OI_ScanContext context) {
        Boolean bodyAccessible = true;
        List<ApexClass> apexClasses;
        try {
            apexClasses = [
                SELECT Name, NamespacePrefix, ApiVersion, Status, IsValid, LengthWithoutComments, BodyCrc, Body
                FROM ApexClass
            ];
        } catch (System.QueryException noAuthorApexAccess) {
            bodyAccessible = false;
            apexClasses = [SELECT Name, NamespacePrefix, ApiVersion, Status, IsValid, LengthWithoutComments, BodyCrc FROM ApexClass];
        }

        List<OI_DiscoveredComponent> components = new List<OI_DiscoveredComponent>();
        Map<String, String> componentKeyByClassName = new Map<String, String>();
        for (ApexClass apexClass : apexClasses) {
            OI_DiscoveredComponent component = toComponent(apexClass);
            components.add(component);
            componentKeyByClassName.put(apexClass.Name, component.componentKey);
        }

        List<OI_DiscoveredRelationship> relationships = new List<OI_DiscoveredRelationship>();
        if (bodyAccessible) {
            for (ApexClass apexClass : apexClasses) {
                relationships.addAll(extractReferences(apexClass, componentKeyByClassName));
            }
        }

        return new OI_DiscoveryBatch(context.scanTaskId, COMPONENT_KIND, components, relationships, true, 1);
    }

    /**
     * One REFERENCES relationship per distinct other known class named as a bare identifier
     * in this class's Body — deduplicated per source class (a class referenced ten times
     * still produces exactly one edge), self-references excluded (not a meaningful
     * dependency), and never emitted when knownClassNames has nothing to check the token
     * against besides the class's own name.
     */
    private List<OI_DiscoveredRelationship> extractReferences(ApexClass apexClass, Map<String, String> componentKeyByClassName) {
        List<OI_DiscoveredRelationship> found = new List<OI_DiscoveredRelationship>();
        if (String.isBlank(apexClass.Body)) {
            return found;
        }
        String fromComponentKey = componentKeyByClassName.get(apexClass.Name);
        Set<String> referencedClassNames = new Set<String>();
        Matcher tokenMatcher = IDENTIFIER_PATTERN.matcher(apexClass.Body);
        while (tokenMatcher.find()) {
            String token = tokenMatcher.group();
            if (token != apexClass.Name && componentKeyByClassName.containsKey(token)) {
                referencedClassNames.add(token);
            }
        }
        for (String referencedClassName : referencedClassNames) {
            String toComponentKey = componentKeyByClassName.get(referencedClassName);
            found.add(
                new OI_DiscoveredRelationship(
                    fromComponentKey + '::' + REFERENCES_RELATIONSHIP_KIND + '::' + toComponentKey,
                    REFERENCES_RELATIONSHIP_KIND,
                    fromComponentKey,
                    toComponentKey,
                    new Map<String, Object>()
                )
            );
        }
        return found;
    }

    private OI_DiscoveredComponent toComponent(ApexClass apexClass) {
        String namespace = String.isBlank(apexClass.NamespacePrefix) ? null : apexClass.NamespacePrefix;
        String fullyQualifiedName = String.isBlank(namespace) ? apexClass.Name : namespace + '.' + apexClass.Name;
        Map<String, Object> attributes = new Map<String, Object>{
            'apiVersion' => apexClass.ApiVersion,
            'status' => apexClass.Status,
            'isValid' => apexClass.IsValid,
            'lengthWithoutComments' => apexClass.LengthWithoutComments,
            'bodyCrc' => apexClass.BodyCrc
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
