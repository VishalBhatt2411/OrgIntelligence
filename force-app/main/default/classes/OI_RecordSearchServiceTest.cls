@isTest
private class OI_RecordSearchServiceTest {
  @isTest
  static void testSearchReturnsMatchingRecordsForTheGivenObjectOnly() {
    insert new Account(Name = 'Acme Corp');
    insert new Contact(LastName = 'Acme Contact');

    List<OI_RecordSummaryDTO> results = new OI_RecordSearchService()
      .search('Account', 'Acme');

    System.assertEquals(1, results.size());
    System.assertEquals('Acme Corp', results[0].label);
    System.assertEquals('Account', results[0].objectApiName);
  }

  @isTest
  static void testSearchBelowMinimumQueryLengthReturnsEmptyNotAnError() {
    System.assertEquals(
      0,
      new OI_RecordSearchService().search('Account', 'a').size()
    );
  }

  @isTest
  static void testSearchWithBlankQueryReturnsEmpty() {
    System.assertEquals(
      0,
      new OI_RecordSearchService().search('Account', null).size()
    );
  }

  @isTest
  static void testBrowseReturnsAllRecordsForTheGivenObjectOrderedAlphabetically() {
    insert new List<Account>{
      new Account(Name = 'Zebra Corp'),
      new Account(Name = 'Acme Corp')
    };
    insert new Contact(LastName = 'Should Not Appear');

    List<OI_RecordSummaryDTO> results = new OI_RecordSearchService()
      .browse('Account');

    System.assertEquals(
      2,
      results.size(),
      'Only records of the requested object must be returned.'
    );
    System.assertEquals(
      'Acme Corp',
      results[0].label,
      'Results must be ordered alphabetically by the object\'s Name field.'
    );
    System.assertEquals('Zebra Corp', results[1].label);
    System.assertEquals('Account', results[0].objectApiName);
  }

  @isTest
  static void testBrowseForAnUnknownObjectThrowsValidationException() {
    try {
      new OI_RecordSearchService().browse('Definitely_Not_Real__x');
      System.assert(
        false,
        'Expected OI_ValidationException for an unknown object.'
      );
    } catch (OI_ValidationException e) {
      System.assert(true);
    }
  }

  @isTest
  static void testSearchForAnUnknownObjectThrowsValidationException() {
    try {
      new OI_RecordSearchService().search('Definitely_Not_Real__x', 'Acme');
      System.assert(
        false,
        'Expected OI_ValidationException for an unknown object.'
      );
    } catch (OI_ValidationException e) {
      System.assert(true);
    }
  }

  @isTest
  static void testSearchEscapesSingleQuotesInTheQueryTermRatherThanErroring() {
    List<OI_RecordSummaryDTO> results = new OI_RecordSearchService()
      .search('Account', 'O\'Brien');
    System.assertEquals(
      0,
      results.size(),
      'No match expected, but the call itself must not throw a SOQL syntax error.'
    );
  }
}
