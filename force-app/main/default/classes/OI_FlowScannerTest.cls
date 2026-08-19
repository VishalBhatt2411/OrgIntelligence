/**
 * Purpose: Verifies OI_FlowScanner (Backlog DE-8, partial) discovers Flows and emits only
 *          well-formed, non-dangling EXECUTES_ON edges toward their trigger objects.
 *
 * Test data strategy: FlowDefinitionView is a read-only platform view — a test cannot insert a
 *          Flow, and this package ships none, so assertions are written as PROPERTIES that must
 *          hold over whatever Flows the org actually contains (including none at all). That is
 *          weaker than a fixture-based test and is called out honestly here rather than
 *          disguised: what these tests genuinely guarantee is that the scanner never emits a
 *          malformed or dangling edge and never fails on an org regardless of its Flow
 *          population — not that a specific Flow produces a specific edge.
 */
@isTest
private class OI_FlowScannerTest {
    @isTest
    static void testScanReturnsAWellFormedBatchRegardlessOfHowManyFlowsTheOrgHas() {
        OI_DiscoveryBatch batch = new OI_FlowScanner().scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        System.assertEquals('Flow', batch.componentKind);
        System.assertEquals(true, batch.isFullSnapshot);
        System.assertNotEquals(null, batch.components, 'An org with no Flows must still yield an empty batch, never a null or a failure.');
        System.assertNotEquals(null, batch.relationships);
    }

    /** Every discovered Flow must carry a usable identity — the invariant OI_MutationGenerator depends on to build a nodeKey at all. */
    @isTest
    static void testEveryDiscoveredFlowHasACompleteComponentIdentity() {
        OI_DiscoveryBatch batch = new OI_FlowScanner().scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        for (OI_DiscoveredComponent component : batch.components) {
            System.assertEquals('Flow', component.componentKind);
            System.assert(String.isNotBlank(component.componentKey), 'Every Flow component needs a componentKey.');
            System.assert(String.isNotBlank(component.fullyQualifiedName), 'Every Flow component needs a fullyQualifiedName.');
            System.assert(String.isNotBlank(component.rawChecksum), 'Every Flow component needs a checksum for change detection.');
            System.assertEquals('SOQL', component.sourceApi);
        }
    }

    /**
     * The dangling-edge guard, stated as a property over the whole batch: an EXECUTES_ON edge
     * may only target an object OI_ObjectScanner would also create a node for. FlowDefinitionView
     * genuinely surfaces trigger objects this platform does not node-ify (Platform Events being
     * the common case), so this is a real risk, not a theoretical one.
     */
    @isTest
    static void testEveryExecutesOnEdgeTargetsAnObjectTheObjectScannerWouldAlsoCreate() {
        OI_DiscoveryBatch batch = new OI_FlowScanner().scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        Set<String> flowComponentKeys = new Set<String>();
        for (OI_DiscoveredComponent component : batch.components) {
            flowComponentKeys.add(component.componentKey);
        }

        for (OI_DiscoveredRelationship relationship : batch.relationships) {
            System.assertEquals('EXECUTES_ON', relationship.relationshipKind, 'This scanner emits no relationship kind other than EXECUTES_ON today.');
            System.assert(flowComponentKeys.contains(relationship.fromComponentKey), 'Every edge must originate from a Flow this same batch discovered.');

            OI_ComponentKeyUtil.ParsedComponentKey parsed = OI_ComponentKeyUtil.parse(relationship.toComponentKey);
            System.assertNotEquals(null, parsed);
            System.assertEquals('CustomObject', parsed.componentKind);

            /** Asserted through the shared resolver (whose memo makes this cheap regardless of edge count) rather than by re-deriving a describe per edge — see OI_PermissionSetScannerTest's equivalent assertion for the CPU-limit incident that motivated this. */
            System.assertEquals(
                parsed.fullyQualifiedName,
                OI_ScannerObjectResolver.canonicalInScopeName(parsed.fullyQualifiedName),
                'EXECUTES_ON target ' + parsed.fullyQualifiedName + ' must resolve to itself as an in-scope, node-producing object, or the edge would dangle.'
            );
        }
    }

    /** A non-record-triggered Flow (screen/autolaunched/scheduled) has no trigger object and must simply produce no edge — absence of an edge means "not record-triggered," never a swallowed failure. */
    @isTest
    static void testFlowsWithoutATriggerObjectProduceNoEdgeRatherThanAFabricatedOne() {
        OI_DiscoveryBatch batch = new OI_FlowScanner().scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        Set<String> keysWithAnEdge = new Set<String>();
        for (OI_DiscoveredRelationship relationship : batch.relationships) {
            keysWithAnEdge.add(relationship.fromComponentKey);
        }
        for (OI_DiscoveredComponent component : batch.components) {
            Object triggerObject = component.rawAttributes.get('triggerObjectApiName');
            if (triggerObject == null) {
                System.assert(!keysWithAnEdge.contains(component.componentKey), 'A Flow with no resolved trigger object must have no EXECUTES_ON edge: ' + component.fullyQualifiedName);
            }
        }
    }

    @isTest
    static void testComponentIdentityIsDeterministicAcrossRepeatedScans() {
        OI_FlowScanner scanner = new OI_FlowScanner();
        OI_DiscoveryBatch first = scanner.scan(new OI_ScanContext(null, 200, null, 'SOQL'));
        OI_DiscoveryBatch second = scanner.scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        Map<String, String> checksumByKey = new Map<String, String>();
        for (OI_DiscoveredComponent component : first.components) {
            checksumByKey.put(component.componentKey, component.rawChecksum);
        }
        for (OI_DiscoveredComponent component : second.components) {
            System.assert(checksumByKey.containsKey(component.componentKey), 'A repeated scan must produce identical componentKeys — an unstable key would create a duplicate node every scan.');
            System.assertEquals(checksumByKey.get(component.componentKey), component.rawChecksum, 'An unchanged Flow must produce an identical checksum, or every scan would spuriously version it.');
        }
    }
}
