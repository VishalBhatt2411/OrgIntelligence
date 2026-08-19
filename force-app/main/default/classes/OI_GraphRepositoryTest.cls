/**
 * Purpose: Verifies OI_GraphRepository's atomicity (commitVersion), optimistic
 *          concurrency translation, and delegation contract (GraphRepository.md §6, §15,
 *          §23) — tested against a fake OI_IGraphStorageProvider for atomicity/delegation,
 *          and against the real OI_CustomObjectStorageProvider for the genuine
 *          DUPLICATE_VALUE conflict path, which cannot be manufactured on a fake
 *          (its StatusCode can't be constructed manually).
 */
@isTest
private class OI_GraphRepositoryTest {
    @isTest
    static void testGetCurrentVersionsDelegatesToProvider() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        fake.writeVersion(OI_TestDataFactory.newNodeVersionRecord('n1', 1, 'c1'), true);
        OI_GraphRepository repo = new OI_GraphRepository(fake, fake);
        System.assertEquals(1, repo.getCurrentVersions(new Set<String>{ 'n1' }, false).size());
    }

    @isTest
    static void testCommitVersionInsertsBrandNewKeyNoFlip() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphRepository repo = new OI_GraphRepository(fake, fake);
        repo.commitVersion(OI_TestDataFactory.newNodeVersionRecord('n2', 1, 'c1'), null);
        System.assertEquals(1, fake.versionsByKey.size());
    }

    @isTest
    static void testCommitVersionSupersedesPriorVersion() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphRepository repo = new OI_GraphRepository(fake, fake);
        OI_VersionRecord v1 = OI_TestDataFactory.newNodeVersionRecord('n3', 1, 'c1');
        repo.commitVersion(v1, null);
        OI_VersionRecord v2 = OI_TestDataFactory.newNodeVersionRecord('n3', 2, 'c2');
        repo.commitVersion(v2, v1.versionKey);
        System.assertEquals(false, fake.versionsByVersionKey.get(v1.versionKey).isCurrent);
        System.assertEquals(true, fake.versionsByVersionKey.get(v2.versionKey).isCurrent);
    }

    /**
     * A manually-constructed DmlException cannot safely simulate this path — calling
     * getNumDml() on one that never came from a real failed DML statement raises an
     * uncatchable platform-level UnexpectedException (confirmed empirically; there is no
     * public API to detect this in advance). So this exercises a genuine, real
     * REQUIRED_FIELD_MISSING DmlException instead (Node_Type__c is required on
     * OI_Graph_Node__c) — verifying isDuplicateValueConflict correctly says "no" to a
     * real non-conflict DmlException and the original exception propagates unwrapped.
     */
    @isTest
    static void testCommitVersionPropagatesNonConflictDmlExceptionUnchanged() {
        OI_GraphRepository repo = new OI_GraphRepository();
        OI_VersionRecord invalidRecord = new OI_VersionRecord(
            'n4',
            'n4::v1',
            1,
            null,
            null,
            null,
            null,
            new Map<String, Object>(),
            'c1',
            'Active',
            null,
            null,
            null,
            true,
            null,
            null
        );
        try {
            repo.commitVersion(invalidRecord, null);
            System.assert(false, 'Expected a DmlException from the missing required Node_Type__c field.');
        } catch (OI_ConcurrencyException e) {
            System.assert(false, 'A required-field violation must not be misclassified as a concurrency conflict.');
        } catch (DmlException e) {
            System.assert(true, 'Non-conflict DmlExceptions must propagate unchanged.');
        }
    }

    @isTest
    static void testRealDuplicateValueConflictTranslatesToConcurrencyException() {
        OI_GraphRepository repo = new OI_GraphRepository();
        OI_VersionRecord record = OI_TestDataFactory.newNodeVersionRecord('n5', 1, 'c1');
        repo.commitVersion(record, null);
        try {
            repo.commitVersion(record, null);
            System.assert(false, 'Expected OI_ConcurrencyException from a real External ID collision.');
        } catch (OI_ConcurrencyException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testTouchLivenessDelegatesToProvider() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphRepository repo = new OI_GraphRepository(fake, fake);
        repo.commitVersion(OI_TestDataFactory.newNodeVersionRecord('n6', 1, 'c1'), null);
        repo.touchLiveness(new Set<String>{ 'n6' }, UserInfo.getUserId(), false);
        System.assertNotEquals(null, fake.versionsByKey.get('n6').lastSeenRunId);
    }

    @isTest
    static void testGetCurrentKeysByTypeDelegatesToProvider() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphRepository repo = new OI_GraphRepository(fake, fake);
        repo.commitVersion(OI_TestDataFactory.newNodeVersionRecord('n7', 1, 'c1'), null);
        OI_KeysPage page = repo.getCurrentKeysByType('Test.NodeType', null, 10, false);
        System.assertEquals(1, page.items.size());
    }

    @isTest
    static void testArchiveSupersededVersionsNotImplementedThisSprint() {
        try {
            new OI_GraphRepository().archiveSupersededVersions(Datetime.now());
            System.assert(false);
        } catch (OI_ServiceException e) {
            System.assert(true);
        }
    }

    /**
     * commitVersion cannot be bulked across different keys the way a plain insert can
     * (GraphRepository.md §11, §24) — each key's insert-then-flip is its own
     * Savepoint-guarded transactional unit, and Database.setSavepoint() itself consumes
     * one DML statement per call. 120 sequential commits (not 200) is the honest
     * boundary this test can exercise within the platform's 150-DML-statement-per-
     * transaction ceiling — a real caller (OI_GraphBuilder, Roadmap Phase 2) is expected
     * to chunk beyond this, exactly as the cited sections already document.
     */
    @isTest
    static void testSequentialCommitVersionAcrossManyKeysRespectsPerTransactionDmlCeiling() {
        OI_FakeGraphStorageProvider fake = new OI_FakeGraphStorageProvider();
        OI_GraphRepository repo = new OI_GraphRepository(fake, fake);
        for (Integer i = 0; i < 120; i++) {
            repo.commitVersion(OI_TestDataFactory.newNodeVersionRecord('bulkKey' + i, 1, 'c' + i), null);
        }
        System.assertEquals(120, fake.versionsByKey.size());
    }
}
