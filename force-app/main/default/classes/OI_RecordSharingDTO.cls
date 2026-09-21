/**
 * Purpose: The @AuraEnabled wire shape for one record's live sharing state — the Record
 *          Intelligence Panel's "Sharing" section (distinct from the Object panel's Security
 *          section, which reports schema-level sharing settings, not per-record grants).
 * Responsibilities: Carry the record's own share rows (who has access and why), whether it is
 *                    currently locked by an in-flight approval process, and an honest coverage
 *                    note for objects that have no share table to read at all. Pure data; all
 *                    derivation lives in OI_RecordSharingService.
 * Dependencies: None.
 *
 * Why this is never cacheable data (see OI_RecordHierarchyController.getRecordSharing): unlike
 * the metadata graph, a record's sharing can change from one click to the next (a share is
 * added, an approval completes) — presenting a cached answer here would be actively misleading
 * in exactly the way OI_NodeIntelligenceDTO's own doc comment warns against for metadata scans.
 *
 * Why this is a distinct DTO from OI_NodeIntelligenceDTO rather than a fourth category on it:
 * per-record sharing cannot be pre-scanned into the persisted graph at all (unbounded
 * cardinality — see OI_RecordSharingService's own Limitations), so it structurally cannot carry
 * a lastScannedAt/coverageNote pair that means the same thing as the metadata categories' do.
 * Conflating the two would misrepresent a live read as scanned intelligence.
 *
 * Why orgWideDefault is embedded here rather than requiring a second panel round-trip: the
 * record's own "who has access and why" reads incomplete without the schema-level default it
 * sits on top of (a share row list of zero means something different under Private than under
 * Public Read/Write), and the "no independent share table" coverageNote below explicitly refers
 * to "the object's org-wide default" — leaving a reader to switch to Object mode just to see the
 * value that sentence is talking about would be a broken cross-reference, not a real boundary.
 * The value itself is still resolved by OI_ObjectSharingSettingsService, never duplicated.
 */
public class OI_RecordSharingDTO {
  /** One row from the record's own <Object>Share table, or a synthesized row for an approval lock — never a guess at who "should" have access, only what is actually recorded. */
  public class ShareRow {
    @AuraEnabled
    public String userOrGroupId;
    @AuraEnabled
    public String userOrGroupLabel;
    @AuraEnabled
    public String accessLevel;
    /** Manual, Rule, Owner, Team, ImplicitChild, etc. — the share table's own RowCause value, never reworded, since an admin needs the exact platform vocabulary to act on it. */
    @AuraEnabled
    public String rowCause;

    public ShareRow(
      String userOrGroupId,
      String userOrGroupLabel,
      String accessLevel,
      String rowCause
    ) {
      this.userOrGroupId = userOrGroupId;
      this.userOrGroupLabel = userOrGroupLabel;
      this.accessLevel = accessLevel;
      this.rowCause = rowCause;
    }
  }

  /** False for an object with no <Object>Share table at all (e.g. most "Controlled by Parent" child objects) — the honest reason a zero here is not "no sharing", but "not applicable", which reads completely differently to an admin. */
  @AuraEnabled
  public Boolean supportsSharing;
  /** Explains a false supportsSharing, or a true one with zero rows — never a silent empty list. */
  @AuraEnabled
  public String coverageNote;
  @AuraEnabled
  public List<ShareRow> shareRows;
  /** True when more share rows exist than were returned — surfaced rather than silently truncated. */
  @AuraEnabled
  public Boolean truncated;
  /** Approval.isLocked(recordId) — a simple, exact platform fact, never inferred from ProcessInstance rows (those are read best-effort, only to add step context, and their absence never changes this flag). */
  @AuraEnabled
  public Boolean isLockedByApproval;
  /** Best-effort context for a lock (e.g. "Pending — submitted by Jane Doe") — null whenever ProcessInstance is not readable in this context, without affecting isLockedByApproval's own accuracy. */
  @AuraEnabled
  public String pendingApprovalDetail;
  /** The object's own Org-Wide Default — the exact same OI_ObjectSharingSettingsDTO the Object panel's Sharing Settings section renders, embedded here rather than re-fetched by the client. See this class's own doc comment for why. */
  @AuraEnabled
  public OI_ObjectSharingSettingsDTO orgWideDefault;

  public OI_RecordSharingDTO(
    Boolean supportsSharing,
    String coverageNote,
    List<ShareRow> shareRows,
    Boolean truncated,
    Boolean isLockedByApproval,
    String pendingApprovalDetail,
    OI_ObjectSharingSettingsDTO orgWideDefault
  ) {
    this.supportsSharing = supportsSharing;
    this.coverageNote = coverageNote;
    this.shareRows = shareRows == null ? new List<ShareRow>() : shareRows;
    this.truncated = truncated == null ? false : truncated;
    this.isLockedByApproval = isLockedByApproval == null
      ? false
      : isLockedByApproval;
    this.pendingApprovalDetail = pendingApprovalDetail;
    this.orgWideDefault = orgWideDefault;
  }
}
