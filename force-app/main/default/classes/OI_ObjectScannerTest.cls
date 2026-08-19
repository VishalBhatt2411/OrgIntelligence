/**
 * Purpose: Verifies OI_ObjectScanner discovers real org SObjects as a full-snapshot
 *          Discovery Batch, excludes companion/out-of-scope objects, and produces a
 *          deterministic identity across repeated scans (MetadataScanner.md §21).
 */
@isTest
private class OI_ObjectScannerTest {
    @isTest
    static void testScanReturnsFullSnapshotContainingAStandardObject() {
        OI_ObjectScanner scanner = new OI_ObjectScanner();
        OI_DiscoveryBatch batch = scanner.scan(new OI_ScanContext(null, 100, null, 'Describe'));

        System.assertEquals('CustomObject', batch.componentKind);
        System.assertEquals(true, batch.isFullSnapshot);
        System.assert(batch.components.size() > 0, 'Expected at least one discovered object.');

        Boolean foundAccount = false;
        for (OI_DiscoveredComponent component : batch.components) {
            if (component.fullyQualifiedName == 'Account') {
                foundAccount = true;
                System.assertEquals('CustomObject', component.componentKind);
                System.assertEquals('Describe', component.sourceApi);
                System.assertNotEquals(null, component.rawChecksum);
                System.assert(component.rawAttributes.containsKey('namespace'), 'Expected a namespace attribute (null for a standard, unpackaged object) to support the Detail Panel\'s Namespace field.');
                System.assertEquals(null, component.rawAttributes.get('namespace'), 'The standard Account object is unpackaged and must resolve to a null namespace.');
            }
        }
        System.assert(foundAccount, 'Expected the standard Account object to be discovered.');
    }

    @isTest
    static void testScanExcludesCompanionAndOutOfScopeObjects() {
        OI_ObjectScanner scanner = new OI_ObjectScanner();
        OI_DiscoveryBatch batch = scanner.scan(new OI_ScanContext(null, 100, null, 'Describe'));

        for (OI_DiscoveredComponent component : batch.components) {
            String name = component.fullyQualifiedName;
            System.assert(!name.endsWith('History'), 'History companion objects must be excluded: ' + name);
            System.assert(!name.endsWith('Share'), 'Share companion objects must be excluded: ' + name);
            System.assert(!name.endsWith('Feed'), 'Feed companion objects must be excluded: ' + name);
            System.assert(!name.endsWith('__mdt'), 'Custom Metadata Types must be excluded: ' + name);
            System.assert(!name.endsWith('__e'), 'Platform Events must be excluded: ' + name);
            System.assert(!name.endsWith('__b'), 'Big Objects must be excluded: ' + name);
        }
    }

    @isTest
    static void testComponentIdentityAndChecksumAreDeterministicAcrossRepeatedScans() {
        OI_ObjectScanner scanner = new OI_ObjectScanner();
        OI_DiscoveryBatch firstBatch = scanner.scan(new OI_ScanContext(null, 100, null, 'Describe'));
        OI_DiscoveryBatch secondBatch = scanner.scan(new OI_ScanContext(null, 100, null, 'Describe'));

        OI_DiscoveredComponent firstAccount = findByName(firstBatch, 'Account');
        OI_DiscoveredComponent secondAccount = findByName(secondBatch, 'Account');

        System.assertNotEquals(null, firstAccount);
        System.assertNotEquals(null, secondAccount);
        System.assertEquals(firstAccount.componentKey, secondAccount.componentKey, 'The same object scanned twice must produce the same componentKey.');
        System.assertEquals(firstAccount.rawChecksum, secondAccount.rawChecksum, 'Unchanged metadata must produce the same checksum across scans.');
    }

    private static OI_DiscoveredComponent findByName(OI_DiscoveryBatch batch, String name) {
        for (OI_DiscoveredComponent component : batch.components) {
            if (component.fullyQualifiedName == name) {
                return component;
            }
        }
        return null;
    }
}
