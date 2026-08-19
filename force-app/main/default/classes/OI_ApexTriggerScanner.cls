/**
 * Purpose: Discovers Apex triggers as Discovery Model components (MetadataScanner.md §6) —
 *          componentKind "ApexTrigger" — and the two dependency relationships a trigger
 *          actually has: the object it fires on (EXECUTES_ON) and the Apex classes it calls
 *          (REFERENCES). Backlog DE-9, closing part of the "Impact Analysis is Apex-class-only"
 *          gap named in OI_DependencyEngineService's own Limitations.
 * Responsibilities: Implement OI_IMetadataScanner.scan() via a plain SOQL query against the
 *                    standard ApexTrigger object — the same "lightest capable mechanism"
 *                    choice OI_ApexClassScanner documents (CLAUDE.md API Selection Priority),
 *                    since the standard object exposes every attribute needed without a
 *                    Tooling API callout. Stays graph-blind (never constructs a typeKey,
 *                    never touches OI_GraphEngine/OI_MutationGenerator).
 * Dependencies: OI_ComponentKeyUtil, OI_ChecksumUtil, OI_ScannerObjectResolver.
 *
 * Object references go through OI_ScannerObjectResolver rather than being resolved here: it
 * centralizes the casing and dangling-edge rules every object-referencing Scanner needs (this
 * package's own OI_LogEventTrigger, which fires on the Platform Event OI_Log_Event__e, is a
 * real instance of the dangling-edge case — see that class for the full reasoning).
 *
 * Why the EXECUTES_ON edge is qualitatively different from REFERENCES: a trigger's target
 * object is DECLARED, not inferred — `trigger Foo on Account (before insert)` names Account
 * unambiguously in the source, and TableEnumOrId carries it independently. That makes this
 * the first exact, non-heuristic dependency edge in the platform (every REFERENCES edge, here
 * and in OI_ApexClassScanner, remains a documented regex heuristic). Impact Analysis against
 * an Object can therefore answer "which triggers fire on this?" with certainty, not
 * best-effort — worth stating plainly so the two edge classes are never conflated when
 * reasoning about result confidence.
 *
 * Object resolution order (both paths verified against Schema.getGlobalDescribe(), so a
 * resolved name is always a real object in this org, never a raw string echoed through):
 *   1. The `trigger <name> on <Object> (` declaration parsed from Body — works identically
 *      for standard and custom objects.
 *   2. TableEnumOrId, when Body is inaccessible or the declaration doesn't parse. This holds
 *      a usable object NAME for standard objects but an opaque Id for custom ones, which is
 *      exactly why it is the fallback rather than the primary: verifying against the global
 *      describe means the custom-object Id case is skipped safely (no edge) instead of
 *      producing a bogus edge to a non-existent "object" named 01Ixx0000000001.
 * A trigger whose object cannot be resolved by either path yields NO EXECUTES_ON edge rather
 * than a guessed one — consistent with this codebase's skip-never-fabricate discipline.
 *
 * Limitations: DOES NOT select Body when the running user lacks "Author Apex" — degrades to
 *              component discovery plus whatever TableEnumOrId alone can resolve, never a hard
 *              scan failure (mirrors OI_ApexClassScanner's own graceful degradation). The
 *              REFERENCES half is the SAME regex heuristic OI_ApexClassScanner documents, with
 *              the same caveats (misses dynamic Apex/interface indirection; can false-positive
 *              on a class name inside a comment or string literal) — the EXECUTES_ON half
 *              carries none of those caveats. Field-level dependencies WITHIN a trigger body
 *              (which fields it reads/writes) are not extracted — that needs real parsing, not
 *              identifier matching, and is deliberately out of scope. Always a full snapshot;
 *              LastModifiedDate is available but not wired as an incremental watermark yet,
 *              same documented state as OI_ApexClassScanner.
 */
