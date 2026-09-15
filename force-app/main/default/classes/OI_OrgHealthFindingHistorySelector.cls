/**
 * Purpose: Query construction against OI_Org_Health_Finding__History — the platform's own
 *          native Field History Tracking object for OI_Org_Health_Finding__c (object-level
 *          enableHistory=true; Status__c, Due_Date__c, and Risk_Acceptance_Expiry__c carry
 *          trackHistory=true) — the finding drawer's "History" audit-trail panel (ADR-0027
 *          lifecycle extension). Prefers this native capability over a hand-rolled audit
 *          object, per CLAUDE.md's "prefer official Salesforce capabilities."
 * Responsibilities: Bulk, bounded reads only, scoped to one finding's Id.
 * Dependencies: OI_Org_Health_Finding__History (standard, platform-generated).
 * Limitations: History rows age out of the org after 18 months per platform limits — this
 *              Selector surfaces whatever the platform still retains, never fabricates earlier
 *              entries. Owner changes are tracked automatically by the platform once
 *              object-level history is enabled (no per-field trackHistory flag applies to the
 *              standard Owner field), so they appear here as Field = 'Owner' without any
 *              corresponding custom-field metadata declaration.
 */
public with sharing class OI_OrgHealthFindingHistorySelector {
  private static final Integer ROW_LIMIT = 50;

  /** Bounded, most-recent-first history for one finding. */
  public List<OI_Org_Health_Finding__History> selectByFindingId(Id findingId) {
    if (findingId == null) {
      return new List<OI_Org_Health_Finding__History>();
    }
    return [
      SELECT Field, OldValue, NewValue, CreatedDate, CreatedBy.Name
      FROM OI_Org_Health_Finding__History
      WHERE ParentId = :findingId
      ORDER BY CreatedDate DESC
      LIMIT :ROW_LIMIT
    ];
  }
}
