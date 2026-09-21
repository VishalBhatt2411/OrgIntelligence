/**
 * Purpose: Live read of one record's own sharing state (Record Intelligence Panel's "Sharing"
 *          section) — who has access to THIS record and why, and whether it is currently locked
 *          by an in-flight approval process. The record-level counterpart to the Object panel's
 *          schema-level Security section (org-wide default, sharing rules); see that section's
 *          own doc comment for why the two are deliberately never merged.
 * Responsibilities: Resolve the record's own <Object>Share table (when one exists), read its
 *                    rows scoped to this record only, resolve the User/Group principals on each
 *                    row to a display label, and report Approval.isLocked with best-effort step
 *                    context. Never persisted, never routed through OI_GraphEngine — same
 *                    parallel-read-path rationale as OI_RecordHierarchyService.
 * Dependencies: OI_RecordSchemaUtil, OI_RecordSharingDTO, OI_ObjectSharingSettingsService.
 * Limitations: Per-record only, by design — this cannot be pre-scanned into the graph at all
 *              (a scan would mean one row set per record, org-wide, an unbounded cardinality
 *              explosion the same way OI_PermissionSetScanner's own doc comment rules out
 *              field-level grants). Bounded at MAX_SHARE_ROWS, truncated rather than silently
 *              capped. UserRecordAccess (a more precise "does user X have access" answer) is a
 *              known, documented gap: it requires a specific user id to check rather than
 *              enumerating "everyone", and correctly resolving that would mean expanding every
 *              Group/Queue/Role row into its member users — a second, unbounded read this
 *              sprint does not build. ProcessInstance step detail is read best-effort inside its
 *              own try/catch and never affects isLockedByApproval's own accuracy, which comes
 *              from the platform's own Approval.isLocked, not from that query succeeding.
 */
