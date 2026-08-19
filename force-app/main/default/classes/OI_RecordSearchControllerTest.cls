@isTest
private class OI_RecordSearchControllerTest {
    @isTest
    static void testSearchRecordsReturnsResultsFromTheService() {
        insert new Account(Name = 'Acme Corp');

        List<OI_RecordSummaryDTO> results = OI_RecordSearchController.searchRecords('Account', 'Acme');

        System.assertEquals(1, results.size());
        System.assertEquals('Acme Corp', results[0].label);
    }

    @isTest
    static void testSearchRecordsWithoutPermissionThrowsAuraHandledException() {
        User unprivileged = createUnprivilegedTestUser();
        System.runAs(unprivileged) {
            try {
                OI_RecordSearchController.searchRecords('Account', 'Acme');
                System.assert(false, 'Expected AuraHandledException when OI_View_Records is not assigned.');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    @isTest
    static void testSearchRecordsForAnUnknownObjectThrowsAuraHandledExceptionNotARawException() {
        try {
            OI_RecordSearchController.searchRecords('Definitely_Not_Real__x', 'Acme');
            System.assert(false, 'Expected a sanitized AuraHandledException, not a raw internal exception leaking to the client.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    private static User createUnprivilegedTestUser() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniqueSuffix = String.valueOf(Crypto.getRandomInteger()).right(8);
        User u = new User(
            FirstName = 'OI Test',
            LastName = 'Unprivileged' + uniqueSuffix,
            Email = 'oi.test.' + uniqueSuffix + '@example.invalid',
            Username = 'oi.test.' + uniqueSuffix + '@example.invalid',
            Alias = 'oitst' + uniqueSuffix.left(3),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = standardProfile.Id
        );
        insert u;
        return u;
    }
}
