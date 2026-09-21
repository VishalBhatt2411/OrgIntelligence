/**
 * Purpose: Verifies OI_ToolingApiAdapter's HTTP-callout contract — the endpoint/auth shape it
 *          sends, the records it extracts from a successful response, and the sanitized
 *          exceptions it raises for every failure mode. Per CodingStandards.md's Adapter-test
 *          rule, every test here uses Test.setMock/HttpCalloutMock — no test depends on a live
 *          Tooling API callout succeeding.
 */
@isTest
private class OI_ToolingApiAdapterTest {
  @isTest
  static void testQueryReturnsParsedRecordsOnASuccessfulResponse() {
    Test.setMock(
      HttpCalloutMock.class,
      new FakeToolingApiResponse(
        200,
        '{"records":[{"InternalSharingModel":"ReadWrite","ExternalSharingModel":null}]}'
      )
    );

    List<Map<String, Object>> records = new OI_ToolingApiAdapter()
      .query(
        'SELECT InternalSharingModel, ExternalSharingModel FROM EntityDefinition'
      );

    System.assertEquals(1, records.size());
    System.assertEquals('ReadWrite', records[0].get('InternalSharingModel'));
    System.assertEquals(null, records[0].get('ExternalSharingModel'));
  }

  @isTest
  static void testQueryReturnsAnEmptyListWhenTheResponseHasNoRecords() {
    Test.setMock(
      HttpCalloutMock.class,
      new FakeToolingApiResponse(200, '{"records":[]}')
    );

    List<Map<String, Object>> records = new OI_ToolingApiAdapter()
      .query('SELECT InternalSharingModel FROM EntityDefinition');

    System.assertEquals(0, records.size());
  }

  @isTest
  static void testQueryCallsTheSelfCalloutNamedCredential() {
    FakeToolingApiResponse mock = new FakeToolingApiResponse(
      200,
      '{"records":[]}'
    );
    Test.setMock(HttpCalloutMock.class, mock);

    new OI_ToolingApiAdapter()
      .query('SELECT InternalSharingModel FROM EntityDefinition');

    System.assert(
      mock.capturedRequest.getEndpoint().startsWith('callout:OI_Self_Callout/'),
      'The endpoint must go through the OI_Self_Callout Named Credential — never a raw org URL or session-based auth (see ADR-0029).'
    );
    System.assert(
      mock.capturedRequest.getEndpoint()
        .contains('/services/data/v67.0/tooling/query/?q=')
    );
  }

  @isTest
  static void testQueryThrowsServiceExceptionOnANonSuccessStatus() {
    Test.setMock(
      HttpCalloutMock.class,
      new FakeToolingApiResponse(
        400,
        '[{"message":"Bad request","errorCode":"INVALID_FIELD"}]'
      )
    );

    try {
      new OI_ToolingApiAdapter()
        .query('SELECT InternalSharingModel FROM EntityDefinition');
      System.assert(
        false,
        'Expected an OI_ServiceException for a non-200 status.'
      );
    } catch (OI_ServiceException e) {
      System.assert(e.getMessage().contains('Tooling API'));
    }
  }

  @isTest
  static void testQueryThrowsServiceExceptionWhenTheResponseBodyIsNotParseableJson() {
    Test.setMock(
      HttpCalloutMock.class,
      new FakeToolingApiResponse(200, 'not json')
    );

    try {
      new OI_ToolingApiAdapter()
        .query('SELECT InternalSharingModel FROM EntityDefinition');
      System.assert(
        false,
        'Expected an OI_ServiceException for an unparseable body, never a raw deserialization exception.'
      );
    } catch (OI_ServiceException e) {
      System.assert(true);
    }
  }

  @isTest
  static void testQueryThrowsValidationExceptionForABlankQuery() {
    try {
      new OI_ToolingApiAdapter().query('   ');
      System.assert(
        false,
        'Expected an OI_ValidationException for a blank query.'
      );
    } catch (OI_ValidationException e) {
      System.assert(true);
    }
  }

  private class FakeToolingApiResponse implements HttpCalloutMock {
    private final Integer statusCode;
    private final String body;
    private HttpRequest capturedRequest;

    private FakeToolingApiResponse(Integer statusCode, String body) {
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
