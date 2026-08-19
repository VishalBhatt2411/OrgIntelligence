/**
 * Purpose: Verifies OI_HierarchyRecordResolver's batch label resolution and its
 *          skip-never-fail discipline for bad input (ADR-0022).
 */
@isTest
private class OI_HierarchyRecordResolverTest {
    @isTest
    static void testResolveLabelsReturnsLabelsForRealAccessibleRecords() {
        Account a = new Account(Name = 'Account A');
        insert a;

        Map<String, String> labels = new OI_HierarchyRecordResolver().resolveLabels(new List<OI_HierarchyRecordResolver.RecordRef>{ new OI_HierarchyRecordResolver.RecordRef('Account', a.Id) });

        System.assertEquals('Account A', labels.get(a.Id));
    }

    @isTest
    static void testResolveLabelsBatchesAcrossMultipleObjectTypesInOneCallEach() {
        Account a = new Account(Name = 'Account A');
        insert a;
        Contact c = new Contact(LastName = 'Contact C', AccountId = a.Id);
        insert c;

        Map<String, String> labels = new OI_HierarchyRecordResolver().resolveLabels(
            new List<OI_HierarchyRecordResolver.RecordRef>{ new OI_HierarchyRecordResolver.RecordRef('Account', a.Id), new OI_HierarchyRecordResolver.RecordRef('Contact', c.Id) }
        );

        System.assertEquals('Account A', labels.get(a.Id));
        System.assertNotEquals(null, labels.get(c.Id));
    }

    @isTest
    static void testResolveLabelsSkipsAnUnknownObjectApiNameRatherThanFailingTheWholeBatch() {
        Account a = new Account(Name = 'Account A');
        insert a;

        Map<String, String> labels = new OI_HierarchyRecordResolver().resolveLabels(
            new List<OI_HierarchyRecordResolver.RecordRef>{ new OI_HierarchyRecordResolver.RecordRef('NotARealObject__x', '001000000000001AAA'), new OI_HierarchyRecordResolver.RecordRef('Account', a.Id) }
        );

        System.assertEquals(1, labels.size());
        System.assertEquals('Account A', labels.get(a.Id));
    }

    @isTest
    static void testResolveLabelsIgnoresBlankAndMalformedReferences() {
        Map<String, String> labels = new OI_HierarchyRecordResolver().resolveLabels(
            new List<OI_HierarchyRecordResolver.RecordRef>{ new OI_HierarchyRecordResolver.RecordRef('Account', null), new OI_HierarchyRecordResolver.RecordRef('Account', 'not-a-valid-id') }
        );
        System.assertEquals(0, labels.size());
    }

    @isTest
    static void testResolveLabelsOnAnEmptyListReturnsAnEmptyMap() {
        Map<String, String> labels = new OI_HierarchyRecordResolver().resolveLabels(new List<OI_HierarchyRecordResolver.RecordRef>());
        System.assertEquals(0, labels.size());
    }
}
