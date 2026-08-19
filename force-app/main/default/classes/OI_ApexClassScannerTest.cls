/**
 * Purpose: Verifies OI_ApexClassScanner discovers real deployed Apex classes, extracts
 *          best-effort REFERENCES relationships from real class bodies (Dependency Engine
 *          epic, DE-0), and produces a deterministic identity across repeated scans.
 */
@isTest
private class OI_ApexClassScannerTest {
    /**
     * Comment/string stripping (2026-08-19). Asserted against stripNonCodeRegions directly with
     * synthetic bodies, because the real scanner can only read Apex actually deployed to the
     * org — a test cannot deploy a class containing a controlled phantom reference, so the unit
     * boundary is where this behavior is genuinely testable.
     */
    @isTest
    static void testStripsBlockCommentsLineCommentsAndStringLiteralsBeforeTokenizing() {
        String body =
            'public class A {\n' +
            '    /** Dependencies: OI_ChecksumUtil, OI_ComponentKeyUtil */\n' +
            '    // see OI_LoggerService for details\n' +
            '    void go() { throw new OI_ValidationException(\'OI_SecurityService rejected it\'); }\n' +
            '}';

        String stripped = OI_ApexClassScanner.stripNonCodeRegions(body);

        System.assert(!stripped.contains('OI_ChecksumUtil'), 'A class named only in a block comment must not survive stripping.');
        System.assert(!stripped.contains('OI_ComponentKeyUtil'), 'A class named only in a block comment must not survive stripping.');
        System.assert(!stripped.contains('OI_LoggerService'), 'A class named only in a line comment must not survive stripping.');
        System.assert(!stripped.contains('OI_SecurityService'), 'A class named only inside a string literal must not survive stripping.');
        System.assert(stripped.contains('OI_ValidationException'), 'A genuine reference in real code must survive stripping — this is the whole point of the edge data.');
    }

    /**
     * The boundary case that makes the single-alternation pass correct rather than merely
     * approximate, verified in BOTH directions: `//` inside a string must not start a comment,
     * and an apostrophe inside a comment must not open a string. A naive two-pass implementation
     * (strip comments, then strings, or the reverse) gets exactly one of these wrong and would
     * then swallow real code as if it were a comment or literal.
     */
    @isTest
    static void testDoesNotMisreadCommentMarkersInsideStringsOrApostrophesInsideComments() {
        String urlInString = 'String u = \'http://example.com\'; OI_RealClass x;';
        String stripped = OI_ApexClassScanner.stripNonCodeRegions(urlInString);
        System.assert(stripped.contains('OI_RealClass'), 'A // inside a string literal must not be treated as a comment start, or all following real code would be discarded.');

        String apostropheInComment = '// don\'t remove this\nOI_RealClass y;';
        String strippedApostrophe = OI_ApexClassScanner.stripNonCodeRegions(apostropheInComment);
        System.assert(strippedApostrophe.contains('OI_RealClass'), 'An apostrophe inside a comment must not open a string literal that swallows the following real code.');
    }

    /** Regions collapse to a space, never to nothing — otherwise two identifiers separated only by a comment would fuse into one token that matches no real class. */
    @isTest
    static void testReplacesStrippedRegionsWithASeparatorSoAdjacentIdentifiersNeverFuse() {
        String stripped = OI_ApexClassScanner.stripNonCodeRegions('foo/*comment*/bar');
        System.assert(!stripped.contains('foobar'), 'A stripped region must leave a separator behind; fusing identifiers would silently corrupt tokenizing.');
    }

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
