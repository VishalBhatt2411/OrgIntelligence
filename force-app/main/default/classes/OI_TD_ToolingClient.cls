/**
 * Purpose: Paged Tooling API / REST reads for the Tech Debt scanner (OI_TD_ScanEngine).
 * Responsibilities: Issue one Tooling query page (following nextRecordsUrl when asked), and
 *                    one REST GET, against the running org through the `OI_Self_Callout`
 *                    Named Credential (ADR-0029). Returns plain untyped maps — never interprets
 *                    what was queried.
 * Dependencies: `OI_Self_Callout` Named Credential.
 * Limitations: Kept separate from OI_ToolingApiAdapter (single unpaged query, 10s timeout) so
 *              the scanner can page through large result sets without changing that adapter's
 *              contract. `virtual` so tests can substitute an in-memory fake.
 */
public virtual with sharing class OI_TD_ToolingClient {
  private static final String NAMED_CREDENTIAL = 'callout:OI_Self_Callout';
  private static final String API_VERSION = 'v67.0';
  private static final Integer CALLOUT_TIMEOUT_MS = 60000;

  /** One page of a Tooling query result. */
  public class QueryPage {
    public List<Map<String, Object>> records = new List<Map<String, Object>>();
    public String nextRecordsUrl;
  }

  /** Runs a Tooling SOQL query and returns its first page. */
  public virtual QueryPage queryPage(String soql) {
    if (String.isBlank(soql)) {
      throw new OI_ValidationException('A Tooling API query is required.');
    }
    return parsePage(
      get(
        '/services/data/' +
          API_VERSION +
          '/tooling/query/?q=' +
          EncodingUtil.urlEncode(soql, 'UTF-8')
      )
    );
  }

  /** Fetches the next page using the nextRecordsUrl of a previous page. */
  public virtual QueryPage nextPage(String nextRecordsUrl) {
    return parsePage(get(nextRecordsUrl));
  }

  /** Runs a Tooling query and follows nextRecordsUrl up to maxPages pages. */
  public List<Map<String, Object>> queryAll(String soql, Integer maxPages) {
    QueryPage page = queryPage(soql);
    List<Map<String, Object>> all = new List<Map<String, Object>>(page.records);
    Integer pages = 1;
    while (page.nextRecordsUrl != null && pages < maxPages) {
      page = nextPage(page.nextRecordsUrl);
      all.addAll(page.records);
      pages++;
    }
    return all;
  }

  /** REST GET relative to the org root (e.g. /services/data/v67.0/sobjects/); returns the raw body. */
  public virtual String get(String path) {
    HttpRequest request = new HttpRequest();
    request.setEndpoint(NAMED_CREDENTIAL + path);
    request.setMethod('GET');
    request.setTimeout(CALLOUT_TIMEOUT_MS);
    HttpResponse response;
    try {
      response = new Http().send(request);
    } catch (CalloutException e) {
      throw new OI_ServiceException(
        'The Salesforce API could not be reached: ' + e.getMessage()
      );
    }
    if (response.getStatusCode() != 200) {
      throw new OI_ServiceException(
        'The Salesforce API returned an error (status ' +
          response.getStatusCode() +
          '): ' +
          response.getBody().left(300)
      );
    }
    return response.getBody();
  }

  public static String describeGlobalPath() {
    return '/services/data/' + API_VERSION + '/sobjects/';
  }

  private QueryPage parsePage(String body) {
    QueryPage page = new QueryPage();
    Map<String, Object> parsed;
    try {
      parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
    } catch (Exception e) {
      throw new OI_ServiceException(
        'The Tooling API response could not be parsed.'
      );
    }
    Object raw = parsed.get('records');
    if (raw instanceof List<Object>) {
      for (Object r : (List<Object>) raw) {
        if (r instanceof Map<String, Object>) {
          page.records.add((Map<String, Object>) r);
        }
      }
    }
    Boolean done = parsed.get('done') == null
      ? true
      : (Boolean) parsed.get('done');
    Object next = parsed.get('nextRecordsUrl');
    page.nextRecordsUrl = (!done && next != null) ? String.valueOf(next) : null;
    return page;
  }
}
