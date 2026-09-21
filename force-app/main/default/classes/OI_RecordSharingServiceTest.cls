@isTest
private class OI_RecordSharingServiceTest {
  /** A fixed, obviously-fake OWD result so every test in this class can assert the DTO is genuinely wired through, never asserting this org's real OWD (CLAUDE.md §Metadata Assumptions). */
  private static OI_RecordSharingService serviceWithFakeOrgWideDefault() {
    return new OI_RecordSharingService(
      new OI_ObjectSharingSettingsService(
        new FakeToolingApiAdapter(
          new List<Map<String, Object>>{
            new Map<String, Object>{
              'InternalSharingModel' => 'ReadWrite',
              'ExternalSharingModel' => 'Private'
            }
          }
        )
      )
    );
  }

  private class FakeToolingApiAdapter extends OI_ToolingApiAdapter {
    private final List<Map<String, Object>> records;

    private FakeToolingApiAdapter(List<Map<String, Object>> records) {
      this.records = records;
    }

    public override List<Map<String, Object>> query(String soql) {
      return records;
    }
  }

  /**
   * Salesforce inserts an implicit "Owner" share row whenever org-wide default does not already
   * grant Edit to everyone — reliable for Opportunity specifically because a manual insert's
   * allowed access levels are themselves OWD-dependent, which a portable unit test must not
   * assume (CLAUDE.md §Metadata Assumptions). Using the owner-record's own guaranteed row
   * sidesteps needing to know or match this org's OWD at all.
   */
  @isTest
  static void testOpportunityReturnsSupportsSharingTrueWithOwnerRowAndResolvedUserLabel() {
    Opportunity opp = new Opportunity(
      Name = 'Owned Deal',
      OwnerId = UserInfo.getUserId(),
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30)
    );
    insert opp;

    OI_RecordSharingDTO sharing = serviceWithFakeOrgWideDefault()
      .getRecordSharing('Opportunity', opp.Id);

