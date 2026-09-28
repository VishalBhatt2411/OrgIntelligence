/**
 * Purpose: Query construction against OI_Org_Health_Finding__History — the platform's own
 *          native Field History Tracking object for OI_Org_Health_Finding__c (object-level
 *          enableHistory=true; Status__c, Due_Date__c, and Risk_Acceptance_Expiry__c carry
 *          trackHistory=true) — the finding drawer's "History" audit-trail panel (ADR-0027
 *          lifecycle extension). Prefers this native capability over a hand-rolled audit
 *          object, per CLAUDE.md's "prefer official Salesforce capabilities."
 * Responsibilities: Bulk, bounded reads only, scoped to one finding's Id.
 * Dependencies: OI_Org_Health_Finding__History (standard, platform-generated),
 *               OI_FindingHistoryRowDTO.
 * Limitations: History rows age out of the org after 18 months per platform limits — this
 *              Selector surfaces whatever the platform still retains, never fabricates earlier
 *              entries. Owner changes are tracked automatically by the platform once
 *              object-level history is enabled (no per-field trackHistory flag applies to the
 *              standard Owner field), so they appear here as Field = 'Owner' without any
 *              corresponding custom-field metadata declaration. A live-org reproduction
 *              (OI_OrgHealthFindingServiceTest) confirmed the platform does not guarantee a
 *              just-written history row is visible to a query in the SAME transaction that
 *              made the change — callers must not assume synchronous read-your-writes here.
 *              Returns OI_FindingHistoryRowDTO rather than the raw OI_Org_Health_Finding__History
 *              SObject — that type's fields cannot be set via a standard constructor or
 *              JSON.deserialize (both confirmed to fail), which made it impossible to build fake
 *              rows for a test. selectByFindingId is virtual solely so a test can extend this
 *              class with an in-memory fake (CodingStandards.md's DI-based-fake convention),
 *              exactly like OI_ToolingApiAdapter.query.
 */
public virtual with sharing class OI_OrgHealthFindingHistorySelector {
  private static final Integer ROW_LIMIT = 50;

  /** Bounded, most-recent-first history for one finding. */
  public virtual List<OI_FindingHistoryRowDTO> selectByFindingId(Id findingId) {
    if (findingId == null) {
      return new List<OI_FindingHistoryRowDTO>();
    }
    List<OI_FindingHistoryRowDTO> rows = new List<OI_FindingHistoryRowDTO>();
    for (OI_Org_Health_Finding__History historyRow : [
      SELECT Field, OldValue, NewValue, CreatedDate, CreatedBy.Name
      FROM OI_Org_Health_Finding__History
      WHERE ParentId = :findingId
      ORDER BY CreatedDate DESC
      LIMIT :ROW_LIMIT
    ]) {
      rows.add(
        new OI_FindingHistoryRowDTO(
          historyRow.Field,
          historyRow.OldValue,
          historyRow.NewValue,
          historyRow.CreatedDate,
          historyRow.CreatedBy?.Name
        )
      );
    }
    return rows;
  }
}
