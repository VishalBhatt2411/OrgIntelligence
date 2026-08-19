@isTest
private class OI_ComponentKeyUtilTest {
    @isTest
    static void testBuildThenParseRoundTrips() {
        String key = OI_ComponentKeyUtil.build('CustomField', 'NS', 'Account.NS__Field__c');
        OI_ComponentKeyUtil.ParsedComponentKey parsed = OI_ComponentKeyUtil.parse(key);
        System.assertEquals('CustomField', parsed.componentKind);
        System.assertEquals('NS', parsed.namespace);
        System.assertEquals('Account.NS__Field__c', parsed.fullyQualifiedName);
    }

    @isTest
    static void testBuildWithNullNamespaceParsesBackToNull() {
        String key = OI_ComponentKeyUtil.build('CustomObject', null, 'Account');
        OI_ComponentKeyUtil.ParsedComponentKey parsed = OI_ComponentKeyUtil.parse(key);
        System.assertEquals(null, parsed.namespace);
        System.assertEquals('Account', parsed.fullyQualifiedName);
    }

    @isTest
    static void testParseOfBlankReturnsNull() {
        System.assertEquals(null, OI_ComponentKeyUtil.parse(null));
        System.assertEquals(null, OI_ComponentKeyUtil.parse(''));
    }

    @isTest
    static void testExtractNamespaceFromApiNameFollowsManagedPackageConvention() {
        System.assertEquals('NS', OI_ComponentKeyUtil.extractNamespaceFromApiName('NS__Object__c'));
        System.assertEquals(null, OI_ComponentKeyUtil.extractNamespaceFromApiName('Object__c'));
        System.assertEquals(null, OI_ComponentKeyUtil.extractNamespaceFromApiName('Account'));
    }
}
