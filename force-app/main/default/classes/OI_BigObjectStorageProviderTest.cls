/**
 * Purpose: Verifies OI_BigObjectStorageProvider's write path and its documented
 *          not-implemented surfaces (GraphRepository.md §9).
 */
@isTest
private class OI_BigObjectStorageProviderTest {
    /**
     * Big Object SOQL is async-query-only and does not guarantee the synchronous-
     * consistency a Custom Object query has, even within the same transaction
     * (GraphRepository.md §9, §19) — so this asserts the insert completes without
     * throwing, not that an immediate SOQL re-query can see it.
     */
    @isTest
    static void testWriteVersionInsertsNodeArchiveRowWithoutError() {
        OI_VersionRecord result = new OI_BigObjectStorageProvider().writeVersion(OI_TestDataFactory.newNodeVersionRecord('archNode1', 1, 'c1'), true);
        System.assertEquals('archNode1', result.key);
    }

    @isTest
    static void testWriteVersionInsertsEdgeArchiveRowWithoutError() {
        OI_VersionRecord result = new OI_BigObjectStorageProvider().writeVersion(OI_TestDataFactory.newEdgeVersionRecord('archEdge1', 'src', 'tgt', 1), true);
        System.assertEquals('archEdge1', result.key);
    }

    @isTest
    static void testReadCurrentThrowsNotSupported() {
        try {
            new OI_BigObjectStorageProvider().readCurrent(new Set<String>{ 'k' }, false);
            System.assert(false);
        } catch (OI_ServiceException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testMarkSupersededThrowsNotSupported() {
        try {
            new OI_BigObjectStorageProvider().markSuperseded('k', false);
            System.assert(false);
        } catch (OI_ServiceException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testTouchLivenessThrowsNotSupported() {
        try {
            new OI_BigObjectStorageProvider().touchLiveness(new Set<String>{ 'k' }, null, false);
            System.assert(false);
        } catch (OI_ServiceException e) {
            System.assert(true);
        }
    }
}
