/**
 * Purpose: Verifies OI_DependencyEngineService's forward/reverse Impact Analysis, cycle
 *          detection, caching, and DE-7 invalidation — using real DML against
 *          OI_Graph_Node__c/OI_Graph_Edge__c/OI_Impact_Cache__c (matching
 *          OI_GraphTraversalTest's own established convention, since this service reads the
 *          graph through OI_GraphEngine's real-SOQL path).
 */
@isTest
private class OI_DependencyEngineServiceTest {
    @isTest
    static void testGetImpactForwardDirectionFindsOnlyOutgoingDependencies() {
        insertClassNode('a', 'Class A');
        insertClassNode('b', 'Class B');
        insertClassNode('c', 'Class C');
        insertReferencesEdge('a', 'b');
        insertReferencesEdge('c', 'a');

        OI_ImpactResult result = new OI_DependencyEngineService().getImpact('a', 'forward', 3);

        System.assertEquals('a', result.rootNodeKey);
        System.assertEquals('forward', result.direction);
        System.assertEquals(1, result.affectedComponents.size(), 'Forward from a must find only b (outgoing), never c (which merely points at a).');
        System.assertEquals('b', result.affectedComponents[0].nodeKey);
        System.assertEquals(1, result.affectedComponents[0].hopDistance);
        System.assertNotEquals(null, result.coverageCaveat, 'Every result must carry the honest coverage caveat (Apex-only today) — never silently omitted.');
    }

    @isTest
    static void testGetImpactReverseDirectionFindsOnlyIncomingDependents() {
        insertClassNode('a', 'Class A');
        insertClassNode('b', 'Class B');
        insertClassNode('c', 'Class C');
        insertReferencesEdge('a', 'b');
        insertReferencesEdge('c', 'a');

        OI_ImpactResult result = new OI_DependencyEngineService().getImpact('a', 'reverse', 3);

        System.assertEquals('reverse', result.direction);
        System.assertEquals(1, result.affectedComponents.size(), 'Reverse from a ("what depends on a") must find only c, never b (which a itself points at).');
        System.assertEquals('c', result.affectedComponents[0].nodeKey);
    }

    @isTest
    static void testGetImpactRespectsRequestedDepth() {
        insertClassNode('a', 'Class A');
        insertClassNode('b', 'Class B');
        insertClassNode('c', 'Class C');
        insertReferencesEdge('a', 'b');
        insertReferencesEdge('b', 'c');

        OI_ImpactResult result = new OI_DependencyEngineService().getImpact('a', 'forward', 1);

        Set<String> keys = new Set<String>();
        for (OI_AffectedComponent component : result.affectedComponents) {
            keys.add(component.nodeKey);
        }
        System.assertEquals(new Set<String>{ 'b' }, keys, 'A requested depth of 1 must not reach c, two hops away.');
    }

    /**
     * The required, non-optional test case (mirroring GraphUI.md §13's diamond-subgraph
     * mandate, applied here to cycle detection): a real cyclic Apex-flavored fixture,
     * A -> B -> C -> A, must terminate (BFS's own visited-set guard, exercised end-to-end
     * through this service) and correctly flag every participant.
     */
    @isTest
    static void testCyclicDependencyIsDetectedOnEveryParticipantAndTraversalTerminates() {
        insertClassNode('a', 'Class A');
        insertClassNode('b', 'Class B');
        insertClassNode('c', 'Class C');
        insertReferencesEdge('a', 'b');
        insertReferencesEdge('b', 'c');
        insertReferencesEdge('c', 'a');

        OI_ImpactResult result = new OI_DependencyEngineService().getImpact('a', 'forward', 5);

        Set<String> seenKeys = new Set<String>();
        for (OI_AffectedComponent component : result.affectedComponents) {
            System.assert(!seenKeys.contains(component.nodeKey), 'Each node on the cycle must appear exactly once — an unterminated traversal would duplicate or hang.');
            seenKeys.add(component.nodeKey);
            System.assertEquals(true, component.isInCycle, 'Every node on the A->B->C->A cycle must be flagged as a cycle participant.');
        }
        System.assertEquals(new Set<String>{ 'b', 'c' }, seenKeys, 'affectedComponents excludes the root itself (a) — b and c are the two other nodes on the cycle.');
    }