    System.assertEquals(
      true,
      sharing.supportsSharing,
      'Opportunity has its own OpportunityShare table.'
    );
    System.assert(
      !sharing.shareRows.isEmpty(),
      'The owner must be represented by at least its own implicit share row.'
    );
    OI_RecordSharingDTO.ShareRow ownerRow;
    for (OI_RecordSharingDTO.ShareRow row : sharing.shareRows) {
      if (row.rowCause == 'Owner') {
        ownerRow = row;
      }
    }
    System.assertNotEquals(
      null,
      ownerRow,
      'An implicit Owner row must be present.'
    );
    System.assertEquals(
      String.valueOf(UserInfo.getUserId()),
      ownerRow.userOrGroupId
    );
    System.assertEquals(
      UserInfo.getName(),
      ownerRow.userOrGroupLabel,
      'The User principal must resolve to its real Name, never a raw Id.'
    );
    System.assertEquals(
      null,
      sharing.coverageNote,
      'A non-empty share list needs no "nothing found" coverage note.'
    );
    System.assertEquals(false, sharing.truncated);
    System.assertNotEquals(
      null,
      sharing.orgWideDefault,
      'The object\'s Org-Wide Default must be embedded alongside the record\'s own share rows.'
    );
    System.assertEquals(true, sharing.orgWideDefault.supported);
    System.assertEquals(
      'ReadWrite',
      sharing.orgWideDefault.internalSharingModel
    );
  }

  /**
   * A Custom Metadata Type record never has a share table on any org, by fixed platform design
   * (CMDT is packaged/deployed configuration, not sharable record data) — unlike Contact/User/
   * Campaign, whose availability or sharing model an org admin can change. This package's own
   * OI_Node_Type_Descriptor__mdt is used since at least one row always exists in this org. This
   * is the honest "not applicable" path, distinct from a true empty result.
   */
  @isTest
  static void testObjectWithNoShareTableReportsSupportsSharingFalse() {
    OI_Node_Type_Descriptor__mdt descriptor = [
      SELECT Id
      FROM OI_Node_Type_Descriptor__mdt
      LIMIT 1
    ];

    OI_RecordSharingDTO sharing = serviceWithFakeOrgWideDefault()
      .getRecordSharing('OI_Node_Type_Descriptor__mdt', descriptor.Id);

    System.assertEquals(false, sharing.supportsSharing);
    System.assertEquals(0, sharing.shareRows.size());
    System.assert(
      String.isNotBlank(sharing.coverageNote),
      'Must say WHY there are no rows — "not applicable", not a silent empty list.'
    );
    System.assertNotEquals(
      null,
      sharing.orgWideDefault,
      'The coverage note references "the object\'s org-wide default" — its actual value must be embedded here too, not just the object\'s own missing share table.'
    );
  }

  /**
   * Without an approval process actually defined for Account in this org, Approval.isLocked
   * must correctly report false — this asserts the field is wired through faithfully rather
   * than fabricated as true. The locked-record path itself needs an org-specific approval
   * process to exercise and is not testable generically here, same documented boundary as
   * every other org-configuration-dependent behavior in this package.
   */
  @isTest
  static void testUnlockedRecordReportsNotLockedWithNoPendingApprovalDetail() {
    Account acct = new Account(Name = 'Unlocked Co');
    insert acct;

    OI_RecordSharingDTO sharing = serviceWithFakeOrgWideDefault()
      .getRecordSharing('Account', acct.Id);

    System.assertEquals(false, sharing.isLockedByApproval);
    System.assertEquals(null, sharing.pendingApprovalDetail);
  }

  @isTest
  static void testInvalidRecordIdForObjectIsRejected() {
    try {
      serviceWithFakeOrgWideDefault()
        .getRecordSharing('Account', '003000000000000AAA');
      System.assert(
        false,
        'A Contact Id passed for Account must be rejected rather than silently queried.'
      );
    } catch (OI_ValidationException expected) {
      System.assert(
        expected.getMessage().containsIgnoreCase('Account'),
        'The error must name the mismatch. Got: ' + expected.getMessage()
      );
    }
  }

  /**
   * Group shares (rather than manual User shares) sidestep the OWD-dependent access-level
   * ceiling entirely for the row VOLUME being tested here: 'Read' is always valid to grant on
   * an object whose OWD is already Public Read Only or more open, which covers this org's
   * current Opportunity OWD without the test needing to know or assume its exact value beyond
   * "at least Read" (CLAUDE.md §Metadata Assumptions) — the point of this test is exercising the
   * truncation boundary, not proving a specific access level.
   */
  @isTest
  static void testMoreThanMaxShareRowsReportsTruncated() {
    Opportunity opp = new Opportunity(
      Name = 'Widely Shared Deal',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30)
    );
    insert opp;

    Integer rowCountBeyondMax = 205;
    List<Group> groups = new List<Group>();
    for (Integer i = 0; i < rowCountBeyondMax; i++) {
      groups.add(
        new Group(Name = 'OI Sharing Test Group ' + i, Type = 'Regular')
      );
    }
    insert groups;

    List<OpportunityShare> shares = new List<OpportunityShare>();
    for (Group g : groups) {
      shares.add(
        new OpportunityShare(
          OpportunityId = opp.Id,
          UserOrGroupId = g.Id,
          OpportunityAccessLevel = 'Read',
          RowCause = Schema.OpportunityShare.RowCause.Manual
        )
      );
    }
    insert shares;

    OI_RecordSharingDTO sharing = serviceWithFakeOrgWideDefault()
      .getRecordSharing('Opportunity', opp.Id);

    System.assertEquals(
      true,
      sharing.truncated,
      'More than MAX_SHARE_ROWS rows exist and must be reported as truncated, not silently capped.'
    );
    System.assertEquals(200, sharing.shareRows.size());
  }
}
