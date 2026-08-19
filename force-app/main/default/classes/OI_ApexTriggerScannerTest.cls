/**
 * Purpose: Verifies OI_ApexTriggerScanner (Backlog DE-9) discovers real deployed triggers,
 *          extracts the exact declared trigger -> object EXECUTES_ON dependency, extracts
 *          best-effort trigger -> Apex class REFERENCES dependencies, and — critically —
 *          never emits an edge pointing at an object OI_ObjectScanner would not create a node
 *          for (the dangling-edge case this package's own OI_LogEventTrigger really hits,
 *          since it fires on a Platform Event).
 *
 * Test data strategy: assertions run against THIS package's own real deployed metadata
 *          (OI_LogEventTrigger on OI_Log_Event__e, calling OI_LogEventTriggerHandler) rather
 *          than fixtures, mirroring OI_ApexClassScannerTest's approach — a scanner that reads
 *          the org's own metadata is most honestly tested against metadata that genuinely
 *          exists. Object-resolution branches that no real trigger in this package exercises
 *          (a standard object, a lowercase declaration, an unknown object) are covered by
 *          driving the resolution method with in-memory ApexTrigger instances, since a test
 *          cannot deploy a new trigger to exercise them.
 */
@isTest
private class OI_ApexTriggerScannerTest {
    @isTest
    static void testScanDiscoversThisPackagesOwnDeployedTrigger() {
        OI_ApexTriggerScanner scanner = new OI_ApexTriggerScanner();
        OI_DiscoveryBatch batch = scanner.scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        System.assertEquals('ApexTrigger', batch.componentKind);
        System.assertEquals(true, batch.isFullSnapshot);

        OI_DiscoveredComponent logTrigger = findComponent(batch, 'OI_LogEventTrigger');
        System.assertNotEquals(null, logTrigger, 'Expected this package\'s own OI_LogEventTrigger to be discovered by a real scan.');
        System.assertEquals('SOQL', logTrigger.sourceApi);
        System.assertNotEquals(null, logTrigger.rawChecksum);
        System.assertEquals(new List<String>{ 'after insert' }, (List<String>) logTrigger.rawAttributes.get('triggerEvents'), 'OI_LogEventTrigger is declared "after insert" — the captured events must reflect the real declaration.');
    }

    /**
     * The dangling-edge guard, and the single most important assertion in this class:
     * OI_LogEventTrigger fires on OI_Log_Event__e, a Platform Event, which OI_ObjectScopeFilter
     * excludes — so OI_ObjectScanner never creates a node for it. Emitting EXECUTES_ON here
     * anyway would put an edge in the graph pointing at a nodeKey nothing ever creates, which
     * Impact Analysis would then report as an affected component with no node behind it.
     */
    @isTest
    static void testEmitsNoExecutesOnEdgeForATriggerOnAnObjectTheObjectScannerExcludes() {
        OI_ApexTriggerScanner scanner = new OI_ApexTriggerScanner();
        OI_DiscoveryBatch batch = scanner.scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        String triggerKey = componentKeyFor(batch, 'OI_LogEventTrigger');
        System.assertNotEquals(null, triggerKey, 'Precondition: OI_LogEventTrigger must have been discovered.');

        for (OI_DiscoveredRelationship relationship : batch.relationships) {
            if (relationship.fromComponentKey == triggerKey && relationship.relationshipKind == 'EXECUTES_ON') {
                System.assert(
                    false,
                    'OI_LogEventTrigger fires on the Platform Event OI_Log_Event__e, which OI_ObjectScopeFilter excludes from node creation — emitting an EXECUTES_ON edge to it would be a dangling edge. Found: ' + relationship.toComponentKey
                );
            }
        }
    }

    /** Every EXECUTES_ON edge this scanner emits, for any trigger in any org, must target an object that is genuinely in OI_ObjectScanner's scope — stated as a property over the whole batch rather than only for the one trigger above, so a future trigger added to this package cannot silently reintroduce dangling edges. */
    @isTest
    static void testEveryExecutesOnEdgeTargetsAnObjectTheObjectScannerWouldAlsoCreate() {
        OI_ApexTriggerScanner scanner = new OI_ApexTriggerScanner();
        OI_DiscoveryBatch batch = scanner.scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        for (OI_DiscoveredRelationship relationship : batch.relationships) {
            if (relationship.relationshipKind != 'EXECUTES_ON') {
                continue;
            }
            OI_ComponentKeyUtil.ParsedComponentKey parsed = OI_ComponentKeyUtil.parse(relationship.toComponentKey);
            System.assertNotEquals(null, parsed, 'An EXECUTES_ON target must be a parseable componentKey.');
            System.assertEquals('CustomObject', parsed.componentKind, 'An EXECUTES_ON edge must target a CustomObject component, never another kind.');

            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(parsed.fullyQualifiedName.toLowerCase());
            System.assertNotEquals(null, objectType, 'EXECUTES_ON target ' + parsed.fullyQualifiedName + ' must be a real object in this org.');
            System.assert(
                OI_ObjectScopeFilter.isInScope(objectType.getDescribe()),
                'EXECUTES_ON target ' + parsed.fullyQualifiedName + ' must be in OI_ObjectScanner\'s scope, or the edge would dangle.'
            );
        }
    }