    /**
     * DE-13's core assertion — the question the user could NOT get an answer to before this
     * change: "what fires on this object?" Reverse impact from an Object must surface the
     * Trigger that executes on it, which requires the traversal to follow EXECUTES_ON, not
     * just REFERENCES. Before DE-13 this returned zero affected components (the edge type was
     * simply not in the allow-list), which read as "Impact Analysis does nothing" even though
     * the traversal itself was working correctly all along.
     */
    @isTest
    static void testReverseImpactOnAnObjectFindsTheTriggerThatExecutesOnIt() {
        insertNodeOfType('acct', 'Account', 'SalesforceMetadata.CustomObject');
        insertNodeOfType('trg', 'AccountTrigger', 'SalesforceMetadata.ApexTrigger');
        insertExecutesOnEdge('trg', 'acct');

        OI_ImpactResult result = new OI_DependencyEngineService().getImpact('acct', 'reverse', 3);

        System.assertEquals(1, result.affectedComponents.size(), 'Reverse impact on an Object must find the Trigger that fires on it via the EXECUTES_ON edge.');
        System.assertEquals('trg', result.affectedComponents[0].nodeKey);
        System.assertEquals(1, result.affectedComponents[0].hopDistance);
    }

    /**
     * Both edge types unioned into ONE traversal rather than traversed in isolation: forward
     * impact from a Trigger ("what does this trigger depend on") must reach both the Object it
     * fires on (EXECUTES_ON) and the handler class it calls (REFERENCES), in the same result.
     *
     * Deliberately NOT asserted here, because it would be semantically wrong: reverse impact
     * from the Object does not reach the handler class. The handler is something the trigger
     * DEPENDS ON, not something that depends on the object — dependency direction is not
     * transitive across a change of role like that, and a test asserting otherwise would be
     * encoding a bug as expected behavior.
     */
    @isTest
    static void testForwardImpactFromATriggerUnionsBothEdgeTypesInOneResult() {
        insertNodeOfType('acct', 'Account', 'SalesforceMetadata.CustomObject');
        insertNodeOfType('trg', 'AccountTrigger', 'SalesforceMetadata.ApexTrigger');
        insertClassNode('handler', 'AccountTriggerHandler');
        insertExecutesOnEdge('trg', 'acct');
        insertReferencesEdge('trg', 'handler');

        OI_ImpactResult result = new OI_DependencyEngineService().getImpact('trg', 'forward', 3);

        Map<String, Integer> hopByKey = new Map<String, Integer>();
        for (OI_AffectedComponent component : result.affectedComponents) {
            hopByKey.put(component.nodeKey, component.hopDistance);
        }
        System.assertEquals(
            new Set<String>{ 'acct', 'handler' },
            hopByKey.keySet(),
            'Forward impact from the trigger must find both the object it fires on (EXECUTES_ON) and the class it calls (REFERENCES) — the two edge types must form one dependency graph, not two separate ones.'
        );
        System.assertEquals(1, hopByKey.get('acct'));
        System.assertEquals(1, hopByKey.get('handler'));
    }

    @isTest
    static void testGetImpactThrowsValidationExceptionForABlankNodeKey() {
        try {
            new OI_DependencyEngineService().getImpact('', 'forward', 3);
            System.assert(false, 'A blank node key must be rejected, never silently traversed.');
        } catch (OI_ValidationException expected) {
            System.assert(expected.getMessage().contains('node key'));
        }
    }

