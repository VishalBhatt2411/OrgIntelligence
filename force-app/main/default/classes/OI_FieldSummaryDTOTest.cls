/**
 * Purpose: Verifies OI_FieldSummaryDTO's attribute-bag parsing is safe against missing,
 *          absent, and malformed keys — the schemaless Attributes_Json__c bag guarantees
 *          nothing about shape (GraphEngine.md §2, §8).
 */
@isTest
private class OI_FieldSummaryDTOTest {
    @isTest
    static void testParsesAFullyPopulatedReferenceFieldsAttributes() {
        OI_VersionRecord version = new OI_VersionRecord(
            'f1',
            'f1::v1',
            1,
            'SalesforceMetadata.CustomField',
            'Owner Id',
            'Account.OwnerId',
            null,
            new Map<String, Object>{ 'custom' => false, 'type' => 'REFERENCE', 'nillable' => true, 'referenceTo' => new List<Object>{ 'User' } },
            'c1',
            'Active',
            null,
            null,
            null,
            true,
            null,
            null
        );

        OI_FieldSummaryDTO dto = new OI_FieldSummaryDTO(version);

        System.assertEquals('f1', dto.nodeKey);
        System.assertEquals('Owner Id', dto.label);
        System.assertEquals('Account.OwnerId', dto.apiName);
        System.assertEquals('REFERENCE', dto.dataType);
        System.assertEquals(false, dto.isCustom);
        System.assertEquals(false, dto.isRequired, 'nillable=true must invert to isRequired=false.');
        System.assertEquals(1, dto.referenceTo.size());
        System.assertEquals('User', dto.referenceTo[0]);
    }

    @isTest
    static void testAnEmptyAttributesBagProducesNullDerivedFieldsNeverAnException() {
        OI_VersionRecord version = new OI_VersionRecord('f2', 'f2::v1', 1, 'SalesforceMetadata.CustomField', 'Bare Field', 'Object.Bare', null, new Map<String, Object>(), 'c1', 'Active', null, null, null, true, null, null);

        OI_FieldSummaryDTO dto = new OI_FieldSummaryDTO(version);

        System.assertEquals(null, dto.dataType);
        System.assertEquals(null, dto.isCustom);
        System.assertEquals(null, dto.isRequired, 'Absent nillable must produce an honest unknown (null), never a false-positive true/false.');
        System.assertEquals(null, dto.referenceTo);
    }

    @isTest
    static void testAMalformedNonListReferenceToIsIgnoredRatherThanThrowing() {
        OI_VersionRecord version = new OI_VersionRecord(
            'f3',
            'f3::v1',
            1,
            'SalesforceMetadata.CustomField',
            'Odd Field',
            'Object.Odd',
            null,
            new Map<String, Object>{ 'referenceTo' => 'NotAList' },
            'c1',
            'Active',
            null,
            null,
            null,
            true,
            null,
            null
        );

        OI_FieldSummaryDTO dto = new OI_FieldSummaryDTO(version);

        System.assertEquals(null, dto.referenceTo, 'A referenceTo value that is not actually a list must be treated as absent, never cast-thrown.');
    }
}
