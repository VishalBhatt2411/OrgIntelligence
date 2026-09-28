/**
 * Purpose: Query construction for OI_Graph_Node__c — the only class that writes SOQL
 *          against this object (CodingStandards.md §4).
 * Responsibilities: Bulk, key-set-shaped reads; centralizes the Is_Current__c = true
 *                    predicate (GraphEngine.md §13/§15/§21) so no caller can omit it by
 *                    accident. Returns sObjects/projections only, never a domain shape —
 *                    that mapping is OI_GraphRepository's job (GraphRepository.md §12).
 * Dependencies: OI_Graph_Node__c.
 * Limitations: Every method is bulk-shaped; there is no single-key overload that issues
 *              its own query (CodingStandards.md §4).
 */
public with sharing class OI_NodeSelector {
  private static final List<String> DETAIL_FIELDS = new List<String>{
    'Id',
    'Node_Key__c',
    'Node_Version_Key__c',
    'Version_Number__c',
    'Node_Type__c',
    'Label__c',
    'Secondary_Key__c',
    'Parent_Key__c',
    'Attributes_Json__c',
    'Checksum__c',
    'State__c',
    'Graph_Scope__c',
    'First_Seen_Run__c',
    'Last_Seen_Run__c',
    'Is_Current__c'
  };

  /**
   * Aggregate current node counts by Node_Type__c, restricted to the given type keys — a
   * single GROUP BY query, never full row loads. Backs Org Health's Org Overview KPI strip
   * (ADR-0026) via OI_GraphEngine.countCurrentNodesByType; mirrors
   * OI_EdgeSelector.countCurrentBySourceKeyGroupedByType's aggregate-not-full-row shape.
   * A type key with zero current nodes is simply absent from the result map, not a
   * zero entry — callers default missing keys to 0.
   */
  public Map<String, Integer> countCurrentByType(Set<String> typeKeys) {
    Map<String, Integer> counts = new Map<String, Integer>();
    if (typeKeys == null || typeKeys.isEmpty()) {
      return counts;
    }
    for (AggregateResult row : [
      SELECT Node_Type__c typeKey, COUNT(Id) total
      FROM OI_Graph_Node__c
      WHERE Node_Type__c IN :typeKeys AND Is_Current__c = TRUE
      GROUP BY Node_Type__c
    ]) {
      counts.put((String) row.get('typeKey'), (Integer) row.get('total'));
    }
    return counts;
  }

  /**
   * Bounded (ceiling-limited) current nodes of a type, key + label only — Metadata Health's
   * live Tier-2 object enumeration (ADR-0026 Phase 2). Deliberately NOT paginated: the
   * caller's ceiling IS the bound, and a result at exactly that size is reported honestly
   * via the caller's own coverage note, never silently completed with a second page —
   * Tier 2 by definition trades exhaustiveness for staying synchronous and bounded.
   */
  public List<OI_Graph_Node__c> selectCurrentByTypeBounded(
    String typeKey,
    Integer ceiling
  ) {
    Integer effectiveCeiling = ceiling == null || ceiling <= 0 ? 500 : ceiling;
    String query =
      'SELECT Node_Key__c, Label__c FROM OI_Graph_Node__c ' +
      'WHERE Node_Type__c = :typeKey AND Is_Current__c = true AND State__c = \'Active\' ' +
      'ORDER BY Node_Key__c ASC LIMIT :effectiveCeiling';
    return Database.query(query);
  }

  /**
   * Bulk lookup of just the real API name (Secondary_Key__c) for a key set — for callers that
   * need identity/classification facts, never the friendly Label__c (which for a custom object
   * or field can differ arbitrarily from its API name — see OI_MetadataClassificationService's
   * own doc comment on why that distinction matters). A key with no current version is simply
   * absent from the result.
   */
  public Map<String, String> selectSecondaryKeysByKeys(Set<String> nodeKeys) {
    Map<String, String> result = new Map<String, String>();
    if (nodeKeys == null || nodeKeys.isEmpty()) {
      return result;
    }
    for (OI_Graph_Node__c node : [
      SELECT Node_Key__c, Secondary_Key__c
      FROM OI_Graph_Node__c
      WHERE Node_Key__c IN :nodeKeys AND Is_Current__c = TRUE
    ]) {
      result.put(node.Node_Key__c, node.Secondary_Key__c);
    }
    return result;
  }

  /**
   * Bulk lookup of current Field nodes belonging to any object in a bounded parent-key set —
   * Metadata Health's per-object CUSTOM field count (a Standard object must only be penalized
   * for fields this org's admins added, never Salesforce's own — ProductSpecs.md). Reads
   * Parent_Key__c directly (already denormalized onto every Field node at scan time, ADR-0018)
   * rather than joining through HAS_FIELD edges, so this is one query, not an edge-then-node
   * two-hop. Capped at a hard row ceiling independent of the caller's object ceiling, since one
   * object can carry far more fields than there are objects in the scan — truncation here is
   * reported by the caller alongside its own coverage note, never silently absorbed.
   */
  public List<OI_Graph_Node__c> selectCurrentFieldNodesByParentKeys(
    Set<String> parentKeys,
    String fieldNodeTypeKey,
    Integer rowCeiling
  ) {
    if (
      parentKeys == null ||
      parentKeys.isEmpty() ||
      String.isBlank(fieldNodeTypeKey)
    ) {
      return new List<OI_Graph_Node__c>();
    }
    Integer effectiveCeiling = rowCeiling == null ||
      rowCeiling <= 0
      ? 20000
      : rowCeiling;
    String query =
      'SELECT Parent_Key__c, Secondary_Key__c FROM OI_Graph_Node__c ' +
      'WHERE Parent_Key__c IN :parentKeys AND Node_Type__c = :fieldNodeTypeKey AND Is_Current__c = true ' +
      'LIMIT :effectiveCeiling';
    return Database.query(query);
  }

  /**
   * Bulk lookup of the current version row for each key in the set. Keys with no
   * current version are simply absent from the result — not an error
   * (GraphRepository.md §2).
   */
  public List<OI_Graph_Node__c> selectCurrentByKeys(Set<String> nodeKeys) {
    if (nodeKeys == null || nodeKeys.isEmpty()) {
      return new List<OI_Graph_Node__c>();
    }
    String query =
      'SELECT ' +
      String.join(DETAIL_FIELDS, ', ') +
      ' FROM OI_Graph_Node__c WHERE Node_Key__c IN :nodeKeys AND Is_Current__c = true';
    return Database.query(query);
  }

  /**
   * Minimal node lookup by label/secondaryKey prefix (Sprint 10) — a deliberately small
   * substitute for the full, unbuilt SearchEngine.md epic (no SOSL multi-domain ranking,
   * no record search, no provider abstraction), sufficient only for oiSearchBar to find
   * a starting node for the graph. LIKE, not SOSL, since this is a simple prefix match
   * over two fields on one object, not the multi-object relevance search SearchEngine.md
   * specifies for a future sprint.
   */
  public List<OI_Graph_Node__c> selectCurrentByLabelOrSecondaryKeyPrefix(
    String queryTerm,
    Integer maxResults
  ) {
    String likeTerm = String.escapeSingleQuotes(queryTerm) + '%';
    Integer effectiveMax = maxResults == null ? 20 : maxResults;
    String query =
      'SELECT ' +
      String.join(DETAIL_FIELDS, ', ') +
      ' FROM OI_Graph_Node__c WHERE Is_Current__c = true AND (Label__c LIKE :likeTerm OR Secondary_Key__c LIKE :likeTerm) ' +
      'ORDER BY Label__c ASC LIMIT :effectiveMax';
    return Database.query(query);
  }

  /**
   * Substring (contains) match on label/secondaryKey — the search a drill-down needs, kept
   * deliberately separate from the prefix method above rather than replacing it.
   *
   * Two different jobs, two different matching rules: `oiSearchBar` looks for a STARTING node
   * by name, where a prefix match is both faster and more predictable as the user types.
   * Searching *within* an already-scoped result set is the opposite expectation — typing
   * "Owner" must find "Account Owner", which a prefix match would miss. Changing the shared
   * prefix method to satisfy this would silently alter global search behaviour, so this is
   * additive.
   *
   * Honest cost note: a leading wildcard cannot use an index, so this is a scan bounded by
   * maxResults. Acceptable because it only ever runs on an explicit user search inside one
   * drill-down (never during graph rendering or scanning), and the caller reports the outcome
   * as a filtered result rather than a complete one.
   */
  public List<OI_Graph_Node__c> selectCurrentByLabelOrSecondaryKeyContains(
    String queryTerm,
    Integer maxResults
  ) {
    if (String.isBlank(queryTerm)) {
      return new List<OI_Graph_Node__c>();
    }
    String likeTerm = '%' + String.escapeSingleQuotes(queryTerm.trim()) + '%';
    Integer effectiveMax = maxResults == null ? 200 : maxResults;
    String query =
      'SELECT ' +
      String.join(DETAIL_FIELDS, ', ') +
      ' FROM OI_Graph_Node__c WHERE Is_Current__c = true AND (Label__c LIKE :likeTerm OR Secondary_Key__c LIKE :likeTerm) ' +
      'ORDER BY Label__c ASC LIMIT :effectiveMax';
    return Database.query(query);
  }

  /**
   * Bounded, alphabetical enumeration of current nodes — optionally scoped to a single type —
   * for oiSearchBar's click-to-browse panel (Sprint 10 follow-up: a suggestion list shown the
   * moment the search box gets focus, before the user has typed anything, alongside the
   * existing prefix-match search). ORDER BY Label__c ASC so the panel reads as a predictable
   * A-Z list; bounded by maxResults exactly like every other Tier-2-style enumeration in this
   * codebase (selectCurrentByTypeBounded above) — a result at exactly that size is a truncated
   * browse, never a promise this is every node of that type.
   */
  public List<OI_Graph_Node__c> selectCurrentBrowse(
    String typeKey,
    Integer maxResults
  ) {
    Integer effectiveMax = maxResults == null ||
      maxResults <= 0
      ? 20
      : maxResults;
    String query =
      'SELECT ' +
      String.join(DETAIL_FIELDS, ', ') +
      ' FROM OI_Graph_Node__c WHERE Is_Current__c = true AND State__c = \'Active\'' +
      (String.isNotBlank(typeKey) ? ' AND Node_Type__c = :typeKey' : '') +
      ' ORDER BY Label__c ASC LIMIT :effectiveMax';
    return Database.query(query);
  }

  /**
   * Keyset-paginated, key-only projection of every currently-Active key for a given
   * typeKey — the enumeration retire-detection needs (GraphRepository.md §2, §9, §12).
   * Deliberately field-minimal: no Attributes_Json__c, no Label__c.
   */
  public List<OI_Graph_Node__c> selectCurrentKeysByType(
    String typeKey,
    String cursorVersionKey,
    Integer pageSize
  ) {
    Integer effectivePageSize = pageSize == null ? 200 : pageSize;
    String query =
      'SELECT Id, Node_Key__c, Node_Version_Key__c FROM OI_Graph_Node__c ' +
      'WHERE Node_Type__c = :typeKey AND Is_Current__c = true AND State__c = \'Active\'';
    if (String.isNotBlank(cursorVersionKey)) {
      query += ' AND Node_Version_Key__c > :cursorVersionKey';
    }
    query += ' ORDER BY Node_Version_Key__c ASC LIMIT :effectivePageSize';
    return Database.query(query);
  }
}
