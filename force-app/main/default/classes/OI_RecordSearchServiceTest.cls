@isTest
private class OI_RecordSearchServiceTest {
    @isTest
    static void testSearchReturnsMatchingRecordsForTheGivenObjectOnly() {
        insert new Account(Name = 'Acme Corp');
        insert new Contact(LastName = 'Acme Contact');

        List<OI_RecordSummaryDTO> results = new OI_RecordSearchService().search('Account', 'Acme');

        System.assertEquals(1, results.size());
        System.assertEquals('Acme Corp', results[0].label);
        System.assertEquals('Account', results[0].objectApiName);
    }

    @isTest
    static void testSearchBelowMinimumQueryLengthReturnsEmptyNotAnError() {
        System.assertEquals(0, new OI_RecordSearchService().search('Account', 'a').size());
    }

    @isTest
    static void testSearchWithBlankQueryReturnsEmpty() {
        System.assertEquals(0, new OI_RecordSearchService().search('Account', null).size());
    }

    @isTest
    static void testSearchForAnUnknownObjectThrowsValidationException() {
        try {
            new OI_RecordSearchService().search('Definitely_Not_Real__x', 'Acme');
            System.assert(false, 'Expected OI_ValidationException for an unknown object.');
        } catch (OI_ValidationException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testSearchEscapesSingleQuotesInTheQueryTermRatherThanErroring() {
        List<OI_RecordSummaryDTO> results = new OI_RecordSearchService().search('Account', 'O\'Brien');
        System.assertEquals(0, results.size(), 'No match expected, but the call itself must not throw a SOQL syntax error.');
    }
}
