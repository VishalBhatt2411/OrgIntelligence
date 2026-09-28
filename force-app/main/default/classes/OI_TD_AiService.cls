/**
 * Purpose: "Explain with AI" for Tech Debt findings and components (Google Gemini
 *          generateContent API — see ADR-0030 for why Gemini replaced Anthropic).
 * Responsibilities: Build the product's prompts, call the model through the OI_Gemini Named
 *                    Credential (the API key never lives in code or data — it is the ApiKey
 *                    parameter of the OI_Gemini_Principal External Credential principal, sent as
 *                    the x-goog-api-key header), retry transient failures and parse replies.
 * Dependencies: Named Credential OI_Gemini, OI_IntegrationException.
 * Inputs: OI_TD_Finding__c records, or a component type/name/description (clipped source).
 * Outputs: FindingExplanation (explanation + recommendation) or plain explanation text.
 * Limitations: Synchronous callout (≤ 120 s) — answers are short (maxOutputTokens 1200, which on
 *              Gemini includes "thinking" tokens, so thinking is pinned to "low"). Retries are
 *              immediate (Apex cannot sleep), so a per-minute free-tier 429 may outlast them.
 *              On the free tier Google may use prompt content (including org source) to improve
 *              its products — see ADR-0030 before any AppExchange release.
 */
