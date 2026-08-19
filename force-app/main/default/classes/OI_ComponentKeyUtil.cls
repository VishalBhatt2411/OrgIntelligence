/**
 * Purpose: Builds and parses OI_DiscoveredComponent.componentKey / the componentKey
 *          referenced by OI_DiscoveredRelationship.from/toComponentKey and
 *          OI_DiscoveredComponent.parentComponentKey (MetadataScanner.md §5).
 * Responsibilities: componentKey is built as the deterministic, self-describing string
 *                    "<componentKind>::<namespace>::<fullyQualifiedName>" rather than a
 *                    one-way SHA-256 digest (a documented, deliberate deviation from
 *                    MetadataScanner.md §5's literal "hash(...)" wording — see
 *                    OI_MutationGenerator's class doc and the Sprint 8 deliverables report
 *                    for the rationale: OI_MutationGenerator only ever sees one
 *                    OI_DiscoveryBatch at a time, so a parentComponentKey or relationship
 *                    endpoint produced by a DIFFERENT scan task's Scanner — e.g. a Field's
 *                    parent Object, scanned separately from the Field itself — must be
 *                    resolvable to a Graph nodeKey without the originating component in
 *                    memory. A one-way hash cannot be inverted; a parseable, deterministic
 *                    string can. componentKey remains internal-only (MetadataScanner.md
 *                    §19 — never exposed to any external caller), so this costs nothing
 *                    architecturally.) This class carries no Graph Engine vocabulary
 *                    (no typeKey/nodeKey) — it is exactly as graph-blind as any Scanner
 *                    that uses it, safe under the facade/blindness lint rule.
 * Dependencies: None.
 * Limitations: componentKind and namespace must never themselves contain the "::"
 *              separator — true of every Salesforce API/metadata-type name.
 */
public inherited sharing class OI_ComponentKeyUtil {
    private static final String SEPARATOR = '::';

    public class ParsedComponentKey {
        public final String componentKind;
        public final String namespace;
        public final String fullyQualifiedName;

        public ParsedComponentKey(String componentKind, String namespace, String fullyQualifiedName) {
            this.componentKind = componentKind;
            this.namespace = namespace;
            this.fullyQualifiedName = fullyQualifiedName;
        }
    }

    public static String build(String componentKind, String namespace, String fullyQualifiedName) {
        return componentKind + SEPARATOR + (namespace == null ? '' : namespace) + SEPARATOR + fullyQualifiedName;
    }

    public static ParsedComponentKey parse(String componentKey) {
        if (String.isBlank(componentKey)) {
            return null;
        }
        List<String> parts = componentKey.split(SEPARATOR, 3);
        if (parts.size() != 3) {
            return null;
        }
        return new ParsedComponentKey(parts[0], String.isBlank(parts[1]) ? null : parts[1], parts[2]);
    }

    /**
     * Convention-based namespace extraction for managed-package Object/Field API names
     * (e.g. "NS__Object__c" -> "NS"), since Schema Describe exposes no direct namespace
     * accessor for SObjects/fields the way ApexClass.NamespacePrefix does. Returns null for
     * org-native (unpackaged) names. Documented limitation: relies on the standard
     * namespace__Name__c naming convention, not a guaranteed platform API.
     */
    public static String extractNamespaceFromApiName(String apiName) {
        if (String.isBlank(apiName)) {
            return null;
        }
        List<String> segments = apiName.split('__');
        if (segments.size() >= 3) {
            return segments[0];
        }
        return null;
    }
}
