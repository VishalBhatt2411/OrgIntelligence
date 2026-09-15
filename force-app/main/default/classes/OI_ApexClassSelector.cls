/**
 * Purpose: Query construction against the standard ApexClass object for Code Health
 *          (ADR-0026 Phase 3).
 * Responsibilities: Bulk, bounded reads only — never a per-class round-trip. A Selector
 *                    reading a standard object directly, bypassing the Graph Engine entirely:
 *                    the deliberate, documented exception the codebase already carves out for
 *                    a service with no graph-read need (OI_NodeConnectionsService's own
 *                    precedent), applied here to a standard object rather than
 *                    OI_Graph_Node__c/OI_Graph_Edge__c.
 * Dependencies: ApexClass (standard).
 * Limitations: Deliberately does NOT surface test coverage — ApexCodeCoverageAggregate and
 *              ApexOrgWideCoverage are Tooling-API-only objects (not valid types for inline
 *              Apex SOQL at all, confirmed at deploy time), so reading them requires the
 *              still-unbuilt OI_ToolingApiAdapter (Backlog MS-2) — the same adapter Impact
 *              Analysis's own coverageCaveat already names as the blocker for Flow/Validation
 *              Rule coverage. Code Health's KPI/score formula is scoped to what ApexClass
 *              alone can answer (dependency fan-in/out, cycles, API version) until that
 *              adapter exists, rather than attempting a Tooling API callout under this phase's
 *              scope.
 */
public with sharing class OI_ApexClassSelector {
  /** Bounded (ceiling-limited) Apex classes, ordered by name — Code Health's live Tier-2 class enumeration. */
  public List<ApexClass> selectClassesBounded(Integer ceiling) {
    Integer effectiveCeiling = ceiling == null || ceiling <= 0 ? 500 : ceiling;
    return [
      SELECT Id, Name, NamespacePrefix, ApiVersion
      FROM ApexClass
      ORDER BY Name ASC
      LIMIT :effectiveCeiling
    ];
  }
}