public with sharing class OI_TD_AiService {
  /** Newest stable Flash model on the Gemini free tier (ADR-0030). The single place to change it. */
  public static final String MODEL = 'gemini-3.8-flash';
  public static final Integer MAX_TOKENS = 1200;
  public static final Integer SOURCE_CHAR_LIMIT = 6000;
  private static final String ENDPOINT =
    'callout:OI_Gemini/v1beta/models/' +
    MODEL +
    ':generateContent';
  private static final String THINKING_LEVEL = 'low';
  private static final Integer MAX_RETRIES = 2;
  private static final Pattern TRANSIENT_ERROR = Pattern.compile(
    '(?i)overloaded|high demand|rate limit|RESOURCE_EXHAUSTED|UNAVAILABLE|\\b(429|503|529)\\b'
  );
  private static final Pattern EXPLANATION_RE = Pattern.compile(
    '(?is)EXPLANATION:\\s*(.*?)RECOMMENDATION:'
  );
  private static final Pattern RECOMMENDATION_RE = Pattern.compile(
    '(?is)RECOMMENDATION:\\s*(.*)'
  );

  public class FindingExplanation {
    public String explanation;
    public String recommendation;
  }

  public static String findingPrompt(OI_TD_Finding__c f) {
    return 'You are a Salesforce technical architect. A scan flagged this technical debt finding:\n\n' +
      'Category: ' +
      f.Category__c +
      '\n' +
      'Rule: ' +
      f.Rule_Key__c +
      '\n' +
      'Severity: ' +
      f.Severity__c +
      '\n' +
      'Component: ' +
      f.Component_Type__c +
      ' "' +
      f.Component_Name__c +
      '"\n' +
      'Title: ' +
      f.Title__c +
      '\n' +
      'Detail: ' +
      f.Detail__c +
      '\n\n' +
      'Reply with exactly two sections, plain text, no markdown headers:\n' +
      'EXPLANATION: <2-3 sentences explaining why this matters in plain English>\n' +
      'RECOMMENDATION: <concrete, actionable steps to fix it>';
  }

  public static FindingExplanation explainFinding(OI_TD_Finding__c f) {
    return parseFindingReply(call(findingPrompt(f)));
  }

  @TestVisible
  private static FindingExplanation parseFindingReply(String text) {
    FindingExplanation out = new FindingExplanation();
    Matcher em = EXPLANATION_RE.matcher(text);
    Matcher rm = RECOMMENDATION_RE.matcher(text);
    String explanation = em.find() ? em.group(1).trim() : '';
    out.explanation = String.isBlank(explanation) ? text : explanation;
    out.recommendation = rm.find() ? rm.group(1).trim() : '';
    return out;
  }

  public static String explainComponent(
    String type,
    String name,
    String description
  ) {
    String prompt =
      'You are a Salesforce technical architect. Explain what this component does, in plain English, for someone unfamiliar with it. 3-5 sentences, no markdown, no headers.\n\n' +
      'Component type: ' +
      type +
      '\n' +
      'Name: ' +
      name +
      '\n' +
      description;
    return call(prompt).trim();
  }

  public static String clip(String source) {
    return source == null ? '' : source.left(SOURCE_CHAR_LIMIT);
  }

  @TestVisible
  private static String call(String prompt) {
    Integer attempt = 0;
    String reply = null;
    Boolean answered = false;
    while (!answered) {
      try {
        reply = send(prompt);
        answered = true;
      } catch (OI_IntegrationException e) {
        Boolean retryable = TRANSIENT_ERROR.matcher(e.getMessage()).find();
        if (!retryable || attempt >= MAX_RETRIES) {
          throw e;
        }
        attempt++;
      }
    }
    return reply;
  }

  private static String send(String prompt) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(ENDPOINT);
    req.setMethod('POST');
    req.setTimeout(120000);
    req.setHeader('Content-Type', 'application/json');
    req.setBody(
      JSON.serialize(
        new Map<String, Object>{
          'contents' => new List<Object>{
            new Map<String, Object>{
              'role' => 'user',
              'parts' => new List<Object>{
                new Map<String, Object>{ 'text' => prompt }
              }
            }
          },
          'generationConfig' => new Map<String, Object>{
            'maxOutputTokens' => MAX_TOKENS,
            'thinkingConfig' => new Map<String, Object>{
              'thinkingLevel' => THINKING_LEVEL
            }
          }
        }
      )
    );
    HttpResponse res;
    try {
      res = new Http().send(req);
    } catch (CalloutException e) {
      throw new OI_IntegrationException(
        'AI provider unreachable: ' + e.getMessage()
      );
    }
    Integer code = res.getStatusCode();
    if (code < 200 || code >= 300) {
      throw new OI_IntegrationException(
        'AI provider error ' + code + ': ' + errorMessage(res.getBody())
      );
    }
    return replyText(res.getBody());
  }

  /**
   * Joins candidates[0].content.parts[].text, skipping "thought" parts. A 200 can still carry no
   * answer — the prompt was blocked (promptFeedback.blockReason) or the candidate was stopped
   * (finishReason SAFETY / MAX_TOKENS …) — which is reported as a clear, non-retryable error.
   */
  @TestVisible
  private static String replyText(String responseBody) {
    Map<String, Object> body;
    try {
      body = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
    } catch (Exception e) {
      throw new OI_IntegrationException(
        'AI provider returned an unreadable response.'
      );
    }
    List<Object> candidates = (List<Object>) body.get('candidates');
    if (candidates == null || candidates.isEmpty()) {
      Map<String, Object> feedback = (Map<String, Object>) body.get(
        'promptFeedback'
      );
      Object blockReason = feedback == null
        ? null
        : feedback.get('blockReason');
      throw new OI_IntegrationException(
        blockReason == null
          ? 'AI provider returned no answer.'
          : 'AI provider blocked the prompt: ' + String.valueOf(blockReason)
      );
    }
    Map<String, Object> candidate = (Map<String, Object>) candidates[0];
    Map<String, Object> content = (Map<String, Object>) candidate.get(
      'content'
    );
    List<Object> rawParts = content == null
      ? null
      : (List<Object>) content.get('parts');
    List<String> texts = new List<String>();
    for (Object raw : rawParts == null ? new List<Object>() : rawParts) {
      Map<String, Object> part = (Map<String, Object>) raw;
      if (part.get('thought') != true && part.get('text') instanceof String) {
        texts.add((String) part.get('text'));
      }
    }
    String reply = String.join(texts, '');
    if (String.isBlank(reply)) {
      throw new OI_IntegrationException(
        'AI provider returned no answer (finish reason: ' +
          String.valueOf(candidate.get('finishReason')) +
          ').'
      );
    }
    return reply;
  }

  /** Gemini errors are {"error":{"code":429,"message":"…","status":"RESOURCE_EXHAUSTED"}}. */
  private static String errorMessage(String body) {
    try {
      Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
        body
      );
      Map<String, Object> err = (Map<String, Object>) parsed.get('error');
      return err == null
        ? body.left(300)
        : String.valueOf(err.get('status')) +
          ' — ' +
          String.valueOf(err.get('message')).left(300);
    } catch (Exception e) {
      return body == null ? '' : body.left(300);
    }
  }
}
