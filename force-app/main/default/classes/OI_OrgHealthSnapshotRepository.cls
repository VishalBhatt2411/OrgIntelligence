/**
 * Purpose: Bulk persistence and lookup of OI_Org_Health_Snapshot__c — the only class that
 *          writes or queries this object (CodingStandards.md §1's Repository role), matching
 *          the exact self-contained-Repository-per-object pattern OI_ImpactCacheRepository/
 *          OI_LogRepository already establish.
 * Responsibilities: getLatest(sectionKey) — the most recently computed snapshot row for a
 *                    section, or null if none exists yet; put(...) — always an insert, never
 *                    an update, since the object is append-only by design (ADR-0026 §0.2).
 * Dependencies: OI_Org_Health_Snapshot__c.
 * Limitations: without sharing — this is an application-internal, Tier-3 computation-result
 *              table (ADR-0026), the same posture OI_ImpactCacheRepository already takes
 *              against OI_Impact_Cache__c. No purge/retention mechanism yet — every recompute
 *              adds one more row per section; a scheduled cleanup job is a reasonable future
 *              addition once real-world row growth is observed, not built speculatively now.
 */
public without sharing class OI_OrgHealthSnapshotRepository {
  public OI_Org_Health_Snapshot__c getLatest(String sectionKey) {
    if (String.isBlank(sectionKey)) {
      return null;
    }
    List<OI_Org_Health_Snapshot__c> rows = [
      SELECT
        Id,
        Section_Key__c,
        Compute_Run_Id__c,
        Score__c,
        Result_Json__c,
        Coverage_Note__c,
        Computed_At__c,
        Row_Count_Examined__c,
        Is_Truncated__c,
        Triggered_By__c
      FROM OI_Org_Health_Snapshot__c
      WHERE Section_Key__c = :sectionKey
      ORDER BY Computed_At__c DESC
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  public void put(
    String sectionKey,
    String computeRunId,
    Decimal score,
    String resultJson,
    String coverageNote,
    Datetime computedAt,
    Integer rowCountExamined,
    Boolean isTruncated,
    Id triggeredById
  ) {
    insert new OI_Org_Health_Snapshot__c(
      Section_Key__c = sectionKey,
      Compute_Run_Id__c = computeRunId,
      Score__c = score,
      Result_Json__c = resultJson,
      Coverage_Note__c = coverageNote,
      Computed_At__c = computedAt,
      Row_Count_Examined__c = rowCountExamined,
      Is_Truncated__c = isTruncated,
      Triggered_By__c = triggeredById
    );
  }
}
