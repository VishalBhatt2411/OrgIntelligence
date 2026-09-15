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
 *              OI_PermissionSetScanner already documents.
 */
public with sharing class OI_PermissionSetSelector {
  private static final Integer MAX_GRANT_ROWS = 5000;

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

  /** Object-level grants broad enough to matter for a security review: View All or Modify All Records on any object. */
  public List<ObjectPermissions> selectBroadObjectGrants(
    Set<Id> permissionSetIds
  ) {
    if (permissionSetIds == null || permissionSetIds.isEmpty()) {
      return new List<ObjectPermissions>();
    }
    return [
      SELECT ParentId, SobjectType
      FROM ObjectPermissions
      WHERE
        ParentId IN :permissionSetIds
        AND (PermissionsViewAllRecords = TRUE
        OR PermissionsModifyAllRecords = TRUE)
      LIMIT :MAX_GRANT_ROWS
    ];
  }
}
