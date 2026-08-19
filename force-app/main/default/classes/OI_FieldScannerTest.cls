/**
 * Purpose: Verifies OI_FieldScanner discovers fields with a correct parentComponentKey,
 *          emits HAS_FIELD relationships for every field, and correctly distinguishes
 *          Lookup from Master-Detail reference relationships (Sprint 8 objective §5/§6).
 */
@isTest
private class OI_FieldScannerTest {
    @isTest
    static void testAccountNameFieldHasCorrectParentAndHasFieldRelationship() {
        OI_FieldScanner scanner = new OI_FieldScanner();
        OI_DiscoveryBatch batch = scanner.scan(new OI_ScanContext(null, 100, null, 'Describe'));

        System.assertEquals('CustomField', batch.componentKind);
        System.assertEquals(true, batch.isFullSnapshot);

        OI_DiscoveredComponent nameField = findByName(batch, 'Account.Name');
        System.assertNotEquals(null, nameField, 'Expected Account.Name to be discovered.');
        String expectedParentKey = OI_ComponentKeyUtil.build('CustomObject', null, 'Account');
        System.assertEquals(expectedParentKey, nameField.parentComponentKey);

        Boolean foundHasField = false;
        for (OI_DiscoveredRelationship relationship : batch.relationships) {
            if (relationship.relationshipKind == 'HAS_FIELD' && relationship.toComponentKey == nameField.componentKey) {
                foundHasField = true;
                System.assertEquals(expectedParentKey, relationship.fromComponentKey);
            }
        }
        System.assert(foundHasField, 'Expected a HAS_FIELD relationship from Account to Account.Name.');
    }

    @isTest
    static void testLookupFieldEmitsLookupToRelationship() {
        OI_FieldScanner scanner = new OI_FieldScanner();
        OI_DiscoveryBatch batch = scanner.scan(new OI_ScanContext(null, 100, null, 'Describe'));

        OI_DiscoveredComponent ownerField = findByName(batch, 'Account.OwnerId');
        System.assertNotEquals(null, ownerField);

        Boolean foundLookup = false;
        for (OI_DiscoveredRelationship relationship : batch.relationships) {
            if (relationship.relationshipKind == 'LOOKUP_TO' && relationship.fromComponentKey == ownerField.componentKey) {
                foundLookup = true;
            }
        }
        System.assert(foundLookup, 'Account.OwnerId is a polymorphic lookup and must emit at least one LOOKUP_TO relationship.');
    }

    /**
     * Uses this package's own OI_Scan_Task__c.Scan_Run__c — a genuine custom Master-Detail
     * field — rather than a standard-object relationship: empirically, standard
     * relationships like OpportunityLineItem -> Opportunity are not exposed through
     * getRelationshipOrder() the same way a real custom Master-Detail field is, so
     * asserting against one would test a platform assumption this Scanner does not
     * actually rely on. A custom Master-Detail field is the reliable, org-independent case.
     */
    @isTest
    static void testMasterDetailFieldEmitsMasterDetailToRelationship() {
        OI_FieldScanner scanner = new OI_FieldScanner();
        OI_DiscoveryBatch batch = scanner.scan(new OI_ScanContext(null, 100, null, 'Describe'));

        OI_DiscoveredComponent scanRunField = findByName(batch, 'OI_Scan_Task__c.Scan_Run__c');
        System.assertNotEquals(null, scanRunField, 'Expected the custom Master-Detail field OI_Scan_Task__c.Scan_Run__c to be discovered.');

        Boolean foundMasterDetail = false;
        for (OI_DiscoveredRelationship relationship : batch.relationships) {
            if (relationship.relationshipKind == 'MASTER_DETAIL_TO' && relationship.fromComponentKey == scanRunField.componentKey) {
                foundMasterDetail = true;
            }
        }
        System.assert(foundMasterDetail, 'OI_Scan_Task__c.Scan_Run__c is a custom Master-Detail field and must emit MASTER_DETAIL_TO, not LOOKUP_TO.');
    }

    /**
     * Scopes both scans to just Account via OI_ScanContext.scopedApiNames — the only
     * assertion this test makes is about Account.Name, so there's no need to pay for a
     * full org-wide Describe twice in one transaction. This isn't only an optimization:
     * a real org's total schema size (every installed managed package's objects/fields
     * included) is outside this test's control, and a org with a large enough schema can
     * exceed the synchronous Apex heap limit on a full org-wide scan alone, let alone two
     * back-to-back — scoping removes that dependency on the target org's total schema size
     * entirely, which holding-only-one-batch-at-a-time (the previous approach) could not.
     */
    @isTest
    static void testChecksumIsDeterministicAcrossRepeatedScans() {
        OI_FieldScanner scanner = new OI_FieldScanner();
        OI_ScanContext accountOnlyScope = new OI_ScanContext(null, 100, null, 'Describe', new Set<String>{ 'Account' });

        OI_DiscoveryBatch firstBatch = scanner.scan(accountOnlyScope);
        OI_DiscoveredComponent first = findByName(firstBatch, 'Account.Name');
        String firstComponentKey = first.componentKey;
        String firstChecksum = first.rawChecksum;
        firstBatch = null;
        first = null;

        OI_DiscoveryBatch secondBatch = scanner.scan(accountOnlyScope);
        OI_DiscoveredComponent second = findByName(secondBatch, 'Account.Name');

        System.assertEquals(firstComponentKey, second.componentKey);
        System.assertEquals(firstChecksum, second.rawChecksum);
    }

    private static OI_DiscoveredComponent findByName(OI_DiscoveryBatch batch, String fullyQualifiedName) {
        for (OI_DiscoveredComponent component : batch.components) {
            if (component.fullyQualifiedName == fullyQualifiedName) {
                return component;
            }
        }
        return null;
    }
}