public inherited sharing class OI_ApexTriggerScanner implements OI_IMetadataScanner {
    private static final String COMPONENT_KIND = 'ApexTrigger';
    private static final String OBJECT_COMPONENT_KIND = 'CustomObject';
    private static final String APEX_CLASS_COMPONENT_KIND = 'ApexClass';
    private static final String EXECUTES_ON_RELATIONSHIP_KIND = 'EXECUTES_ON';
    private static final String REFERENCES_RELATIONSHIP_KIND = 'REFERENCES';
    private static final Pattern IDENTIFIER_PATTERN = Pattern.compile('[A-Za-z_][A-Za-z0-9_]*');
    /** Matches the mandatory `trigger <Name> on <Object>` header. CASE_INSENSITIVE because Apex keywords are; \s+ rather than a single space since the declaration may wrap across lines. */
    private static final Pattern TRIGGER_DECLARATION_PATTERN = Pattern.compile('(?i)\\btrigger\\s+[A-Za-z0-9_]+\\s+on\\s+([A-Za-z0-9_]+)');

    public OI_DiscoveryBatch scan(OI_ScanContext context) {
        Boolean bodyAccessible = true;
        List<ApexTrigger> triggers;
        try {
            triggers = [
                SELECT Name, NamespacePrefix, ApiVersion, Status, IsValid, TableEnumOrId, LengthWithoutComments, BodyCrc, Body,
                    UsageBeforeInsert, UsageAfterInsert, UsageBeforeUpdate, UsageAfterUpdate, UsageBeforeDelete, UsageAfterDelete, UsageAfterUndelete
                FROM ApexTrigger
            ];
        } catch (System.QueryException noAuthorApexAccess) {
            bodyAccessible = false;
            triggers = [
                SELECT Name, NamespacePrefix, ApiVersion, Status, IsValid, TableEnumOrId, LengthWithoutComments, BodyCrc,
                    UsageBeforeInsert, UsageAfterInsert, UsageBeforeUpdate, UsageAfterUpdate, UsageBeforeDelete, UsageAfterDelete, UsageAfterUndelete
                FROM ApexTrigger
            ];
        }

        List<OI_DiscoveredComponent> components = new List<OI_DiscoveredComponent>();
        Map<String, String> componentKeyByTriggerName = new Map<String, String>();
        for (ApexTrigger apexTrigger : triggers) {
            OI_DiscoveredComponent component = toComponent(apexTrigger);
            components.add(component);
            componentKeyByTriggerName.put(apexTrigger.Name, component.componentKey);
        }

        Map<String, String> componentKeyByClassName = buildApexClassComponentKeys();

        List<OI_DiscoveredRelationship> relationships = new List<OI_DiscoveredRelationship>();
        for (ApexTrigger apexTrigger : triggers) {
            String fromComponentKey = componentKeyByTriggerName.get(apexTrigger.Name);
            OI_DiscoveredRelationship executesOn = buildExecutesOnRelationship(apexTrigger, fromComponentKey);
            if (executesOn != null) {
                relationships.add(executesOn);
            }
            if (bodyAccessible) {
                relationships.addAll(extractClassReferences(apexTrigger, fromComponentKey, componentKeyByClassName));
            }
        }

        return new OI_DiscoveryBatch(context.scanTaskId, COMPONENT_KIND, components, relationships, true, 1);
    }

    /**
     * The exact, declared trigger -> object dependency (see this class's own doc comment on
     * why this edge is categorically more trustworthy than a REFERENCES edge). Returns null —
     * no edge — when the object cannot be resolved to a real object in this org by either
     * path, rather than emitting a guess.
     */
    @TestVisible
    private OI_DiscoveredRelationship buildExecutesOnRelationship(ApexTrigger apexTrigger, String fromComponentKey) {
        String objectApiName = resolveObjectApiName(apexTrigger);
        if (String.isBlank(objectApiName) || String.isBlank(fromComponentKey)) {
            return null;
        }
        String objectNamespace = OI_ComponentKeyUtil.extractNamespaceFromApiName(objectApiName);
        String toComponentKey = OI_ComponentKeyUtil.build(OBJECT_COMPONENT_KIND, objectNamespace, objectApiName);
        return new OI_DiscoveredRelationship(
            fromComponentKey + '::' + EXECUTES_ON_RELATIONSHIP_KIND + '::' + toComponentKey,
            EXECUTES_ON_RELATIONSHIP_KIND,
            fromComponentKey,
            toComponentKey,
            new Map<String, Object>{ 'triggerEvents' => describeTriggerEvents(apexTrigger) }
        );
    }

    /** Declaration first, TableEnumOrId second — both validated against the global describe. See the class doc comment for why that order, and why an unresolvable object yields no edge. */
    @TestVisible
    private String resolveObjectApiName(ApexTrigger apexTrigger) {
        if (String.isNotBlank(apexTrigger.Body)) {
            Matcher declarationMatcher = TRIGGER_DECLARATION_PATTERN.matcher(apexTrigger.Body);
            if (declarationMatcher.find()) {
                String declared = canonicalObjectName(declarationMatcher.group(1));
                if (declared != null) {
                    return declared;
                }
            }
        }
        return canonicalObjectName(apexTrigger.TableEnumOrId);
    }

    /** Delegates to the shared resolver every object-referencing Scanner uses — see OI_ScannerObjectResolver for the casing and dangling-edge reasoning this centralizes. */
    private String canonicalObjectName(String candidate) {
        return OI_ScannerObjectResolver.canonicalInScopeName(candidate);
    }

    /** Same heuristic, same caveats, as OI_ApexClassScanner.extractReferences — deduplicated per trigger, and a trigger can never reference itself (different componentKind namespace entirely). */
    private List<OI_DiscoveredRelationship> extractClassReferences(ApexTrigger apexTrigger, String fromComponentKey, Map<String, String> componentKeyByClassName) {
        List<OI_DiscoveredRelationship> found = new List<OI_DiscoveredRelationship>();
        if (String.isBlank(apexTrigger.Body) || String.isBlank(fromComponentKey) || componentKeyByClassName.isEmpty()) {
            return found;
        }
        Set<String> referencedClassNames = new Set<String>();
        Matcher tokenMatcher = IDENTIFIER_PATTERN.matcher(apexTrigger.Body);
        while (tokenMatcher.find()) {
            String token = tokenMatcher.group();
            if (componentKeyByClassName.containsKey(token)) {
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

    /**
     * Class names are needed only to recognize which identifier tokens in a trigger body are
     * real Apex classes — Body is deliberately NOT selected here (this scanner never needs
     * class bodies, only their names), keeping the query cheap and avoiding a second reason to
     * require "Author Apex" beyond the trigger bodies themselves.
     */
    private Map<String, String> buildApexClassComponentKeys() {
        Map<String, String> componentKeyByClassName = new Map<String, String>();
        for (ApexClass apexClass : [SELECT Name, NamespacePrefix FROM ApexClass]) {
            String namespace = String.isBlank(apexClass.NamespacePrefix) ? null : apexClass.NamespacePrefix;
            String fullyQualifiedName = namespace == null ? apexClass.Name : namespace + '.' + apexClass.Name;
            componentKeyByClassName.put(apexClass.Name, OI_ComponentKeyUtil.build(APEX_CLASS_COMPONENT_KIND, namespace, fullyQualifiedName));
        }
        return componentKeyByClassName;
    }

    /** The trigger's declared events as a compact, display-ready list (e.g. "before insert", "after update") — carried on the EXECUTES_ON edge so the UI can answer "fires on WHAT operation" without re-reading the trigger. */
    private List<String> describeTriggerEvents(ApexTrigger apexTrigger) {
        List<String> events = new List<String>();
        if (apexTrigger.UsageBeforeInsert == true) {
            events.add('before insert');
        }
        if (apexTrigger.UsageAfterInsert == true) {
            events.add('after insert');
        }
        if (apexTrigger.UsageBeforeUpdate == true) {
            events.add('before update');
        }
        if (apexTrigger.UsageAfterUpdate == true) {
            events.add('after update');
        }
        if (apexTrigger.UsageBeforeDelete == true) {
            events.add('before delete');
        }
        if (apexTrigger.UsageAfterDelete == true) {
            events.add('after delete');
        }
        if (apexTrigger.UsageAfterUndelete == true) {
            events.add('after undelete');
        }
        return events;
    }

    private OI_DiscoveredComponent toComponent(ApexTrigger apexTrigger) {
        String namespace = String.isBlank(apexTrigger.NamespacePrefix) ? null : apexTrigger.NamespacePrefix;
        String fullyQualifiedName = namespace == null ? apexTrigger.Name : namespace + '.' + apexTrigger.Name;
        Map<String, Object> attributes = new Map<String, Object>{
            'apiVersion' => apexTrigger.ApiVersion,
            'status' => apexTrigger.Status,
            'isValid' => apexTrigger.IsValid,
            'objectApiName' => resolveObjectApiName(apexTrigger),
            'triggerEvents' => describeTriggerEvents(apexTrigger),
            'lengthWithoutComments' => apexTrigger.LengthWithoutComments,
            'bodyCrc' => apexTrigger.BodyCrc
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
