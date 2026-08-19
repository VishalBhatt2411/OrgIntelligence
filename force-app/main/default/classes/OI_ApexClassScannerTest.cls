/**
 * Purpose: Verifies OI_ApexClassScanner discovers real deployed Apex classes, extracts
 *          best-effort REFERENCES relationships from real class bodies (Dependency Engine
 *          epic, DE-0), and produces a deterministic identity across repeated scans.
 */
@isTest
private class OI_ApexClassScannerTest {
    @isTest
    static void testScanDiscoversAClassFromThisPackage() {
        OI_ApexClassScanner scanner = new OI_ApexClassScanner();
        OI_DiscoveryBatch batch = scanner.scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        System.assertEquals('ApexClass', batch.componentKind);
        System.assertEquals(true, batch.isFullSnapshot);
        System.assert(batch.components.size() > 0, 'Expected at least one Apex class to be discovered.');

        Boolean foundSelf = false;
        for (OI_DiscoveredComponent component : batch.components) {
            if (component.fullyQualifiedName.endsWith('OI_ApexClassScanner')) {
                foundSelf = true;
                System.assertEquals('SOQL', component.sourceApi);
                System.assertNotEquals(null, component.rawChecksum);
            }
        }
        System.assert(foundSelf, 'Expected OI_ApexClassScanner itself to be discovered by its own scan.');
    }

    @isTest
    static void testDiscoversARealDeduplicatedReferenceBetweenTwoClassesInThisPackage() {
        OI_ApexClassScanner scanner = new OI_ApexClassScanner();
        OI_DiscoveryBatch batch = scanner.scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        String mutationGeneratorKey = componentKeyFor(batch, 'OI_MutationGenerator');
        String graphEngineKey = componentKeyFor(batch, 'OI_GraphEngine');
        System.assertNotEquals(null, mutationGeneratorKey, 'Precondition: OI_MutationGenerator must have been discovered as a component.');
        System.assertNotEquals(null, graphEngineKey, 'Precondition: OI_GraphEngine must have been discovered as a component.');

        Integer matchCount = 0;
        for (OI_DiscoveredRelationship relationship : batch.relationships) {
            if (relationship.fromComponentKey == mutationGeneratorKey && relationship.toComponentKey == graphEngineKey) {
                matchCount++;
                System.assertEquals('REFERENCES', relationship.relationshipKind);
            }
        }
        System.assertEquals(
            1,
            matchCount,
            'OI_MutationGenerator names OI_GraphEngine multiple times in its own body (a field declaration and two constructors), but must produce exactly one deduplicated REFERENCES edge, never one per occurrence.'
        );
    }

    @isTest
    static void testNeverEmitsASelfReferenceEvenThoughAClassNamesItselfInItsOwnDocComments() {
        OI_ApexClassScanner scanner = new OI_ApexClassScanner();
        OI_DiscoveryBatch batch = scanner.scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        String selfKey = componentKeyFor(batch, 'OI_ApexClassScanner');
        System.assertNotEquals(null, selfKey);
        for (OI_DiscoveredRelationship relationship : batch.relationships) {
            System.assert(
                !(relationship.fromComponentKey == selfKey && relationship.toComponentKey == selfKey),
                'A class must never be recorded as referencing itself, even though its own name legitimately appears in its own doc comments/declaration.'
            );
        }
    }

    private static String componentKeyFor(OI_DiscoveryBatch batch, String classNameSuffix) {
        for (OI_DiscoveredComponent component : batch.components) {
            if (component.fullyQualifiedName.endsWith(classNameSuffix)) {
                return component.componentKey;
            }
        }
        return null;
    }

    @isTest
    static void testComponentIdentityIsDeterministicAcrossRepeatedScans() {
        OI_ApexClassScanner scanner = new OI_ApexClassScanner();
        OI_DiscoveryBatch firstBatch = scanner.scan(new OI_ScanContext(null, 200, null, 'SOQL'));
        OI_DiscoveryBatch secondBatch = scanner.scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        OI_DiscoveredComponent first = findSelf(firstBatch);
        OI_DiscoveredComponent second = findSelf(secondBatch);

        System.assertNotEquals(null, first);
        System.assertEquals(first.componentKey, second.componentKey);
        System.assertEquals(first.rawChecksum, second.rawChecksum);
    }

    private static OI_DiscoveredComponent findSelf(OI_DiscoveryBatch batch) {
        for (OI_DiscoveredComponent component : batch.components) {
            if (component.fullyQualifiedName.endsWith('OI_ApexClassScanner')) {
                return component;
            }
        }
        return null;
    }
}
