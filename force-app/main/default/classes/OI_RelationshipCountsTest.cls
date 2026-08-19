/**
 * Purpose: Verifies OI_RelationshipCounts.total() sums both directions correctly and
 *          tolerates null maps.
 */
@isTest
private class OI_RelationshipCountsTest {
    @isTest
    static void testTotalSumsOutgoingAndIncomingCounts() {
        OI_RelationshipCounts counts = new OI_RelationshipCounts(
            new Map<String, Integer>{ 'SalesforceMetadata.HAS_FIELD' => 3, 'SalesforceMetadata.LOOKUP_TO' => 2 },
            new Map<String, Integer>{ 'SalesforceMetadata.LOOKUP_TO' => 1 }
        );
        System.assertEquals(6, counts.total());
    }

    @isTest
    static void testNullMapsAreTreatedAsEmpty() {
        OI_RelationshipCounts counts = new OI_RelationshipCounts(null, null);
        System.assertEquals(0, counts.total());
        System.assertEquals(0, counts.outgoingByType.size());
        System.assertEquals(0, counts.incomingByType.size());
    }
}
