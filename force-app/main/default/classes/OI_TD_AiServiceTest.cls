/**
 * Purpose: Verifies OI_TD_AiService's Gemini generateContent calls (via the OI_Gemini Named
 *          Credential): request shape, reply parsing, blocked/empty candidates, transient-error
 *          retries and error translation.
 */
@isTest
private class OI_TD_AiServiceTest {
  private static final String ANSWER_BODY =
    '{"candidates":[{"content":{"role":"model","parts":[' +
    '{"text":"thinking out loud","thought":true},' +
    '{"text":"EXPLANATION: Loops hit limits.\\n"},{"text":"RECOMMENDATION: Bulkify."}' +
    ']},"finishReason":"STOP"}]}';

  /** Replays the given status codes in order; 2xx responses carry successBody. */
  private class SequenceMock implements HttpCalloutMock {
    private List<Integer> codes;
    private String errorBody;
    private String successBody = ANSWER_BODY;
    public Integer calls = 0;
    SequenceMock(List<Integer> codes, String errorBody) {
      this.codes = codes;
      this.errorBody = errorBody;
    }
    SequenceMock withSuccessBody(String body) {
      this.successBody = body;
      return this;
    }
    public HttpResponse respond(HttpRequest req) {
      System.assertEquals(
        'callout:OI_Gemini/v1beta/models/' +
          OI_TD_AiService.MODEL +
          ':generateContent',
        req.getEndpoint()
      );
      System.assertEquals('POST', req.getMethod());
      System.assertEquals(null, req.getHeader('anthropic-version'));
      Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(
        req.getBody()
      );
      Map<String, Object> content = (Map<String, Object>) ((List<Object>) sent.get(
        'contents'
      ))[0];
      System.assertEquals('user', content.get('role'));
      Map<String, Object> part = (Map<String, Object>) ((List<Object>) content.get(
        'parts'
      ))[0];
      System.assert(
        String.isNotBlank((String) part.get('text')),
        'The prompt must be sent as parts[0].text.'
      );
      Map<String, Object> config = (Map<String, Object>) sent.get(
        'generationConfig'
      );
      System.assertEquals(
        OI_TD_AiService.MAX_TOKENS,
        config.get('maxOutputTokens')
      );

      Integer code = codes[Math.min(calls, codes.size() - 1)];
      calls++;
      HttpResponse res = new HttpResponse();
      res.setStatusCode(code);
      res.setBody(code == 200 ? successBody : errorBody);
      return res;
    }
  }

  private static OI_TD_Finding__c finding() {
    return new OI_TD_Finding__c(
      Category__c = 'governor_limits',
      Rule_Key__c = 'soql_in_loop',
      Severity__c = 'high',
      Title__c = 'SOQL in loop',
      Detail__c = 'Line 4',
      Component_Type__c = 'ApexClass',
      Component_Name__c = 'Svc'
    );
  }

  private static String callExpectingError(SequenceMock mock) {
    Test.setMock(HttpCalloutMock.class, mock);
    try {
      OI_TD_AiService.call('hi');
      System.assert(false, 'expected an integration error');
    } catch (OI_IntegrationException e) {
      return e.getMessage();
    }
    return null;
  }

  @isTest
  static void explainFindingParsesSectionsAndSkipsThoughtParts() {
    Test.setMock(
      HttpCalloutMock.class,
      new SequenceMock(new List<Integer>{ 200 }, null)
    );
    Test.startTest();
    OI_TD_AiService.FindingExplanation e = OI_TD_AiService.explainFinding(
      finding()
    );
    Test.stopTest();
    System.assertEquals('Loops hit limits.', e.explanation);
    System.assertEquals('Bulkify.', e.recommendation);
    System.assert(
      !e.explanation.contains('thinking'),
      'Thought parts must never reach the user.'
    );
    System.assert(
      OI_TD_AiService.findingPrompt(finding())
        .contains('Component: ApexClass "Svc"')
    );
  }

