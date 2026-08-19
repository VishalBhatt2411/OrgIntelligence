@isTest
private class OI_ObjectScopeFilterTest {
    @isTest
    static void testAccountIsInScope() {
        System.assertEquals(true, OI_ObjectScopeFilter.isInScope(Account.SObjectType.getDescribe()));
    }

    @isTest
    static void testAccountHistoryIsExcluded() {
        System.assertEquals(false, OI_ObjectScopeFilter.isInScope(Schema.getGlobalDescribe().get('AccountHistory').getDescribe()));
    }

    @isTest
    static void testAccountShareIsExcluded() {
        System.assertEquals(false, OI_ObjectScopeFilter.isInScope(Schema.getGlobalDescribe().get('AccountShare').getDescribe()));
    }

    @isTest
    static void testNullIsNotInScope() {
        System.assertEquals(false, OI_ObjectScopeFilter.isInScope(null));
    }
}
