/**
 * Purpose: Verifies OI_MutationGenerator's real translation mechanics (MetadataScanner.md
 *          §15) — deterministic nodeKey/edgeKey derivation, cross-batch parentKey/edge
 *          endpoint resolution, and retire-detection gated on isFullSnapshot.
 */
@isTest
private class OI_MutationGeneratorTest {
    private static OI_GraphEngine buildEngine(OI_FakeGraphStorageProvider fake) {
        OI_GraphRepository repo = new OI_GraphRepository(fake, fake);
        return new OI_GraphEngine(new OI_GraphBuilder(repo), new OI_GraphTraversal(repo), repo, new OI_GraphSerializer(), new OI_GraphCache());
    }

    @isTest
    static void testEmptyBatchIsANoOp() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_MutationGenerator generator = new OI_MutationGenerator(buildEngine(fake));
        generator.translateAndIngest(new OI_DiscoveryBatch(null, 'CustomObject', new List<OI_DiscoveredComponent>(), new List<OI_DiscoveredRelationship>(), true, 0));
        System.assertEquals(0, fake.versionsByKey.size());
    }

    @isTest
    static void testSimpleComponentBecomesAGraphNode() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_MutationGenerator generator = new OI_MutationGenerator(buildEngine(fake));
        OI_DiscoveredComponent component = new OI_DiscoveredComponent(
            OI_ComponentKeyUtil.build('CustomObject', null, 'Account'),
            'CustomObject',
            'Account',
            null,
            'Describe',
            new Map<String, Object>{ 'custom' => false },
            'checksumA',
            null,
            null
        );
        generator.translateAndIngest(
            new OI_DiscoveryBatch(null, 'CustomObject', new List<OI_DiscoveredComponent>{ component }, new List<OI_DiscoveredRelationship>(), false, 1)
        );
        System.assertEquals(1, fake.versionsByKey.size());
        for (OI_VersionRecord record : fake.versionsByKey.values()) {
            System.assertEquals('SalesforceMetadata.CustomObject', record.typeKey);
            System.assertEquals('checksumA', record.checksum);
        }
    }

    /**
     * The Hierarchy Visualizer's Detail Panel needs Label and API Name to be genuinely
     * distinct — before this fix, Label__c was set to fullyQualifiedName (the API name),
     * duplicating Secondary_Key__c exactly. This verifies the friendly Describe label a
     * Scanner captures in rawAttributes.label ("Owner ID") is what actually lands in
     * Label__c, while Secondary_Key__c independently keeps the API name ("Account.OwnerId").
     */
    @isTest
    static void testNodeLabelUsesFriendlyDescribeLabelNotApiName() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_MutationGenerator generator = new OI_MutationGenerator(buildEngine(fake));
        OI_DiscoveredComponent component = new OI_DiscoveredComponent(
            OI_ComponentKeyUtil.build('CustomField', null, 'Account.OwnerId'),
            'CustomField',
            'Account.OwnerId',
            null,
            'Describe',
            new Map<String, Object>{ 'label' => 'Owner ID', 'type' => 'REFERENCE' },
            'checksumOwner',
            null,
            null
        );
        generator.translateAndIngest(
            new OI_DiscoveryBatch(null, 'CustomField', new List<OI_DiscoveredComponent>{ component }, new List<OI_DiscoveredRelationship>(), false, 1)
        );

        OI_VersionRecord node = fake.versionsByKey.values()[0];
        System.assertEquals('Owner ID', node.label, 'Label must be the friendly Describe label, not the API name.');
        System.assertEquals('Account.OwnerId', node.secondaryKey, 'Secondary_Key__c must independently keep the API name.');
    }

    /**
     * A componentKind with no captured 'label' attribute (e.g. ApexClass, which has no
     * separate friendly-label concept) must still fall back to fullyQualifiedName — never a
     * blank/null label.
     */
    @isTest
    static void testNodeLabelFallsBackToFullyQualifiedNameWhenNoLabelAttributeCaptured() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_MutationGenerator generator = new OI_MutationGenerator(buildEngine(fake));
        OI_DiscoveredComponent component = new OI_DiscoveredComponent(
            OI_ComponentKeyUtil.build('ApexClass', null, 'MyOtherClass'),
            'ApexClass',
            'MyOtherClass',
            null,
            'Describe',
            new Map<String, Object>{ 'status' => 'Active' },
            'checksumClass',
            null,
            null
        );
        generator.translateAndIngest(
            new OI_DiscoveryBatch(null, 'ApexClass', new List<OI_DiscoveredComponent>{ component }, new List<OI_DiscoveredRelationship>(), false, 1)
        );

        OI_VersionRecord node = fake.versionsByKey.values()[0];
        System.assertEquals('MyOtherClass', node.label);
    }

    @isTest
    static void testRepeatedScanOfIdenticalComponentProducesSameIdentityAndNoNewVersion() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphEngine engine = buildEngine(fake);
        OI_MutationGenerator generator1 = new OI_MutationGenerator(engine);
        OI_MutationGenerator generator2 = new OI_MutationGenerator(engine);
        OI_DiscoveredComponent component = new OI_DiscoveredComponent(
            OI_ComponentKeyUtil.build('ApexClass', null, 'MyClass'),
            'ApexClass',
            'MyClass',
            null,
            'Describe',
            new Map<String, Object>{ 'status' => 'Active' },
            'sameChecksum',
            null,
            null
        );
        generator1.translateAndIngest(
            new OI_DiscoveryBatch(null, 'ApexClass', new List<OI_DiscoveredComponent>{ component }, new List<OI_DiscoveredRelationship>(), false, 1)
        );
        System.assertEquals(1, fake.versionsByKey.size());
        String firstNodeKey = new List<String>(fake.versionsByKey.keySet())[0];
        Integer firstVersionNumber = fake.versionsByKey.get(firstNodeKey).versionNumber;

        generator2.translateAndIngest(
            new OI_DiscoveryBatch(null, 'ApexClass', new List<OI_DiscoveredComponent>{ component }, new List<OI_DiscoveredRelationship>(), false, 1)
        );

        System.assertEquals(1, fake.versionsByKey.size(), 'The same metadata component scanned twice must resolve to the same node identity, not a second node.');
        System.assertEquals(firstVersionNumber, fake.versionsByKey.get(firstNodeKey).versionNumber, 'An unchanged checksum must not create a new version.');
    }

    @isTest
    static void testParentComponentKeyResolvesAcrossBatchesToParentNodeKey() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphEngine engine = buildEngine(fake);
        OI_MutationGenerator objectGenerator = new OI_MutationGenerator(engine);
        OI_MutationGenerator fieldGenerator = new OI_MutationGenerator(engine);

        String objectComponentKey = OI_ComponentKeyUtil.build('CustomObject', null, 'Account');
        OI_DiscoveredComponent objectComponent = new OI_DiscoveredComponent(
            objectComponentKey,
            'CustomObject',
            'Account',
            null,
            'Describe',
            new Map<String, Object>(),
            'objChecksum',
            null,
            null
        );
        objectGenerator.translateAndIngest(
            new OI_DiscoveryBatch(null, 'CustomObject', new List<OI_DiscoveredComponent>{ objectComponent }, new List<OI_DiscoveredRelationship>(), true, 1)
        );
        String parentNodeKey = new List<String>(fake.versionsByKey.keySet())[0];

        OI_DiscoveredComponent fieldComponent = new OI_DiscoveredComponent(
            OI_ComponentKeyUtil.build('CustomField', null, 'Account.Industry__c'),
            'CustomField',
            'Account.Industry__c',
            null,
            'Describe',
            new Map<String, Object>(),
            'fieldChecksum',
            null,
            objectComponentKey
        );
        fieldGenerator.translateAndIngest(
            new OI_DiscoveryBatch(null, 'CustomField', new List<OI_DiscoveredComponent>{ fieldComponent }, new List<OI_DiscoveredRelationship>(), false, 1)
        );

        OI_VersionRecord fieldNode = null;
        for (OI_VersionRecord record : fake.versionsByKey.values()) {
            if (record.typeKey == 'SalesforceMetadata.CustomField') {
                fieldNode = record;
            }
        }
        System.assertNotEquals(null, fieldNode);
        System.assertEquals(parentNodeKey, fieldNode.parentKey, 'A parentComponentKey scanned in a different batch/task must resolve to the parent object\'s real nodeKey.');
    }

    @isTest
    static void testRelationshipBecomesEdgeBetweenResolvedEndpoints() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphEngine engine = buildEngine(fake);
        OI_MutationGenerator generator = new OI_MutationGenerator(engine);

        String objectComponentKey = OI_ComponentKeyUtil.build('CustomObject', null, 'Account');
        String fieldComponentKey = OI_ComponentKeyUtil.build('CustomField', null, 'Account.OwnerId');
        OI_DiscoveredComponent fieldComponent = new OI_DiscoveredComponent(
            fieldComponentKey,
            'CustomField',
            'Account.OwnerId',
            null,
            'Describe',
            new Map<String, Object>(),
            'checksum',
            null,
            objectComponentKey
        );
        OI_DiscoveredRelationship hasField = new OI_DiscoveredRelationship(
            OI_HashUtil.hash(objectComponentKey + '::HAS_FIELD::' + fieldComponentKey),
            'HAS_FIELD',
            objectComponentKey,
            fieldComponentKey,
            new Map<String, Object>()
        );
        generator.translateAndIngest(
            new OI_DiscoveryBatch(null, 'CustomField', new List<OI_DiscoveredComponent>{ fieldComponent }, new List<OI_DiscoveredRelationship>{ hasField }, false, 1)
        );

        Integer edgeCount = 0;
        for (OI_VersionRecord record : fake.versionsByKey.values()) {
            if (record.isEdge()) {
                edgeCount++;
                System.assertEquals('SalesforceMetadata.HAS_FIELD', record.typeKey);
            }
        }
        System.assertEquals(1, edgeCount);
    }

    @isTest
    static void testRelationshipWithUnresolvableEndpointIsSkippedWithoutError() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_MutationGenerator generator = new OI_MutationGenerator(buildEngine(fake));
        OI_DiscoveredRelationship danglingRelationship = new OI_DiscoveredRelationship('rk', 'LOOKUP_TO', null, null, new Map<String, Object>());
        generator.translateAndIngest(
            new OI_DiscoveryBatch(null, 'CustomField', new List<OI_DiscoveredComponent>(), new List<OI_DiscoveredRelationship>{ danglingRelationship }, false, 1)
        );
        System.assertEquals(0, fake.versionsByKey.size());
    }

    @isTest
    static void testFullSnapshotRetiresComponentsMissingFromTheLatestScan() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphEngine engine = buildEngine(fake);
        OI_MutationGenerator generator = new OI_MutationGenerator(engine);

        OI_DiscoveredComponent componentA = new OI_DiscoveredComponent(
            OI_ComponentKeyUtil.build('CustomObject', null, 'ObjA'),
            'CustomObject',
            'ObjA',
            null,
            'Describe',
            new Map<String, Object>(),
            'ca',
            null,
            null
        );
        OI_DiscoveredComponent componentB = new OI_DiscoveredComponent(
            OI_ComponentKeyUtil.build('CustomObject', null, 'ObjB'),
            'CustomObject',
            'ObjB',
            null,
            'Describe',
            new Map<String, Object>(),
            'cb',
            null,
            null
        );
        generator.translateAndIngest(
            new OI_DiscoveryBatch(
                null,
                'CustomObject',
                new List<OI_DiscoveredComponent>{ componentA, componentB },
                new List<OI_DiscoveredRelationship>(),
                true,
                1
            )
        );

        String nodeKeyB = null;
        for (String key : fake.versionsByKey.keySet()) {
            if (fake.versionsByKey.get(key).checksum == 'cb') {
                nodeKeyB = key;
            }
        }
        System.assertNotEquals(null, nodeKeyB);

        generator.translateAndIngest(
            new OI_DiscoveryBatch(null, 'CustomObject', new List<OI_DiscoveredComponent>{ componentA }, new List<OI_DiscoveredRelationship>(), true, 1)
        );

        System.assertEquals('Stale', fake.versionsByKey.get(nodeKeyB).state, 'A full-snapshot scan that no longer observes ObjB must retire it.');
    }

    @isTest
    static void testPartialSnapshotNeverRetiresAnything() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphEngine engine = buildEngine(fake);
        OI_MutationGenerator generator = new OI_MutationGenerator(engine);

        OI_DiscoveredComponent componentA = new OI_DiscoveredComponent(
            OI_ComponentKeyUtil.build('CustomObject', null, 'ObjC'),
            'CustomObject',
            'ObjC',
            null,
            'Describe',
            new Map<String, Object>(),
            'cc',
            null,
            null
        );
        generator.translateAndIngest(
            new OI_DiscoveryBatch(null, 'CustomObject', new List<OI_DiscoveredComponent>{ componentA }, new List<OI_DiscoveredRelationship>(), true, 1)
        );
        String nodeKeyC = new List<String>(fake.versionsByKey.keySet())[0];

        generator.translateAndIngest(
            new OI_DiscoveryBatch(null, 'CustomObject', new List<OI_DiscoveredComponent>(), new List<OI_DiscoveredRelationship>(), false, 1)
        );

        System.assertEquals('Active', fake.versionsByKey.get(nodeKeyC).state, 'A partial (non-full-snapshot) scan must never trigger a retirement.');
    }

    /**
     * findMissingKeys is the read-only half of retire-detection (Sprint 9.1, replacing
     * MS-4b's combined-read-and-retire retireMissingKeysPage). It must find every Active
     * key not in observedNodeKeys in one call, regardless of how many pages the read side
     * needs internally — the whole point of splitting read from write is that the cheap,
     * DML-free read never needs chunking across transactions, only the write does.
     */
    @isTest
    static void testFindMissingKeysReturnsEveryActiveKeyNotObservedAcrossMultipleReadPages() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphEngine engine = buildEngine(fake);
        OI_MutationGenerator generator = new OI_MutationGenerator(engine);

        Integer totalNodes = 120;
        for (Integer i = 0; i < totalNodes; i++) {
            String key = 'bulkRetireKey' + i;
            fake.versionsByKey.put(
                key,
                new OI_VersionRecord(key, key + '::v1', 1, 'SalesforceMetadata.CustomObject', 'Label' + i, null, null, new Map<String, Object>(), 'c' + i, 'Active', null, null, null, true, null, null)
            );
        }

        List<String> missingKeys = generator.findMissingKeys('CustomObject', new Set<String>());

        System.assertEquals(totalNodes, missingKeys.size(), 'Every Active key must be found missing when observedNodeKeys is empty, regardless of internal read pagination.');
    }

    /**
     * MS-4b's original guarantee (Sprint 9), preserved under the Sprint 9.1 split: a
     * retirement wave larger than one Batch Apex scope must be fully processed across
     * multiple retireKeys calls, never in one unbounded pass. Nodes are seeded directly
     * into the fake's store (bypassing DML entirely), but each retirement still costs one
     * real Database.setSavepoint() call inside OI_GraphRepository.commitVersion — a
     * genuine platform DML-equivalent statement regardless of which storage provider is
     * injected. The two retireKeys calls below mirror exactly what
     * OI_ScanRetireDetectionBatchable's two execute() scopes would do for 120 keys at
     * CHUNK_SIZE=60; both calls share this one test-method transaction (chunking only
     * creates separate governor-limit budgets across separate transactions/Batch Apex
     * scopes — a plain loop within one test method is still one transaction), so this is
     * capped at 120 nodes (safely under the 150-statement ceiling with margin) rather than
     * a literal 200+. Genuine >150-retirement volume in one scan is validated for real in
     * the Sprint 9.1 large-scale sandbox run (outside test context — see the deliverables
     * report), which is the only context where that scale can actually be exercised
     * end-to-end.
     */
    @isTest
    static void testRetireKeysProcessesALargeRetirementWaveAcrossMultipleChunkedCalls() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphEngine engine = buildEngine(fake);
        OI_MutationGenerator generator = new OI_MutationGenerator(engine);

        Integer totalNodes = 120;
        List<String> allKeys = new List<String>();
        for (Integer i = 0; i < totalNodes; i++) {
            String key = 'bulkRetireKey' + i;
            allKeys.add(key);
            fake.versionsByKey.put(
                key,
                new OI_VersionRecord(key, key + '::v1', 1, 'SalesforceMetadata.CustomObject', 'Label' + i, null, null, new Map<String, Object>(), 'c' + i, 'Active', null, null, null, true, null, null)
            );
        }

        List<String> firstChunk = new List<String>();
        List<String> secondChunk = new List<String>();
        for (Integer i = 0; i < allKeys.size(); i++) {
            (i < 60 ? firstChunk : secondChunk).add(allKeys[i]);
        }
        generator.retireKeys(firstChunk, UserInfo.getUserId());
        generator.retireKeys(secondChunk, UserInfo.getUserId());

        Integer staleCount = 0;
        for (OI_VersionRecord record : fake.versionsByKey.values()) {
            if (record.state == 'Stale') {
                staleCount++;
            }
        }
        System.assertEquals(totalNodes, staleCount, 'Every one of the 120 nodes must be retired across the chunked calls — none skipped, none double-processed.');
    }
}
