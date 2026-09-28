/**
 * Purpose: Verifies OI_MetadataApiAdapter's SOAP-callout contract — the endpoint/envelope shape
 *          it sends, the generic node-to-map/list parsing of a readMetadata response, and the
 *          sanitized exceptions it raises for every failure mode. Per CodingStandards.md's
 *          Adapter-test rule, every test here uses Test.setMock/HttpCalloutMock — no test depends
 *          on a live Metadata API callout succeeding.
 */
@isTest
private class OI_MetadataApiAdapterTest {
  private static final String READ_METADATA_RESPONSE =
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://soap.sforce.com/2006/04/metadata">' +
    '<soapenv:Body>' +
    '<readMetadataResponse>' +
    '<result>' +
    '<fullName>Account</fullName>' +
    '<sharingCriteriaRules>' +
    '<fullName>Account.Share_To_Sales</fullName>' +
    '<accessLevel>Read</accessLevel>' +
    '<sharedTo><role>Sales_Manager</role></sharedTo>' +
    '</sharingCriteriaRules>' +
    '<sharingCriteriaRules>' +
    '<fullName>Account.Share_To_Support</fullName>' +
    '<accessLevel>Edit</accessLevel>' +
    '</sharingCriteriaRules>' +
    '</result>' +
    '<result>' +
    '<fullName>Case</fullName>' +
    '</result>' +
    '</readMetadataResponse>' +
    '</soapenv:Body>' +
    '</soapenv:Envelope>';

  private static final String INVALID_SESSION_FAULT =
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">' +
    '<soapenv:Body>' +
    '<soapenv:Fault>' +
    '<faultcode>INVALID_SESSION_ID</faultcode>' +
    '<faultstring>INVALID_SESSION_ID: Invalid Session ID found in SessionHeader</faultstring>' +
    '</soapenv:Fault>' +
    '</soapenv:Body>' +
    '</soapenv:Envelope>';

  @isTest
  static void testReadMetadataParsesRepeatedAndNestedElementsIntoGenericMapsAndLists() {
    Test.setMock(
      HttpCalloutMock.class,
      new FakeMetadataApiResponse(200, READ_METADATA_RESPONSE)
    );

    List<Map<String, Object>> results = new OI_MetadataApiAdapter()
      .readMetadata('SharingRules', new List<String>{ 'Account', 'Case' });

    System.assertEquals(2, results.size());
    Map<String, Object> accountResult = results[0];
    System.assertEquals('Account', accountResult.get('fullName'));
    Object rulesRaw = accountResult.get('sharingCriteriaRules');
    System.assert(
      rulesRaw instanceof List<Object>,
      'A repeated element name must become a List.'
    );
    List<Object> rules = (List<Object>) rulesRaw;
    System.assertEquals(2, rules.size());
    Map<String, Object> firstRule = (Map<String, Object>) rules[0];
    System.assertEquals('Account.Share_To_Sales', firstRule.get('fullName'));
    System.assertEquals('Read', firstRule.get('accessLevel'));
    Map<String, Object> sharedTo = (Map<String, Object>) firstRule.get(
      'sharedTo'
    );
    System.assertEquals(
      'Sales_Manager',
      sharedTo.get('role'),
      'A nested element must become a nested Map.'
    );
    Map<String, Object> secondRule = (Map<String, Object>) rules[1];
    System.assertEquals('Edit', secondRule.get('accessLevel'));

    Map<String, Object> caseResult = results[1];
    System.assertEquals('Case', caseResult.get('fullName'));
    System.assertEquals(
      false,
      caseResult.containsKey('sharingCriteriaRules'),
      'An object with no Sharing Rules has no repeated child elements to report.'
    );
  }

