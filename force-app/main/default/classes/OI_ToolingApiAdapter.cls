/**
 * Purpose: The single choke point for Tooling API callouts (Architecture.md's scanner/service
 *          rule: "Calls the relevant Adapter [...] — never a raw HTTP callout [...] from the
 *          scanner itself") — currently backs OI_ObjectSharingSettingsService's Object-level
 *          Sharing Settings (OWD) read, the first Tooling-API-only fact this platform surfaces
 *          (Apex Describe has no accessor for sharing model — see OI_ObjectScanner's own
 *          documented gap).
 * Responsibilities: Issue one Tooling API SOQL query against the RUNNING ORG's own Tooling API
 *                    endpoint and return its records as a plain, generically-typed list — never
 *                    interprets the query or its result, which stays entirely the calling
 *                    service's concern (this Adapter must never learn what EntityDefinition or
 *                    ProcessDefinition mean, mirroring OI_GraphEngine's own "stay generic"
 *                    discipline, ADR-0013).
 * Dependencies: The `OI_Self_Callout` Named Credential (backed by the `OI_Self_Callout_Credential`
 *               External Credential, OAuth 2.0 Client Credentials flow against this same org's
 *               own token endpoint) — see ADR-0029.
 * Limitations: Same-org callout only, but NOT session-based despite that: an earlier version of
 *              this Adapter authenticated with the running user's own session
 *              (UserInfo.getSessionId()), on the reasoning that a callout back to the same org
 *              needs no Remote Site Setting and elevates nothing beyond the running user's own
 *              access. That reasoning held for Visualforce-issued sessions but NOT for
 *              Lightning/Aura-issued ones — a session obtained via `UserInfo.getSessionId()`
 *              inside an `@AuraEnabled` method (i.e. every call this Adapter actually receives,
 *              since every caller reaches it through OI_GraphController) is deliberately scoped
 *              down by the platform and Tooling API rejects it with HTTP 401. Confirmed live: the
 *              identical query succeeded via `sf apex run` (API-scoped CLI session) and failed
 *              with 401 through the real LWC UI. See ADR-0029 for the full trade-off. Because of
 *              this, the endpoint really IS a same-org self-callout, but it is package-installable
 *              rather than zero-config: the installing admin completes a documented one-time setup
 *              (an External Client App with Client Credentials Flow + Run As user, the External
 *              Credential's principal Client Id/Secret, and pointing this Named Credential's URL
 *              at their own org's domain) — see ADR-0029's setup section. This callout still
 *              elevates nothing beyond what the configured Run As user could see querying Tooling
 *              API directly, so it introduces no additional privilege-escalation surface for a
 *              Security Review beyond that one documented Run As identity. `query` is `virtual`
 *              solely so a test can extend this
 *              class with an in-memory fake (CodingStandards.md's DI-based-fake convention for
 *              Adapter dependencies) — this class's OWN test instead exercises the real HTTP
 *              path via Test.setMock/HttpCalloutMock, per CodingStandards.md's Adapter-test
 *              rule. Bounded to a single, unpaged query per call; the calling service is
 *              responsible for keeping that query small enough to answer on one page — every
 *              current caller's query returns at most one row, so Tooling API's own pagination
 *              is not implemented here.
 */
public virtual with sharing class OI_ToolingApiAdapter {
  private static final String NAMED_CREDENTIAL = 'OI_Self_Callout';
  private static final String TOOLING_API_VERSION = 'v67.0';
  private static final Integer CALLOUT_TIMEOUT_MS = 10000;

  public virtual List<Map<String, Object>> query(String soql) {
    if (String.isBlank(soql)) {
      throw new OI_ValidationException('A Tooling API query is required.');
    }

    HttpRequest request = new HttpRequest();
    request.setEndpoint(
      'callout:' +
        NAMED_CREDENTIAL +
        '/services/data/' +
        TOOLING_API_VERSION +
        '/tooling/query/?q=' +
        EncodingUtil.urlEncode(soql, 'UTF-8')
    );
    request.setMethod('GET');
    request.setTimeout(CALLOUT_TIMEOUT_MS);

    HttpResponse response;
    try {
      response = new Http().send(request);
    } catch (CalloutException e) {
      throw new OI_ServiceException('The Tooling API could not be reached.');
    }

    if (response.getStatusCode() != 200) {
      throw new OI_ServiceException(
        'The Tooling API returned an error (status ' +
          response.getStatusCode() +
          ').'
      );
    }

    return parseRecords(response.getBody());
  }

  /** Isolated so a malformed/unexpected body (never expected from a 200 Tooling API response, but never trusted blindly either) reports the same sanitized failure as a callout error, rather than leaking a raw deserialization exception. */
  private List<Map<String, Object>> parseRecords(String responseBody) {
    try {
      Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
        responseBody
      );
      Object rawRecords = parsed.get('records');
      List<Map<String, Object>> records = new List<Map<String, Object>>();
      if (rawRecords instanceof List<Object>) {
        for (Object rawRecord : (List<Object>) rawRecords) {
          if (rawRecord instanceof Map<String, Object>) {
            records.add((Map<String, Object>) rawRecord);
          }
        }
      }
      return records;
    } catch (Exception e) {
      throw new OI_ServiceException(
        'The Tooling API response could not be parsed.'
      );
    }
  }
}