    /** The real, deduplicated trigger -> Apex class dependency: OI_LogEventTrigger's body names OI_LogEventTriggerHandler, so Impact Analysis on that handler must be able to find the trigger. */
    @isTest
    static void testDiscoversARealDeduplicatedReferenceFromATriggerToTheHandlerClassItCalls() {
        OI_ApexTriggerScanner scanner = new OI_ApexTriggerScanner();
        OI_DiscoveryBatch batch = scanner.scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        String triggerKey = componentKeyFor(batch, 'OI_LogEventTrigger');
        System.assertNotEquals(null, triggerKey, 'Precondition: OI_LogEventTrigger must have been discovered.');
        String handlerKey = OI_ComponentKeyUtil.build('ApexClass', null, 'OI_LogEventTriggerHandler');

        Integer matchCount = 0;
        for (OI_DiscoveredRelationship relationship : batch.relationships) {
            if (relationship.fromComponentKey == triggerKey && relationship.toComponentKey == handlerKey) {
                matchCount++;
                System.assertEquals('REFERENCES', relationship.relationshipKind);
            }
        }
        System.assertEquals(1, matchCount, 'Expected exactly one deduplicated REFERENCES edge from OI_LogEventTrigger to the OI_LogEventTriggerHandler class it instantiates.');
    }

    /** A standard object named in the declaration resolves to its real, correctly-cased API name — the ordinary positive path no trigger in this package happens to exercise. */
    @isTest
    static void testResolvesAStandardObjectFromTheTriggerDeclaration() {
        OI_ApexTriggerScanner scanner = new OI_ApexTriggerScanner();
        ApexTrigger inMemory = new ApexTrigger(Name = 'FakeAccountTrigger', Body = 'trigger FakeAccountTrigger on Account (before insert) { }');

        System.assertEquals('Account', scanner.resolveObjectApiName(inMemory));
    }

    /**
     * Apex keywords and identifiers are case-insensitive, but componentKey/nodeKey derivation
     * is not — a trigger declared `on account` must still resolve to the same "Account" node
     * OI_ObjectScanner creates, or the edge would point at a node that never exists.
     */
    @isTest
    static void testCanonicalizesObjectNameCasingSoTheEdgeTargetsTheSameNodeTheObjectScannerCreates() {
        OI_ApexTriggerScanner scanner = new OI_ApexTriggerScanner();
        ApexTrigger inMemory = new ApexTrigger(Name = 'FakeLowercaseTrigger', Body = 'trigger FakeLowercaseTrigger on account (before update) { }');

        System.assertEquals('Account', scanner.resolveObjectApiName(inMemory), 'A lowercase declaration must canonicalize to the object\'s real API-name casing.');
    }

    /** An object this org does not have yields no name — and therefore no edge — rather than a fabricated one. */
    @isTest
    static void testResolvesToNullForAnObjectThisOrgDoesNotHave() {
        OI_ApexTriggerScanner scanner = new OI_ApexTriggerScanner();
        ApexTrigger inMemory = new ApexTrigger(Name = 'FakeUnknownTrigger', Body = 'trigger FakeUnknownTrigger on Definitely_Not_A_Real_Object__c (before insert) { }');

        System.assertEquals(null, scanner.resolveObjectApiName(inMemory));
        System.assertEquals(null, scanner.buildExecutesOnRelationship(inMemory, 'ApexTrigger::::FakeUnknownTrigger'), 'An unresolvable object must produce no relationship at all, never a guessed one.');
    }

    /** TableEnumOrId is the documented fallback when the declaration cannot be parsed (e.g. Body inaccessible without "Author Apex"). */
    @isTest
    static void testFallsBackToTableEnumOrIdWhenTheBodyIsUnavailable() {
        OI_ApexTriggerScanner scanner = new OI_ApexTriggerScanner();
        ApexTrigger inMemory = new ApexTrigger(Name = 'FakeNoBodyTrigger', TableEnumOrId = 'Account');

        System.assertEquals('Account', scanner.resolveObjectApiName(inMemory));
    }

    @isTest
    static void testComponentIdentityIsDeterministicAcrossRepeatedScans() {
        OI_ApexTriggerScanner scanner = new OI_ApexTriggerScanner();
        OI_DiscoveryBatch firstBatch = scanner.scan(new OI_ScanContext(null, 200, null, 'SOQL'));
        OI_DiscoveryBatch secondBatch = scanner.scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        OI_DiscoveredComponent first = findComponent(firstBatch, 'OI_LogEventTrigger');
        OI_DiscoveredComponent second = findComponent(secondBatch, 'OI_LogEventTrigger');

        System.assertNotEquals(null, first);
        System.assertEquals(first.componentKey, second.componentKey);
        System.assertEquals(first.rawChecksum, second.rawChecksum);
    }

    private static OI_DiscoveredComponent findComponent(OI_DiscoveryBatch batch, String nameSuffix) {
        for (OI_DiscoveredComponent component : batch.components) {
            if (component.fullyQualifiedName.endsWith(nameSuffix)) {
                return component;
            }
        }
        return null;
    }

    private static String componentKeyFor(OI_DiscoveryBatch batch, String nameSuffix) {
        OI_DiscoveredComponent component = findComponent(batch, nameSuffix);
        return component == null ? null : component.componentKey;
    }
}