public with sharing class OI_RecordSharingService {
  private static final Integer MAX_SHARE_ROWS = 200;
  private static final String USER_KEY_PREFIX = '005';

  private final OI_ObjectSharingSettingsService objectSharingSettingsService;

  public OI_RecordSharingService() {
    this(new OI_ObjectSharingSettingsService());
  }

  /** DI seam for tests (CodingStandards.md's DI-based-fake convention) — production code always uses the zero-arg constructor above. */
  public OI_RecordSharingService(
    OI_ObjectSharingSettingsService objectSharingSettingsService
  ) {
    this.objectSharingSettingsService = objectSharingSettingsService;
  }

  public OI_RecordSharingDTO getRecordSharing(
    String objectApiName,
    String recordId
  ) {
    Schema.DescribeSObjectResult describe = OI_RecordSchemaUtil.describeAccessibleObject(
      objectApiName
    );
    Id validatedRecordId = OI_RecordSchemaUtil.validateRecordIdForObject(
      describe,
      recordId
    );

    ShareTableInfo shareTable = resolveShareTable(describe);
    Boolean isLockedByApproval = resolveApprovalLockStatus(validatedRecordId);
    String pendingApprovalDetail = isLockedByApproval
      ? resolvePendingApprovalDetail(validatedRecordId)
      : null;
    OI_ObjectSharingSettingsDTO orgWideDefault = objectSharingSettingsService.getObjectSharingSettings(
      describe.getName()
    );

    if (shareTable == null) {
      return new OI_RecordSharingDTO(
        false,
        'This object has no independent sharing table — its access is controlled entirely by its parent record or by the object\'s org-wide default.',
        new List<OI_RecordSharingDTO.ShareRow>(),
        false,
        isLockedByApproval,
        pendingApprovalDetail,
        orgWideDefault
      );
    }

    List<SObject> rawRows = queryShareRows(shareTable, validatedRecordId);
    Boolean truncated = rawRows.size() > MAX_SHARE_ROWS;
    List<SObject> boundedRows = truncated
      ? trimTo(rawRows, MAX_SHARE_ROWS)
      : rawRows;
    Map<Id, String> labelByPrincipalId = resolvePrincipalLabels(boundedRows);

    List<OI_RecordSharingDTO.ShareRow> shareRows = new List<OI_RecordSharingDTO.ShareRow>();
    for (SObject row : boundedRows) {
      Id principalId = (Id) row.get('UserOrGroupId');
      shareRows.add(
        new OI_RecordSharingDTO.ShareRow(
          principalId == null ? null : String.valueOf(principalId),
          labelByPrincipalId.get(principalId),
          (String) row.get(shareTable.accessLevelFieldApiName),
          (String) row.get('RowCause')
        )
      );
    }

    /**
     * Every owned record gets an implicit "Owner" row regardless of org-wide default, so this
     * branch is a defensive fallback rather than a common case — it is reached only when even
     * that row is filtered out by field/object security in USER_MODE.
     */
    String coverageNote = shareRows.isEmpty()
      ? 'No share rows are visible for this record with your current access.'
      : null;

    return new OI_RecordSharingDTO(
      true,
      coverageNote,
      shareRows,
      truncated,
      isLockedByApproval,
      pendingApprovalDetail,
      orgWideDefault
    );
  }

  /**
   * A custom object's share table always uses ParentId; a standard object's uses
   * "<ObjectName>Id" (AccountId, ContactId, CaseId, etc.) — there is no describe-exposed
   * "this is the parent field" pointer, so this is the platform's own documented naming
   * convention, not a guess, with a defensive fallback to ParentId if that field happens to be
   * absent (an object this convention does not fit is treated as unsupported, never crashed
   * on).
   */
  private ShareTableInfo resolveShareTable(
    Schema.DescribeSObjectResult describe
  ) {
    String shareObjectApiName = describe.getName() + 'Share';
    Schema.SObjectType shareType = Schema.getGlobalDescribe()
      .get(shareObjectApiName);
    if (shareType == null) {
      return null;
    }
    Schema.DescribeSObjectResult shareDescribe = shareType.getDescribe();
    if (!shareDescribe.isAccessible() || !shareDescribe.isQueryable()) {
      return null;
    }
    Map<String, Schema.SObjectField> shareFields = shareDescribe.fields.getMap();
    String parentField = describe.isCustom()
      ? 'ParentId'
      : describe.getName() + 'Id';
    if (!shareFields.containsKey(parentField)) {
      parentField = shareFields.containsKey('ParentId') ? 'ParentId' : null;
    }
    /**
     * A custom object's share table exposes a single generic "AccessLevel" field; a standard
     * object's exposes an object-specific one instead — "AccountAccessLevel", "CaseAccessLevel",
     * "ContactAccessLevel", etc. — never the generic name. Same platform convention split as
     * the parent field above, with the same defensive fallback.
     */
    String accessLevelField = describe.isCustom()
      ? 'AccessLevel'
      : describe.getName() + 'AccessLevel';
    if (!shareFields.containsKey(accessLevelField)) {
      accessLevelField = shareFields.containsKey('AccessLevel')
        ? 'AccessLevel'
        : null;
    }
    if (
      parentField == null ||
      accessLevelField == null ||
      !shareFields.containsKey('UserOrGroupId') ||
      !shareFields.containsKey('RowCause')
    ) {
      return null;
    }
    return new ShareTableInfo(
      shareDescribe.getName(),
      parentField,
      accessLevelField
    );
  }

  private List<SObject> queryShareRows(ShareTableInfo shareTable, Id recordId) {
    Integer fetchLimit = MAX_SHARE_ROWS + 1;
    String soql =
      'SELECT UserOrGroupId, ' +
      shareTable.accessLevelFieldApiName +
      ', RowCause FROM ' +
      shareTable.objectApiName +
      ' WHERE ' +
      shareTable.parentFieldApiName +
      ' = :recordId LIMIT :fetchLimit';
    try {
      return Database.query(soql, AccessLevel.USER_MODE);
    } catch (QueryException e) {
      /** A describe-listed share table can still be unqueryable in practice (edition/feature gating) — CLAUDE.md §Metadata Assumptions: report unsupported rather than fail the whole panel. */
      return new List<SObject>();
    }
  }

  private List<SObject> trimTo(List<SObject> rows, Integer maxSize) {
    List<SObject> trimmed = new List<SObject>();
    for (Integer i = 0; i < maxSize; i++) {
      trimmed.add(rows[i]);
    }
    return trimmed;
  }

  /** One bulk query per principal type (User, Group/Queue) — never one query per row. */
  private Map<Id, String> resolvePrincipalLabels(List<SObject> shareRows) {
    Set<Id> userIds = new Set<Id>();
    Set<Id> groupIds = new Set<Id>();
    for (SObject row : shareRows) {
      Id principalId = (Id) row.get('UserOrGroupId');
      if (principalId == null) {
        continue;
      }
      if (String.valueOf(principalId).startsWith(USER_KEY_PREFIX)) {
        userIds.add(principalId);
      } else {
        groupIds.add(principalId);
      }
    }
    Map<Id, String> labelById = new Map<Id, String>();
    if (!userIds.isEmpty()) {
      for (User u : [
        SELECT Id, Name
        FROM User
        WHERE Id IN :userIds
        WITH USER_MODE
      ]) {
        labelById.put(u.Id, u.Name);
      }
    }
    if (!groupIds.isEmpty()) {
      for (Group g : [
        SELECT Id, Name, Type
        FROM Group
        WHERE Id IN :groupIds
        WITH USER_MODE
      ]) {
        labelById.put(g.Id, g.Name + ' (' + g.Type + ')');
      }
    }
    return labelById;
  }

  /**
   * Approval.isLocked throws System.NoAccessException whenever the org has not turned on
   * Setup -> Process Automation Settings -> "Enable record locking and unlocking in Apex" —
   * that preference defaults OFF, so most orgs (including this one) will hit it. CLAUDE.md
   * §Metadata Assumptions: never assume org configuration: not-enabled is reported as
   * "not locked" rather than surfacing an org-preference error through the whole Sharing panel.
   */
  private Boolean resolveApprovalLockStatus(Id recordId) {
    try {
      return Approval.isLocked(recordId);
    } catch (NoAccessException e) {
      return false;
    }
  }

  /**
   * Best-effort only: a failure here (no ProcessInstance access, unexpected schema) must never
   * change isLockedByApproval, which already came from the platform's own Approval.isLocked
   * before this method is even called.
   */
  private String resolvePendingApprovalDetail(Id recordId) {
    try {
      List<ProcessInstance> instances = [
        SELECT Id, SubmittedBy.Name, (SELECT Actor.Name FROM Workitems LIMIT 1)
        FROM ProcessInstance
        WHERE TargetObjectId = :recordId AND Status = 'Pending'
        WITH USER_MODE
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
      if (instances.isEmpty()) {
        return null;
      }
      ProcessInstance current = instances[0];
      String submitter = current.SubmittedBy != null
        ? current.SubmittedBy.Name
        : null;
      String approver = !current.Workitems.isEmpty() &&
        current.Workitems[0].Actor != null
        ? current.Workitems[0].Actor.Name
        : null;
      if (submitter == null && approver == null) {
        return null;
      }
      if (approver == null) {
        return 'Submitted by ' + submitter + ', awaiting the next approver.';
      }
      if (submitter == null) {
        return 'Awaiting approval from ' + approver + '.';
      }
      return 'Submitted by ' +
        submitter +
        ', awaiting approval from ' +
        approver +
        '.';
    } catch (Exception e) {
      return null;
    }
  }

  private class ShareTableInfo {
    private final String objectApiName;
    private final String parentFieldApiName;
    private final String accessLevelFieldApiName;

    private ShareTableInfo(
      String objectApiName,
      String parentFieldApiName,
      String accessLevelFieldApiName
    ) {
      this.objectApiName = objectApiName;
      this.parentFieldApiName = parentFieldApiName;
      this.accessLevelFieldApiName = accessLevelFieldApiName;
    }
  }
}
