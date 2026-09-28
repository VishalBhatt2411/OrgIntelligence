/**
 * Purpose: The single choke point for Metadata API SOAP callouts (Architecture.md's
 *          scanner/service rule: "Calls the relevant Adapter [...] — never a raw HTTP callout
 *          [...] from the scanner itself"), mirroring OI_ToolingApiAdapter's REST equivalent.
 *          First caller: OI_SharingRuleScanner, which needs Sharing Rules — a metadata type with
 *          no Tooling API or Apex-queryable standard-object equivalent at all.
 * Responsibilities: Issue one Metadata API readMetadata SOAP call per invocation and return each
 *                    requested component's fields as a plain, generic Map<String, Object> — never
 *                    interprets what a "SharingRules" or any other type's fields mean, which stays
 *                    entirely the calling Scanner's concern (same "stay generic" discipline
 *                    OI_ToolingApiAdapter and OI_GraphEngine already hold, ADR-0013). Repeated
 *                    child elements (e.g. a SharingRules component's several sharingCriteriaRules)
 *                    are returned as a List<Object>; nested elements as a nested Map; a leaf
 *                    element as its raw String text — the same un-opinionated shape
 *                    JSON.deserializeUntyped gives OI_ToolingApiAdapter's callers, adapted to XML.
 * Dependencies: The `OI_Self_Callout` Named Credential (same one OI_ToolingApiAdapter uses),
 *               with `allowMergeFieldsInBody` now enabled — see this class's Limitations for why.
 *
 * Why a hand-built SOAP envelope, not a WSDL2Apex-generated MetadataService.cls: the generated
 * stub from Salesforce's Metadata WSDL is many thousands of lines covering every metadata type
 * this platform will never touch, and still requires the exact same SessionHeader/merge-field
 * wiring this Adapter already does by hand. A single hand-built readMetadata envelope keeps this
 * Adapter the same order of size and review surface as OI_ToolingApiAdapter (CLAUDE.md's
 * "prefer simple architecture that scales over complicated architecture that appears
 * enterprise"), and every current/foreseeable caller needs exactly one operation.
 *
 * Why the OAuth token goes in the SOAP body, not a Bearer header: confirmed directly against
 * Salesforce's own "Using OAuth 2.0 with the SOAP API" guidance — classic SOAP APIs (Enterprise,
 * Partner, Metadata) authenticate only via a <SessionHeader><sessionId> element in the SOAP body;
 * a bare Authorization: Bearer header is rejected with INVALID_SESSION_ID even with a valid token.
 * The supported mechanism for a Named-Credential-mediated OAuth token is the
 * `{!$Credential.OAuthToken}` merge field (confirmed via Salesforce's "Merge Fields for Apex
 * Callouts That Use Named Credentials" doc), substituted into the request body at callout time —
 * Apex code never sees the raw token, preserving the same credential-hiding guarantee
 * OI_ToolingApiAdapter's header-based auth already has. This requires
 * `allowMergeFieldsInBody=true` on `OI_Self_Callout` (flipped alongside this class; see
 * OI_Self_Callout.namedCredential-meta.xml), NOT a new Named Credential.
 *
 * Limitations: Documented, permanent (Salesforce's own doc states this verbatim): "When you use
 *              these merge fields in SOAP API calls, OAuth access tokens aren't refreshed." A
 *              long-idle session can make a call fail with INVALID_SESSION_ID even though the
 *              underlying OAuth grant is still valid — this Adapter does not special-case that
 *              fault; it surfaces as any other OI_ServiceException, and every current caller
 *              (OI_SharingRuleScanner) already treats ANY exception from an Adapter call as
 *              OI_ScanCoverage.degraded rather than a hard failure, so a rescan recovers it
 *              without special handling here. `readMetadata` enforces the Metadata API's own hard
 *              platform limit of 10 fullNames per call (confirmed against the official
 *              readMetadata reference) by throwing OI_ValidationException rather than silently
 *              truncating — the caller must chunk, exactly as OI_ToolingApiAdapter's doc comment
 *              places pagination responsibility on the calling service. `readMetadata` is
 *              `virtual` solely so a test can extend this class with an in-memory fake
 *              (CodingStandards.md's DI-based-fake convention); this class's OWN test instead
 *              exercises the real HTTP path via Test.setMock/HttpCalloutMock, per
 *              CodingStandards.md's Adapter-test rule. Bounded to metadata types whose
 *              readMetadata response this Adapter's generic node-to-map walk can represent (any
 *              type — the walk makes no type-specific assumption); it does NOT implement
 *              createMetadata/updateMetadata/deleteMetadata or any other Metadata API operation,
 *              since no caller needs them yet.
 */
