/**
 * Purpose: Query construction against the standard PermissionSet / ObjectPermissions /
 *          PermissionSetAssignment objects for Security Health (ADR-0026 Phase 4).
 * Responsibilities: Bulk, bounded reads only — never a per-row round-trip. A Selector reading
 *                    standard objects directly, bypassing the Graph Engine entirely: the
 *                    deliberate, documented exception the codebase already carves out for a
 *                    service with no graph-read need (OI_NodeConnectionsService's own
 *                    precedent, already extended once to OI_ApexClassSelector).
 * Dependencies: PermissionSet, ObjectPermissions, PermissionSetAssignment (all standard).
 * Limitations: Deliberately INCLUDES profile-owned permission set shadow rows
 *              (IsOwnedByProfile = true) — the opposite of OI_PermissionSetScanner's graph
 *              scanner, which excludes them to avoid a synthetic, unmanageable graph node.
 *              Here the shadow row is exactly the evidence Security Health needs: it is how a
 *              Profile's own elevated system permissions and object grants become visible
 *              without a dedicated Profile scanner (Backlog MS-7). Field-level grants
 *              (FieldPermissions) are out of scope for the same governor-limit reasons
 *              OI_PermissionSetScanner already documents. Broad object grants are surfaced as
 *              two purpose-built, inherently bounded queries (countBroadObjectGrantsByPermissionSetIds,
 *              selectSensitiveObjectGrantPermissionSetIds) rather than one row-level
 *              "SELECT ... LIMIT N" fetch of every matching ObjectPermissions row: this org alone
 *              has 11,000+ rows matching "View All or Modify All on any object" across all
 *              Permission Sets, which a flat, unordered LIMIT silently and non-deterministically
 *              truncated (confirmed live) — a real caller only ever needs a per-Permission-Set
 *              count and a per-Permission-Set sensitive-object flag, both of which an aggregate
 *              or narrowly-filtered query can answer exactly, with no row cap needed at all.
 */
public with sharing class OI_PermissionSetSelector {
  /** Bounded (ceiling-limited) Permission Sets AND profile shadow rows, ordered by label. */
  public List<PermissionSet> selectPermissionSetsBounded(Integer ceiling) {
    Integer effectiveCeiling = ceiling == null || ceiling <= 0 ? 500 : ceiling;
    return [
      SELECT
        Id,
        Name,
        Label,
        IsOwnedByProfile,
        IsCustom,
        PermissionsModifyAllData,
        PermissionsViewAllData,
        PermissionsAuthorApex,
        PermissionsManageUsers,
        PermissionsCustomizeApplication,
        PermissionsManageSharing,
        PermissionsResetPasswords
      FROM PermissionSet
      ORDER BY Label ASC
      LIMIT :effectiveCeiling
    ];
  }

  /** One assignee count per Permission Set Id — a bounded aggregate, never a per-row count. */
  public Map<Id, Integer> countAssigneesByPermissionSetIds(
    Set<Id> permissionSetIds
  ) {
    Map<Id, Integer> countsByPermissionSetId = new Map<Id, Integer>();
    if (permissionSetIds == null || permissionSetIds.isEmpty()) {
      return countsByPermissionSetId;
    }
    for (AggregateResult result : [
      SELECT PermissionSetId targetId, COUNT(Id) assigneeCount
      FROM PermissionSetAssignment
      WHERE PermissionSetId IN :permissionSetIds
      GROUP BY PermissionSetId
    ]) {
      countsByPermissionSetId.put(
        (Id) result.get('targetId'),
        (Integer) result.get('assigneeCount')
      );
    }
    return countsByPermissionSetId;
  }

  /**
   * One broad-grant (View All or Modify All Records, any object) count per Permission Set Id —
   * an aggregate, exactly like countAssigneesByPermissionSetIds, so the result set is bounded by
   * permissionSetIds.size() rows regardless of how many underlying ObjectPermissions rows exist.
   */
  public Map<Id, Integer> countBroadObjectGrantsByPermissionSetIds(
    Set<Id> permissionSetIds
  ) {
    Map<Id, Integer> countsByPermissionSetId = new Map<Id, Integer>();
    if (permissionSetIds == null || permissionSetIds.isEmpty()) {
      return countsByPermissionSetId;
    }
    for (AggregateResult result : [
      SELECT ParentId targetId, COUNT(SobjectType) grantCount
      FROM ObjectPermissions
      WHERE
        ParentId IN :permissionSetIds
        AND (PermissionsViewAllRecords = TRUE
        OR PermissionsModifyAllRecords = TRUE)
      GROUP BY ParentId
    ]) {
      countsByPermissionSetId.put(
        (Id) result.get('targetId'),
        (Integer) result.get('grantCount')
      );
    }
    return countsByPermissionSetId;
  }

  /**
   * Permission Set Ids that hold a broad (View All or Modify All Records) grant on any of the
   * given sensitive object API names. Narrowly filtered by both ParentId and SobjectType, so the
   * result is bounded by permissionSetIds.size() * sensitiveObjectApiNames.size() — small enough
   * (a handful of curated sensitive objects, ADR-0026 Phase 4) that no row cap is needed.
   */
  public Set<Id> selectSensitiveObjectGrantPermissionSetIds(
    Set<Id> permissionSetIds,
    Set<String> sensitiveObjectApiNames
  ) {
    Set<Id> permissionSetIdsWithSensitiveGrant = new Set<Id>();
    if (
      permissionSetIds == null ||
      permissionSetIds.isEmpty() ||
      sensitiveObjectApiNames == null ||
      sensitiveObjectApiNames.isEmpty()
    ) {
      return permissionSetIdsWithSensitiveGrant;
    }
    for (ObjectPermissions grant : [
      SELECT ParentId
      FROM ObjectPermissions
      WHERE
        ParentId IN :permissionSetIds
        AND SobjectType IN :sensitiveObjectApiNames
        AND (PermissionsViewAllRecords = TRUE
        OR PermissionsModifyAllRecords = TRUE)
    ]) {
      permissionSetIdsWithSensitiveGrant.add(grant.ParentId);
    }
    return permissionSetIdsWithSensitiveGrant;
  }
}