    @isTest
    static void testGetImpactServesFromCacheOnASecondCallWithoutRecomputing() {
        insertClassNode('a', 'Class A');
        insertClassNode('b', 'Class B');
        insertReferencesEdge('a', 'b');

        OI_DependencyEngineService service = new OI_DependencyEngineService();
        OI_ImpactResult first = service.getImpact('a', 'forward', 3);
        System.assertEquals(1, first.affectedComponents.size());

        List<OI_Impact_Cache__c> cacheRows = [SELECT Id, Manual_Test_Json__c FROM OI_Impact_Cache__c];
        System.assertEquals(1, cacheRows.size(), 'Precondition: exactly one cache row must have been written by the first (miss) call.');
        Map<String, Object> cachedPayload = (Map<String, Object>) JSON.deserializeUntyped(cacheRows[0].Manual_Test_Json__c);
        cachedPayload.put('coverageCaveat', 'SENTINEL-FROM-CACHE');
        cacheRows[0].Manual_Test_Json__c = JSON.serialize(cachedPayload);
        update cacheRows[0];

        OI_ImpactResult second = service.getImpact('a', 'forward', 3);
        System.assertEquals('SENTINEL-FROM-CACHE', second.coverageCaveat, 'A second call within the TTL must be served from the cache, not recomputed against the live graph.');
    }

    @isTest
    static void testInvalidateForScanDeltaEvictsTheRootsCacheRowAndItsOneHopNeighbor() {
        insertClassNode('a', 'Class A');
        insertClassNode('b', 'Class B');
        insertClassNode('c', 'Class C');
        insertReferencesEdge('a', 'b');

        OI_DependencyEngineService service = new OI_DependencyEngineService();
        service.getImpact('a', 'forward', 3);
        service.getImpact('c', 'forward', 3);
        System.assertEquals(2, [SELECT COUNT() FROM OI_Impact_Cache__c]);

        service.invalidateForScanDelta(new Set<String>{ 'b' });

        System.assertEquals(
            0,
            [SELECT COUNT() FROM OI_Impact_Cache__c WHERE Root_Node_Key__c = 'a'],
            'a has a current edge to b, so a\'s cached result must be evicted when b changes.'
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM OI_Impact_Cache__c WHERE Root_Node_Key__c = 'c'],
            'c has no relationship to b at all, so c\'s cached result must survive untouched.'
        );
    }

    private static void insertClassNode(String nodeKey, String label) {
        insert new OI_Graph_Node__c(
            Node_Key__c = nodeKey,
            Node_Version_Key__c = nodeKey + '::v1',
            Version_Number__c = 1,
            Node_Type__c = 'SalesforceMetadata.ApexClass',
            Label__c = label,
            Secondary_Key__c = label,
            Checksum__c = nodeKey + '-checksum',
            State__c = 'Active',
            Is_Current__c = true
        );
    }

    private static void insertReferencesEdge(String fromKey, String toKey) {
        insertEdgeOfType(fromKey, toKey, 'SalesforceMetadata.REFERENCES');
    }

    private static void insertExecutesOnEdge(String fromKey, String toKey) {
        insertEdgeOfType(fromKey, toKey, 'SalesforceMetadata.EXECUTES_ON');
    }

    private static void insertEdgeOfType(String fromKey, String toKey, String edgeType) {
        insert new OI_Graph_Edge__c(
            Edge_Key__c = fromKey + '->' + toKey,
            Edge_Version_Key__c = fromKey + '->' + toKey + '::v1',
            Version_Number__c = 1,
            Edge_Type__c = edgeType,
            Source_Node_Key__c = fromKey,
            Target_Node_Key__c = toKey,
            State__c = 'Active',
            Is_Current__c = true
        );
    }

    private static void insertNodeOfType(String nodeKey, String label, String nodeType) {
        insert new OI_Graph_Node__c(
            Node_Key__c = nodeKey,
            Node_Version_Key__c = nodeKey + '::v1',
            Version_Number__c = 1,
            Node_Type__c = nodeType,
            Label__c = label,
            Secondary_Key__c = label,
            Checksum__c = nodeKey + '-checksum',
            State__c = 'Active',
            Is_Current__c = true
        );
    }
}
