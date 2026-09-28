/**
 * Purpose: Verifies OI_TD_ToolingClient's paged Tooling queries and REST GETs through the
 *          OI_Self_Callout Named Credential, including error translation.
 */
@isTest
private class OI_TD_ToolingClientTest {
  private class ApiMock implements HttpCalloutMock {
    private Integer code;
    private String firstBody;
    public List<String> endpoints = new List<String>();
    ApiMock(Integer code, String firstBody) {
      this.code = code;
      this.firstBody = firstBody;
    }
    public HttpResponse respond(HttpRequest req) {
      endpoints.add(req.getEndpoint());
      HttpResponse res = new HttpResponse();
      res.setStatusCode(code);
      if (req.getEndpoint().contains('/query/01g')) {
        res.setBody('{"done":true,"records":[{"Id":"b"}]}');
      } else {
        res.setBody(firstBody);
      }
      return res;
    }
  }

  @isTest
  static void queryAllFollowsNextRecordsUrl() {
    ApiMock mock = new ApiMock(
      200,
      '{"done":false,"nextRecordsUrl":"/services/data/v67.0/tooling/query/01g-2000","records":[{"Id":"a"},"junk"]}'
    );
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    List<Map<String, Object>> rows = new OI_TD_ToolingClient()
      .queryAll('SELECT Id FROM ApexClass', 5);
    Test.stopTest();
    System.assertEquals(2, rows.size());
    System.assertEquals('b', rows[1].get('Id'));
    System.assert(
      mock.endpoints[0]
        .startsWith(
          'callout:OI_Self_Callout/services/data/v67.0/tooling/query/?q='
        )
    );
  }

  @isTest
  static void queryAllStopsAtMaxPages() {
    Test.setMock(
      HttpCalloutMock.class,
      new ApiMock(
        200,
        '{"done":false,"nextRecordsUrl":"/next","records":[{"Id":"a"}]}'
      )
    );
    Test.startTest();
    List<Map<String, Object>> rows = new OI_TD_ToolingClient()
      .queryAll('SELECT Id FROM ApexClass', 1);
    OI_TD_ToolingClient.QueryPage donePage = new OI_TD_ToolingClient()
      .nextPage('/services/data/v67.0/tooling/query/01g-3');
    Test.stopTest();
    System.assertEquals(1, rows.size());
    System.assertEquals(null, donePage.nextRecordsUrl);
  }

  @isTest
  static void errorsAreTranslated() {
    OI_TD_ToolingClient client = new OI_TD_ToolingClient();
    try {
      client.queryPage('  ');
      System.assert(false, 'expected a validation error');
    } catch (OI_ValidationException e) {
      System.assertEquals('A Tooling API query is required.', e.getMessage());
    }

    Test.setMock(HttpCalloutMock.class, new ApiMock(500, 'Server error'));
    try {
      client.get(OI_TD_ToolingClient.describeGlobalPath());
      System.assert(false, 'expected a service error');
    } catch (OI_ServiceException e) {
      System.assertEquals(
        'The Salesforce API returned an error (status 500): Server error',
        e.getMessage()
      );
    }

    Test.setMock(HttpCalloutMock.class, new ApiMock(200, 'not json'));
    try {
      client.queryPage('SELECT Id FROM ApexClass');
      System.assert(false, 'expected a service error');
    } catch (OI_ServiceException e) {
      System.assertEquals(
        'The Tooling API response could not be parsed.',
        e.getMessage()
      );
    }
  }

  @isTest
  static void describePath() {
    System.assertEquals(
      '/services/data/v67.0/sobjects/',
      OI_TD_ToolingClient.describeGlobalPath()
    );
  }
}