  @isTest
  static void testReadMetadataSendsTheSessionHeaderMergeFieldAndRequestedFullNames() {
    FakeMetadataApiResponse mock = new FakeMetadataApiResponse(
      200,
      READ_METADATA_RESPONSE
    );
    Test.setMock(HttpCalloutMock.class, mock);

    new OI_MetadataApiAdapter()
      .readMetadata('SharingRules', new List<String>{ 'Account', 'Case' });

    System.assert(
      mock.capturedRequest.getEndpoint().startsWith('callout:OI_Self_Callout/'),
      'The endpoint must go through the OI_Self_Callout Named Credential.'
    );
    System.assert(
      mock.capturedRequest.getEndpoint().endsWith('/services/Soap/m/67.0')
    );
    String body = mock.capturedRequest.getBody();
    System.assert(
      body.contains('{!$Credential.OAuthToken}'),
      'OAuth authentication for a classic SOAP API must be a SessionHeader body merge field, never a bare Bearer header.'
    );
    System.assert(body.contains('<met:type>SharingRules</met:type>'));
    System.assert(body.contains('<met:fullNames>Account</met:fullNames>'));
    System.assert(body.contains('<met:fullNames>Case</met:fullNames>'));
  }

  @isTest
  static void testReadMetadataThrowsServiceExceptionWithTheFaultStringOnASoapFault() {
    Test.setMock(
      HttpCalloutMock.class,
      new FakeMetadataApiResponse(500, INVALID_SESSION_FAULT)
    );

    try {
      new OI_MetadataApiAdapter()
        .readMetadata('SharingRules', new List<String>{ 'Account' });
      System.assert(false, 'Expected an OI_ServiceException for a SOAP fault.');
    } catch (OI_ServiceException e) {
      System.assert(
        e.getMessage().contains('INVALID_SESSION_ID'),
        'The permanent no-token-refresh limitation on SOAP merge-field auth surfaces as this exact fault — the message must carry it through for diagnosis.'
      );
    }
  }

  @isTest
  static void testReadMetadataThrowsServiceExceptionWhenTheResponseBodyIsNotParseableXml() {
    Test.setMock(
      HttpCalloutMock.class,
      new FakeMetadataApiResponse(200, 'not xml')
    );

    try {
      new OI_MetadataApiAdapter()
        .readMetadata('SharingRules', new List<String>{ 'Account' });
      System.assert(
        false,
        'Expected an OI_ServiceException for an unparseable body.'
      );
    } catch (OI_ServiceException e) {
      System.assert(true);
    }
  }

  @isTest
  static void testReadMetadataThrowsValidationExceptionForABlankType() {
    try {
      new OI_MetadataApiAdapter()
        .readMetadata('   ', new List<String>{ 'Account' });
      System.assert(
        false,
        'Expected an OI_ValidationException for a blank type.'
      );
    } catch (OI_ValidationException e) {
      System.assert(true);
    }
  }

  @isTest
  static void testReadMetadataThrowsValidationExceptionForNoFullNames() {
    try {
      new OI_MetadataApiAdapter()
        .readMetadata('SharingRules', new List<String>());
      System.assert(
        false,
        'Expected an OI_ValidationException for an empty fullNames list.'
      );
    } catch (OI_ValidationException e) {
      System.assert(true);
    }
  }

  @isTest
  static void testReadMetadataThrowsValidationExceptionWhenMoreThanTenFullNamesAreRequested() {
    List<String> tooMany = new List<String>();
    for (Integer i = 0; i < 11; i++) {
      tooMany.add('Object_' + i);
    }

    try {
      new OI_MetadataApiAdapter().readMetadata('SharingRules', tooMany);
      System.assert(
        false,
        'Expected an OI_ValidationException — readMetadata accepts at most 10 fullNames per call, a hard Metadata API platform limit.'
      );
    } catch (OI_ValidationException e) {
      System.assert(true);
    }
  }

  private class FakeMetadataApiResponse implements HttpCalloutMock {
    private final Integer statusCode;
    private final String body;
    private HttpRequest capturedRequest;

    private FakeMetadataApiResponse(Integer statusCode, String body) {
      this.statusCode = statusCode;
      this.body = body;
    }

    public HttpResponse respond(HttpRequest request) {
      this.capturedRequest = request;
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setBody(body);
      return response;
    }
  }
}