public virtual with sharing class OI_MetadataApiAdapter {
  private static final String NAMED_CREDENTIAL = 'OI_Self_Callout';
  private static final String METADATA_API_VERSION = '67.0';
  private static final Integer CALLOUT_TIMEOUT_MS = 20000;
  private static final Integer MAX_FULL_NAMES_PER_CALL = 10;
  private static final String SOAP_ENVELOPE_NS = 'http://schemas.xmlsoap.org/soap/envelope/';
  private static final String METADATA_NS = 'http://soap.sforce.com/2006/04/metadata';

  public virtual List<Map<String, Object>> readMetadata(
    String metadataType,
    List<String> fullNames
  ) {
    if (String.isBlank(metadataType)) {
      throw new OI_ValidationException('A Metadata API type name is required.');
    }
    if (fullNames == null || fullNames.isEmpty()) {
      throw new OI_ValidationException('At least one full name is required.');
    }
    if (fullNames.size() > MAX_FULL_NAMES_PER_CALL) {
      throw new OI_ValidationException(
        'readMetadata accepts at most ' +
          MAX_FULL_NAMES_PER_CALL +
          ' full names per call (a Metadata API platform limit) — the caller must chunk.'
      );
    }

    HttpRequest request = new HttpRequest();
    request.setEndpoint(
      'callout:' + NAMED_CREDENTIAL + '/services/Soap/m/' + METADATA_API_VERSION
    );
    request.setMethod('POST');
    request.setTimeout(CALLOUT_TIMEOUT_MS);
    request.setHeader('Content-Type', 'text/xml; charset=UTF-8');
    request.setHeader('SOAPAction', '""');
    request.setBody(buildReadMetadataEnvelope(metadataType, fullNames));

    HttpResponse response;
    try {
      response = new Http().send(request);
    } catch (CalloutException e) {
      throw new OI_ServiceException('The Metadata API could not be reached.');
    }

    if (response.getStatusCode() != 200) {
      throw new OI_ServiceException(
        'The Metadata API returned an error: ' +
        faultMessageOf(response.getBody())
      );
    }

    return parseReadMetadataResults(response.getBody());
  }

  private String buildReadMetadataEnvelope(
    String metadataType,
    List<String> fullNames
  ) {
    List<String> fullNameElements = new List<String>();
    for (String fullName : fullNames) {
      fullNameElements.add(
        '<met:fullNames>' + fullName.escapeXml() + '</met:fullNames>'
      );
    }
    return '<?xml version="1.0" encoding="UTF-8"?>' +
      '<soapenv:Envelope xmlns:soapenv="' +
      SOAP_ENVELOPE_NS +
      '" xmlns:met="' +
      METADATA_NS +
      '">' +
      '<soapenv:Header>' +
      '<met:SessionHeader><met:sessionId>{!$Credential.OAuthToken}</met:sessionId></met:SessionHeader>' +
      '</soapenv:Header>' +
      '<soapenv:Body>' +
      '<met:readMetadata>' +
      '<met:type>' +
      metadataType.escapeXml() +
      '</met:type>' +
      String.join(fullNameElements, '') +
      '</met:readMetadata>' +
      '</soapenv:Body>' +
      '</soapenv:Envelope>';
  }

  /** Isolated so a malformed/unexpected body reports the same sanitized failure as any other Adapter error, rather than leaking a raw XML-parsing exception (mirrors OI_ToolingApiAdapter.parseRecords). */
  private List<Map<String, Object>> parseReadMetadataResults(
    String responseBody
  ) {
    try {
      Dom.Document document = new Dom.Document();
      document.load(responseBody);
      Dom.XmlNode responseNode = findDescendant(
        document.getRootElement(),
        'readMetadataResponse'
      );
      List<Map<String, Object>> results = new List<Map<String, Object>>();
      if (responseNode == null) {
        return results;
      }
      for (Dom.XmlNode child : responseNode.getChildElements()) {
        if (child.getName() == 'result') {
          results.add(nodeToMap(child));
        }
      }
      return results;
    } catch (Exception e) {
      throw new OI_ServiceException(
        'The Metadata API response could not be parsed.'
      );
    }
  }

  /** Best-effort SOAP Fault message extraction for the error text on a non-200 response; never throws itself, since a fault we cannot parse must still surface as SOME actionable message rather than aborting error reporting. */
  private String faultMessageOf(String responseBody) {
    try {
      Dom.Document document = new Dom.Document();
      document.load(responseBody);
      Dom.XmlNode faultString = findDescendant(
        document.getRootElement(),
        'faultstring'
      );
      if (faultString != null && String.isNotBlank(faultString.getText())) {
        return faultString.getText();
      }
    } catch (Exception e) {
      // Falls through to the generic message below — a fault body this Adapter cannot parse is still reported, just without the specific reason.
    }
    return 'the response could not be interpreted.';
  }

  private Dom.XmlNode findDescendant(Dom.XmlNode node, String name) {
    for (Dom.XmlNode child : node.getChildElements()) {
      if (child.getName() == name) {
        return child;
      }
      Dom.XmlNode nested = findDescendant(child, name);
      if (nested != null) {
        return nested;
      }
    }
    return null;
  }

  /**
   * Generic element-to-Map walk (the XML analogue of JSON.deserializeUntyped): a leaf element
   * becomes its raw text, a parent element becomes a nested Map, and a repeated element name
   * becomes a List — the only three shapes a caller ever needs to branch on, regardless of which
   * metadata type it requested.
   */
  private Map<String, Object> nodeToMap(Dom.XmlNode node) {
    Map<String, List<Dom.XmlNode>> childrenByName = new Map<String, List<Dom.XmlNode>>();
    for (Dom.XmlNode child : node.getChildElements()) {
      String name = child.getName();
      if (!childrenByName.containsKey(name)) {
        childrenByName.put(name, new List<Dom.XmlNode>());
      }
      childrenByName.get(name).add(child);
    }

    Map<String, Object> result = new Map<String, Object>();
    for (String name : childrenByName.keySet()) {
      List<Dom.XmlNode> children = childrenByName.get(name);
      if (children.size() > 1) {
        List<Object> values = new List<Object>();
        for (Dom.XmlNode child : children) {
          values.add(nodeValue(child));
        }
        result.put(name, values);
      } else {
        result.put(name, nodeValue(children[0]));
      }
    }
    return result;
  }

  private Object nodeValue(Dom.XmlNode node) {
    if (!node.getChildElements().isEmpty()) {
      return nodeToMap(node);
    }
    String text = node.getText();
    return String.isBlank(text) ? null : text;
  }
}