  @isTest
  static void rateLimitErrorsAreRetried() {
    SequenceMock mock = new SequenceMock(
      new List<Integer>{ 429, 429, 200 },
      '{"error":{"code":429,"message":"Quota exceeded","status":"RESOURCE_EXHAUSTED"}}'
    );
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    String text = OI_TD_AiService.explainComponent(
      'ApexClass',
      'Svc',
      'source'
    );
    Test.stopTest();
    System.assert(text.startsWith('EXPLANATION'), text);
    System.assertEquals(3, mock.calls);
  }

  @isTest
  static void retriesGiveUpAfterLimit() {
    SequenceMock mock = new SequenceMock(
      new List<Integer>{ 503 },
      '{"error":{"code":503,"message":"The model is overloaded.","status":"UNAVAILABLE"}}'
    );
    Test.startTest();
    String message = callExpectingError(mock);
    Test.stopTest();
    System.assertEquals(
      'AI provider error 503: UNAVAILABLE — The model is overloaded.',
      message
    );
    System.assertEquals(3, mock.calls);
  }

  @isTest
  static void permanentErrorsAreNotRetried() {
    SequenceMock mock = new SequenceMock(
      new List<Integer>{ 400 },
      '{"error":{"code":400,"message":"API key not valid.","status":"INVALID_ARGUMENT"}}'
    );
    Test.startTest();
    String message = callExpectingError(mock);
    Test.stopTest();
    System.assertEquals(
      'AI provider error 400: INVALID_ARGUMENT — API key not valid.',
      message
    );
    System.assertEquals(1, mock.calls);
  }

  @isTest
  static void nonJsonErrorBodyIsReportedVerbatim() {
    SequenceMock mock = new SequenceMock(
      new List<Integer>{ 500 },
      'Internal error'
    );
    Test.startTest();
    String message = callExpectingError(mock);
    Test.stopTest();
    System.assertEquals('AI provider error 500: Internal error', message);
    System.assertEquals(1, mock.calls);
  }

  @isTest
  static void blockedPromptReportsTheBlockReasonWithoutRetrying() {
    SequenceMock mock = new SequenceMock(new List<Integer>{ 200 }, null)
      .withSuccessBody('{"promptFeedback":{"blockReason":"SAFETY"}}');
    Test.startTest();
    String message = callExpectingError(mock);
    Test.stopTest();
    System.assertEquals('AI provider blocked the prompt: SAFETY', message);
    System.assertEquals(1, mock.calls);
  }

  @isTest
  static void emptyCandidatesArrayIsAClearError() {
    SequenceMock mock = new SequenceMock(new List<Integer>{ 200 }, null)
      .withSuccessBody('{"candidates":[]}');
    Test.startTest();
    String message = callExpectingError(mock);
    Test.stopTest();
    System.assertEquals('AI provider returned no answer.', message);
  }

  @isTest
  static void candidateWithoutTextReportsItsFinishReason() {
    SequenceMock mock = new SequenceMock(new List<Integer>{ 200 }, null)
      .withSuccessBody('{"candidates":[{"finishReason":"SAFETY"}]}');
    Test.startTest();
    String message = callExpectingError(mock);
    Test.stopTest();
    System.assertEquals(
      'AI provider returned no answer (finish reason: SAFETY).',
      message
    );
    System.assertEquals(1, mock.calls);
  }

  @isTest
  static void unreadableSuccessBodyIsAClearError() {
    SequenceMock mock = new SequenceMock(new List<Integer>{ 200 }, null)
      .withSuccessBody('<html>');
    Test.startTest();
    String message = callExpectingError(mock);
    Test.stopTest();
    System.assertEquals(
      'AI provider returned an unreadable response.',
      message
    );
  }

  @isTest
  static void replyParsingAndClipping() {
    OI_TD_AiService.FindingExplanation plain = OI_TD_AiService.parseFindingReply(
      'Just some text'
    );
    System.assertEquals('Just some text', plain.explanation);
    System.assertEquals('', plain.recommendation);
    System.assertEquals('', OI_TD_AiService.clip(null));
    System.assertEquals(
      OI_TD_AiService.SOURCE_CHAR_LIMIT,
      OI_TD_AiService.clip('x'.repeat(7000)).length()
    );
  }
}
