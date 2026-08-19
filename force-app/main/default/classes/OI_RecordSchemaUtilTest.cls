@isTest
private class OI_RecordSchemaUtilTest {
    @isTest
    static void testDescribeAccessibleObjectReturnsDescribeForAKnownObject() {
        Schema.DescribeSObjectResult describe = OI_RecordSchemaUtil.describeAccessibleObject('Account');
        System.assertEquals('Account', describe.getName());
    }

    @isTest
    static void testDescribeAccessibleObjectThrowsValidationExceptionForAnUnknownObject() {
        try {
            OI_RecordSchemaUtil.describeAccessibleObject('Definitely_Not_A_Real_Object__x');
            System.assert(false, 'Expected OI_ValidationException for an unknown object.');
        } catch (OI_ValidationException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testDescribeAccessibleObjectThrowsValidationExceptionForBlankInput() {
        try {
            OI_RecordSchemaUtil.describeAccessibleObject(null);
            System.assert(false, 'Expected OI_ValidationException for a blank object API name.');
        } catch (OI_ValidationException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testResolveNameFieldFindsAccountName() {
        Schema.DescribeSObjectResult describe = OI_RecordSchemaUtil.describeAccessibleObject('Account');
        System.assertEquals('Name', OI_RecordSchemaUtil.resolveNameField(describe));
    }

    @isTest
    static void testLabelForReturnsPlaceholderWhenTheNameFieldIsNull() {
        Account a = new Account();
        System.assertEquals('(no name)', OI_RecordSchemaUtil.labelFor(a, 'Name'));
    }

    @isTest
    static void testRecordNodeKeyAndTypeKeyAreDistinctlyNamespacedFromMetadataKeys() {
        String nodeKey = OI_RecordSchemaUtil.recordNodeKey('Account', '001000000000001');
        String typeKey = OI_RecordSchemaUtil.recordTypeKey('Account');
        System.assert(nodeKey.startsWith('Record::'), 'Record node keys must never collide with metadata node key formats.');
        System.assert(typeKey.startsWith('SalesforceRecord.'), 'Record type keys must never collide with SalesforceMetadata.* type keys.');
    }
}
