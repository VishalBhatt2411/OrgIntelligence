/**
 * Purpose: Verifies OI_GraphBuilder's three-way version decision and retire handling
 *          (GraphEngine.md §7) against the in-memory fake storage provider.
 */
@isTest
private class OI_GraphBuilderTest {
    /**
     * DE-7's foundation: the Builder is the only component that can tell a real change from a
     * liveness touch, so the delta it reports is what makes Impact Analysis cache invalidation
     * both correct and affordable. These four tests pin that contract.
     */
    @isTest
    static void testIngestReportsANewObservationAsAChangedNode() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));

        OI_IngestDelta delta = builder.ingest(
            new List<OI_GraphMutation>{
                OI_GraphMutation.upsertNode('d1', 'Test.Type', 'Label', null, null, new Map<String, Object>(), 'c1', null, UserInfo.getUserId())
            }
        );

        System.assertEquals(new Set<String>{ 'd1' }, delta.changedNodeKeys);
        System.assert(delta.impactedNodeKeys.contains('d1'));
        System.assertEquals(false, delta.isEmpty());
    }

    /**
     * The case that decides whether the impact cache is worth having at all: a rescan that
     * changes nothing must invalidate nothing. Reporting observations instead of changes here
     * would flush the entire cache on every scan.
     */
    @isTest
    static void testIngestReportsNoChangeForAnUnchangedRescan() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));
        Id runId = UserInfo.getUserId();
        builder.ingest(
            new List<OI_GraphMutation>{
                OI_GraphMutation.upsertNode('d2', 'Test.Type', 'Label', null, null, new Map<String, Object>(), 'same', null, runId)
            }
        );

        OI_IngestDelta secondDelta = builder.ingest(
            new List<OI_GraphMutation>{
                OI_GraphMutation.upsertNode('d2', 'Test.Type', 'Label', null, null, new Map<String, Object>(), 'same', null, runId)
            }
        );

        System.assertEquals(true, secondDelta.isEmpty(), 'An unchanged rescan is a liveness touch and must report zero changes, or the impact cache would be flushed on every scan.');
        System.assertEquals(0, secondDelta.impactedNodeKeys.size());
    }

    /**
     * The subtle half of DE-7: a changed EDGE must invalidate BOTH endpoint nodes, including
     * one whose own content never changed. Concretely — class A starts calling class B: A's
     * node re-versions, B's is byte-identical, yet B's cached "what depends on me?" answer is
     * now wrong. Without this, B would serve a stale answer until its TTL expired.
     */
    @isTest
    static void testAChangedEdgeMarksBothEndpointNodesAsImpactedEvenWhenNeitherNodeChanged() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));

        OI_IngestDelta delta = builder.ingest(
            new List<OI_GraphMutation>{
                OI_GraphMutation.upsertEdge('e1', 'Test.REFERENCES', 'classA', 'classB', new Map<String, Object>(), null, null, null, UserInfo.getUserId())
            }
        );

        System.assertEquals(new Set<String>{ 'e1' }, delta.changedEdgeKeys);
        System.assertEquals(0, delta.changedNodeKeys.size(), 'No NODE changed here — only the edge did.');
        System.assert(delta.impactedNodeKeys.contains('classA'), 'The edge source must be invalidated.');
        System.assert(
            delta.impactedNodeKeys.contains('classB'),
            'The edge TARGET must be invalidated too — its own content never changed, but its reverse-impact answer did. This is the exact stale-result defect DE-7 exists to prevent.'
        );
    }

    /** A retirement is a change; an idempotent no-op retire is not. Both must be reported accurately or invalidation over- or under-fires. */
    @isTest
    static void testRetirementIsReportedAsAChangeButARepeatedRetireIsNot() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));
        Id runId = UserInfo.getUserId();
        builder.ingest(
            new List<OI_GraphMutation>{
                OI_GraphMutation.upsertNode('d3', 'Test.Type', 'Label', null, null, new Map<String, Object>(), 'c1', null, runId)
            }
        );

        OI_IngestDelta retireDelta = builder.ingest(new List<OI_GraphMutation>{ OI_GraphMutation.retireNode('d3', runId) });
        System.assert(retireDelta.changedNodeKeys.contains('d3'), 'Retiring a live node is a real change — anything whose cached impact referenced it is now wrong.');

        OI_IngestDelta repeatDelta = builder.ingest(new List<OI_GraphMutation>{ OI_GraphMutation.retireNode('d3', runId) });
        System.assertEquals(true, repeatDelta.isEmpty(), 'Re-retiring an already-Stale node is an idempotent no-op and must report no change.');
    }

    @isTest
    static void testNewObservationInsertsVersionOneActive() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));

        builder.ingest(
            new List<OI_GraphMutation>{
                OI_GraphMutation.upsertNode('n1', 'Test.Type', 'Label', null, null, new Map<String, Object>(), 'c1', null, UserInfo.getUserId())
            }
        );

        OI_VersionRecord result = fake.versionsByKey.get('n1');
        System.assertNotEquals(null, result);
        System.assertEquals(1, result.versionNumber);
        System.assertEquals('Active', result.state);
        System.assertEquals(true, result.isCurrent);
    }

    @isTest
    static void testUnchangedChecksumIsALivenessTouchNotANewVersion() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));
        Id firstRunId = UserInfo.getUserId();
        builder.ingest(
            new List<OI_GraphMutation>{
                OI_GraphMutation.upsertNode('n2', 'Test.Type', 'Label', null, null, new Map<String, Object>(), 'sameChecksum', null, firstRunId)
            }
        );

        builder.ingest(
            new List<OI_GraphMutation>{
                OI_GraphMutation.upsertNode('n2', 'Test.Type', 'Label', null, null, new Map<String, Object>(), 'sameChecksum', null, firstRunId)
            }
        );

        OI_VersionRecord result = fake.versionsByKey.get('n2');
        System.assertEquals(1, result.versionNumber, 'An unchanged checksum must not create a new version.');
    }

    @isTest
    static void testChangedChecksumCreatesNewVersionAndSupersedesPrior() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));
        Id runId = UserInfo.getUserId();
        builder.ingest(
            new List<OI_GraphMutation>{ OI_GraphMutation.upsertNode('n3', 'Test.Type', 'Label', null, null, new Map<String, Object>(), 'c1', null, runId) }
        );
        String v1Key = fake.versionsByKey.get('n3').versionKey;

        builder.ingest(
            new List<OI_GraphMutation>{ OI_GraphMutation.upsertNode('n3', 'Test.Type', 'Label2', null, null, new Map<String, Object>(), 'c2', null, runId) }
        );

        OI_VersionRecord current = fake.versionsByKey.get('n3');
        System.assertEquals(2, current.versionNumber);
        System.assertEquals('c2', current.checksum);
        System.assertEquals(false, fake.versionsByVersionKey.get(v1Key).isCurrent, 'The prior version must be superseded.');
    }

    @isTest
    static void testRetireTransitionsActiveToStale() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));
        Id runId = UserInfo.getUserId();
        builder.ingest(
            new List<OI_GraphMutation>{ OI_GraphMutation.upsertNode('n4', 'Test.Type', 'Label', null, null, new Map<String, Object>(), 'c1', null, runId) }
        );

        builder.ingest(new List<OI_GraphMutation>{ OI_GraphMutation.retireNode('n4', runId) });

        System.assertEquals('Stale', fake.versionsByKey.get('n4').state);
    }

    @isTest
    static void testRetireOfAlreadyStaleNodeIsIdempotentNoOp() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));
        Id runId = UserInfo.getUserId();
        builder.ingest(
            new List<OI_GraphMutation>{ OI_GraphMutation.upsertNode('n5', 'Test.Type', 'Label', null, null, new Map<String, Object>(), 'c1', null, runId) }
        );
        builder.ingest(new List<OI_GraphMutation>{ OI_GraphMutation.retireNode('n5', runId) });
        Integer versionCountAfterFirstRetire = fake.versionsByKey.get('n5').versionNumber;

        builder.ingest(new List<OI_GraphMutation>{ OI_GraphMutation.retireNode('n5', runId) });

        System.assertEquals(versionCountAfterFirstRetire, fake.versionsByKey.get('n5').versionNumber, 'Retiring an already-Stale node must be a no-op.');
    }

    @isTest
    static void testRetireOfUnknownKeyIsANoOp() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));
        builder.ingest(new List<OI_GraphMutation>{ OI_GraphMutation.retireNode('neverExisted', UserInfo.getUserId()) });
        System.assertEquals(null, fake.versionsByKey.get('neverExisted'));
    }

    @isTest
    static void testUpsertEdgeStoresSourceAndTargetKeys() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));
        builder.ingest(
            new List<OI_GraphMutation>{
                OI_GraphMutation.upsertEdge('e1', 'Test.Edge', 'src', 'tgt', new Map<String, Object>(), 'c1', null, null, UserInfo.getUserId())
            }
        );
        OI_VersionRecord result = fake.versionsByKey.get('e1');
        System.assertEquals('src', result.sourceKey);
        System.assertEquals('tgt', result.targetKey);
    }

    @isTest
    static void testSelfLoopEdgeWithoutExplicitFlagThrowsValidationException() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));
        try {
            builder.ingest(
                new List<OI_GraphMutation>{
                    OI_GraphMutation.upsertEdge('e2', 'Test.Edge', 'same', 'same', new Map<String, Object>(), 'c1', null, null, UserInfo.getUserId())
                }
            );
            System.assert(false, 'Expected OI_ValidationException for an unflagged self-loop.');
        } catch (OI_ValidationException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testSelfLoopEdgeWithExplicitFlagIsAllowed() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));
        builder.ingest(
            new List<OI_GraphMutation>{
                OI_GraphMutation.upsertEdge(
                    'e3',
                    'Test.Edge',
                    'same',
                    'same',
                    new Map<String, Object>{ 'allowSelfLoop' => true },
                    'c1',
                    null,
                    null,
                    UserInfo.getUserId()
                )
            }
        );
        System.assertNotEquals(null, fake.versionsByKey.get('e3'));
    }

    @isTest
    static void testMissingKeyThrowsValidationException() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));
        try {
            builder.ingest(new List<OI_GraphMutation>{ OI_GraphMutation.upsertNode(null, 'Test.Type', 'Label', null, null, new Map<String, Object>(), 'c1', null, null) });
            System.assert(false, 'Expected OI_ValidationException for a blank key.');
        } catch (OI_ValidationException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testBulkBatchOfNewNodesInsertsEveryone() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));
        List<OI_GraphMutation> batch = new List<OI_GraphMutation>();
        for (Integer i = 0; i < 50; i++) {
            batch.add(OI_GraphMutation.upsertNode('bulk' + i, 'Test.Type', 'Label' + i, null, null, new Map<String, Object>(), 'c' + i, null, UserInfo.getUserId()));
        }
        builder.ingest(batch);
        System.assertEquals(50, fake.versionsByKey.size());
    }

    @isTest
    static void testEmptyBatchIsANoOp() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));
        builder.ingest(new List<OI_GraphMutation>());
        System.assertEquals(0, fake.versionsByKey.size());
    }

    /**
     * GE-2c (GraphRepository.md §15): a single simulated conflict on the first write
     * attempt must converge on retry — the mutation still ends up committed, not lost or
     * duplicated. ConflictOnceThenSucceedProvider throws OI_ConcurrencyException directly
     * (never a manually-constructed DmlException — the platform quirk documented on
     * OI_GraphRepository.isDuplicateValueConflict does not apply to our own exception type),
     * scoped to this test file only so no other test's shared fake gains a stateful toggle.
     */
    @isTest
    static void testConcurrencyConflictOnFirstAttemptSucceedsOnRetry() {
        ConflictOnceThenSucceedProvider fake = new ConflictOnceThenSucceedProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));

        builder.ingest(
            new List<OI_GraphMutation>{
                OI_GraphMutation.upsertNode('retryNode', 'Test.Type', 'Label', null, null, new Map<String, Object>(), 'c1', null, UserInfo.getUserId())
            }
        );

        System.assertEquals(2, fake.writeAttempts, 'Expected exactly one retry (two total write attempts).');
        System.assertNotEquals(null, fake.committed.get('retryNode'), 'The mutation must still be committed after the retry converges.');
    }

    @isTest
    static void testConcurrencyConflictOnBothAttemptsPropagates() {
        AlwaysConflictProvider fake = new AlwaysConflictProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));

        try {
            builder.ingest(
                new List<OI_GraphMutation>{
                    OI_GraphMutation.upsertNode('alwaysConflict', 'Test.Type', 'Label', null, null, new Map<String, Object>(), 'c1', null, UserInfo.getUserId())
                }
            );
            System.assert(false, 'Expected OI_ConcurrencyException to propagate after the retry also conflicts.');
        } catch (OI_ConcurrencyException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testConcurrencyConflictOnRetireConvergesOnRetry() {
        ConflictOnceThenSucceedProvider fake = new ConflictOnceThenSucceedProvider();
        OI_GraphBuilder builder = new OI_GraphBuilder(new OI_GraphRepository(fake, fake));
        Id runId = UserInfo.getUserId();
        fake.seedCurrent(OI_TestDataFactory.newNodeVersionRecord('retireConflictKey', 1, 'c1'));

        builder.ingest(new List<OI_GraphMutation>{ OI_GraphMutation.retireNode('retireConflictKey', runId) });

        System.assertEquals(2, fake.writeAttempts);
        System.assertEquals('Stale', fake.committed.get('retireConflictKey').state);
    }

    /** Throws OI_ConcurrencyException on the first writeVersion call only, then succeeds. */
    private class ConflictOnceThenSucceedProvider implements OI_IGraphStorageProvider {
        public Integer writeAttempts = 0;
        public Map<String, OI_VersionRecord> committed = new Map<String, OI_VersionRecord>();

        public void seedCurrent(OI_VersionRecord record) {
            committed.put(record.key, record);
        }

        public Map<String, OI_VersionRecord> readCurrent(Set<String> keys, Boolean isEdgeFlavor) {
            Map<String, OI_VersionRecord> result = new Map<String, OI_VersionRecord>();
            for (String key : keys) {
                if (committed.containsKey(key) && committed.get(key).isCurrent == true) {
                    result.put(key, committed.get(key));
                }
            }
            return result;
        }

        public OI_KeysPage readCurrentKeysByType(String typeKey, String cursor, Integer pageSize, Boolean isEdgeFlavor) {
            return new OI_KeysPage(new List<String>(), null, false);
        }

        public OI_VersionRecord writeVersion(OI_VersionRecord record, Boolean isNew) {
            writeAttempts++;
            if (writeAttempts == 1) {
                throw new OI_ConcurrencyException('Simulated concurrent write for GE-2c test.');
            }
            committed.put(record.key, record);
            return record;
        }

        public void markSuperseded(String versionKey, Boolean isEdgeFlavor) {
        }

        public void touchLiveness(Set<String> keys, Id runId, Boolean isEdgeFlavor) {
        }

        public Integer moveToArchive(List<OI_VersionRecord> records) {
            return 0;
        }
    }

    /** Always throws OI_ConcurrencyException — verifies a second conflict propagates rather than retrying forever. */
    private class AlwaysConflictProvider implements OI_IGraphStorageProvider {
        public Map<String, OI_VersionRecord> readCurrent(Set<String> keys, Boolean isEdgeFlavor) {
            return new Map<String, OI_VersionRecord>();
        }

        public OI_KeysPage readCurrentKeysByType(String typeKey, String cursor, Integer pageSize, Boolean isEdgeFlavor) {
            return new OI_KeysPage(new List<String>(), null, false);
        }

        public OI_VersionRecord writeVersion(OI_VersionRecord record, Boolean isNew) {
            throw new OI_ConcurrencyException('Simulated persistent conflict for GE-2c test.');
        }

        public void markSuperseded(String versionKey, Boolean isEdgeFlavor) {
        }

        public void touchLiveness(Set<String> keys, Id runId, Boolean isEdgeFlavor) {
        }

        public Integer moveToArchive(List<OI_VersionRecord> records) {
            return 0;
        }
    }
}
