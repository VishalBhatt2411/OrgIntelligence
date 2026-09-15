/**
 * Purpose: Verifies OI_OrgHealthFindingRepository's fingerprint stability, lifecycle-field
 *          preservation across re-scans, auto-resolve-on-disappearance, and reopen-on-
 *          recurrence behavior — the correctness properties the whole unified finding model
 *          depends on (ADR-0027) — plus the Remediation Management workspace's filtered/sorted/
 *          paginated queue query, export, and org-wide summary aggregates (ADR-0027 lifecycle
 *          extension).
 */
@isTest
private class OI_OrgHealthFindingRepositoryTest {
  /** Creating the second-owner fixture user (a setup-object DML: User + PermissionSetAssignment) must happen in its own @TestSetup transaction — doing it inline inside a test method that has already inserted/updated a non-setup object (OI_Org_Health_Finding__c) trips Apex's MIXED_DML_OPERATION restriction. */
  @TestSetup
  static void setupSecondTestUser() {
    createSecondTestUser();
  }

  @isTest
  static void testComputeFingerprintIsStableAndDistinguishesEveryComponent() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    String base = repo.computeFingerprint(
      'MetadataHealth',
      'MetadataHealth.HighFieldCount',
      'objA'
    );

    System.assertEquals(
      base,
      repo.computeFingerprint(
        'MetadataHealth',
        'MetadataHealth.HighFieldCount',
        'objA'
      ),
      'The same triple must always hash to the same fingerprint.'
    );
    System.assertNotEquals(
      base,
      repo.computeFingerprint(
        'SecurityHealth',
        'MetadataHealth.HighFieldCount',
        'objA'
      ),
      'A different section must change the fingerprint.'
    );
    System.assertNotEquals(
      base,
      repo.computeFingerprint(
        'MetadataHealth',
        'MetadataHealth.HighDegree',
        'objA'
      ),
      'A different rule must change the fingerprint.'
    );
    System.assertNotEquals(
      base,
      repo.computeFingerprint(
        'MetadataHealth',
        'MetadataHealth.HighFieldCount',
        'objB'
      ),
      'A different component must change the fingerprint.'
    );
  }

  @isTest
  static void testUpsertCandidatesInsertsNewFindingAsOpenWithFirstAndLastDetectedSet() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    OI_OrgHealthFindingCandidate candidate = buildCandidate('objA', 'Critical');

    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{ candidate },
      'run-1',
      Datetime.now()
    );

    OI_Org_Health_Finding__c record = [
      SELECT Status__c, First_Detected__c, Last_Detected__c, Severity__c
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c = 'objA'
    ];
    System.assertEquals(
      'Open',
      record.Status__c,
      'A brand-new finding must start Open.'
    );
    System.assertEquals(
      record.First_Detected__c,
      record.Last_Detected__c,
      'On first detection, first and last detected must be identical.'
    );
    System.assertEquals('Critical', record.Severity__c);
  }

  @isTest
  static void testUpsertCandidatesRefreshesEvidenceButNeverOverwritesLifecycleFields() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objA', 'Warning')
      },
      'run-1',
      Datetime.now().addDays(-1)
    );

    OI_Org_Health_Finding__c existing = [
      SELECT Id
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c = 'objA'
    ];
    update new OI_Org_Health_Finding__c(
      Id = existing.Id,
      Status__c = 'Acknowledged',
      Notes__c = 'Investigating with the platform team.',
      OwnerId = UserInfo.getUserId()
    );

    OI_OrgHealthFindingCandidate rescanned = buildCandidate('objA', 'Critical');
    rescanned.evidence = 'Now 900 fields detected.';
    Datetime secondRunTimestamp = Datetime.now();
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{ rescanned },
      'run-2',
      secondRunTimestamp
    );

    OI_Org_Health_Finding__c afterRescan = [
      SELECT
        Status__c,
        Notes__c,
        OwnerId,
        Severity__c,
        Evidence__c,
        Last_Detected__c
      FROM OI_Org_Health_Finding__c
      WHERE Id = :existing.Id
    ];
    System.assertEquals(
      'Acknowledged',
      afterRescan.Status__c,
      'A re-scan that still detects the same condition must never reset an administrator-set status.'
    );
    System.assertEquals(
      'Investigating with the platform team.',
      afterRescan.Notes__c,
      'Administrator notes must survive a re-scan untouched.'
    );
    System.assertEquals(
      UserInfo.getUserId(),
      afterRescan.OwnerId,
      'An administrator-assigned owner must survive a re-scan untouched.'
    );
    System.assertEquals(
      'Critical',
      afterRescan.Severity__c,
      'The severity must still refresh to reflect the latest evidence.'
    );
    System.assertEquals(
      'Now 900 fields detected.',
      afterRescan.Evidence__c,
      'The evidence text must still refresh.'
    );
    System.assertEquals(
      secondRunTimestamp,
      afterRescan.Last_Detected__c,
      'Last_Detected__c must advance on every re-scan that still finds the condition.'
    );
  }

  @isTest
  static void testResolveMissingFindingsResolvesOpenFindingsNoLongerDetected() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objA', 'Warning')
      },
      'run-1',
      Datetime.now()
    );

    Integer resolvedCount = repo.resolveMissingFindings(
      'MetadataHealth',
      new Set<String>(),
      'run-2',
      Datetime.now()
    );

    System.assertEquals(1, resolvedCount);
    OI_Org_Health_Finding__c record = [
      SELECT Status__c, Resolution_Evidence__c
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c = 'objA'
    ];
    System.assertEquals('Resolved', record.Status__c);
    System.assert(
      record.Resolution_Evidence__c.contains('run-2'),
      'The auto-resolve note must name the run that stopped detecting the condition.'
    );
  }

  @isTest
  static void testResolveMissingFindingsLeavesAlreadyTerminalFindingsAlone() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objA', 'Warning')
      },
      'run-1',
      Datetime.now()
    );
    OI_Org_Health_Finding__c existing = [
      SELECT Id
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c = 'objA'
    ];
    update new OI_Org_Health_Finding__c(
      Id = existing.Id,
      Status__c = 'False Positive'
    );

    Integer resolvedCount = repo.resolveMissingFindings(
      'MetadataHealth',
      new Set<String>(),
      'run-2',
      Datetime.now()
    );

    System.assertEquals(
      0,
      resolvedCount,
      'A False Positive finding must never be auto-resolved — it is already a terminal, administrator-made judgment.'
    );
  }

  @isTest
  static void testRecurrenceReopensAResolvedFindingButNotARiskAcceptedOne() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objResolved', 'Warning'),
        buildCandidate('objAccepted', 'Warning')
      },
      'run-1',
      Datetime.now()
    );
    OI_Org_Health_Finding__c resolvedRecord = [
      SELECT Id
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c = 'objResolved'
    ];
    OI_Org_Health_Finding__c acceptedRecord = [
      SELECT Id
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c = 'objAccepted'
    ];
    update new List<OI_Org_Health_Finding__c>{
      new OI_Org_Health_Finding__c(
        Id = resolvedRecord.Id,
        Status__c = 'Resolved'
      ),
      new OI_Org_Health_Finding__c(
        Id = acceptedRecord.Id,
        Status__c = 'Risk Accepted'
      )
    };

    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objResolved', 'Warning'),
        buildCandidate('objAccepted', 'Warning')
      },
      'run-2',
      Datetime.now()
    );

    Map<String, String> statusByComponent = new Map<String, String>();
    for (OI_Org_Health_Finding__c record : [
      SELECT Component_Key__c, Status__c
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c IN ('objResolved', 'objAccepted')
    ]) {
      statusByComponent.put(record.Component_Key__c, record.Status__c);
    }
    System.assertEquals(
      'Open',
      statusByComponent.get('objResolved'),
      'A Resolved finding whose condition recurs must reopen — the claim "this is gone" was false.'
    );
    System.assertEquals(
      'Risk Accepted',
      statusByComponent.get('objAccepted'),
      'A Risk Accepted finding is a judgment about the condition itself, not a claim it disappeared — recurrence must never override that judgment.'
    );
  }

  @isTest
  static void testResolveMissingFindingsStampsResolvedDate() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objA', 'Warning')
      },
      'run-1',
      Datetime.now()
    );

    Datetime resolveTimestamp = Datetime.now();
    repo.resolveMissingFindings(
      'MetadataHealth',
      new Set<String>(),
      'run-2',
      resolveTimestamp
    );

    OI_Org_Health_Finding__c record = [
      SELECT Resolved_Date__c
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c = 'objA'
    ];
    System.assertEquals(
      resolveTimestamp,
      record.Resolved_Date__c,
      'Auto-resolve must stamp Resolved_Date__c with the run that stopped detecting the condition.'
    );
  }

  @isTest
  static void testRecurrenceReopeningAResolvedFindingClearsResolvedDate() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objResolved', 'Warning')
      },
      'run-1',
      Datetime.now()
    );
    OI_Org_Health_Finding__c existing = [
      SELECT Id
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c = 'objResolved'
    ];
    update new OI_Org_Health_Finding__c(
      Id = existing.Id,
      Status__c = 'Resolved',
      Resolved_Date__c = Datetime.now().addDays(-1)
    );

    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objResolved', 'Warning')
      },
      'run-2',
      Datetime.now()
    );

    OI_Org_Health_Finding__c afterReopen = [
      SELECT Status__c, Resolved_Date__c
      FROM OI_Org_Health_Finding__c
      WHERE Id = :existing.Id
    ];
    System.assertEquals('Open', afterReopen.Status__c);
    System.assertEquals(
      null,
      afterReopen.Resolved_Date__c,
      'A reopened finding is no longer resolved, so its Resolved_Date__c must be cleared, not left stale.'
    );
  }

  @isTest
  static void testUpdateStatusStampsResolvedDateWhenExplicitlyResolvedAndClearsItWhenReopened() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objA', 'Warning')
      },
      'run-1',
      Datetime.now()
    );
    OI_Org_Health_Finding__c existing = [
      SELECT Id
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c = 'objA'
    ];

    repo.updateStatus(
      existing.Id,
      'Resolved',
      null,
      null,
      null,
      null,
      null,
      null
    );
    OI_Org_Health_Finding__c afterResolve = [
      SELECT Resolved_Date__c
      FROM OI_Org_Health_Finding__c
      WHERE Id = :existing.Id
    ];
    System.assertNotEquals(
      null,
      afterResolve.Resolved_Date__c,
      'An administrator explicitly resolving a finding must stamp Resolved_Date__c.'
    );

    repo.updateStatus(existing.Id, 'Open', null, null, null, null, null, null);
    OI_Org_Health_Finding__c afterReopen = [
      SELECT Resolved_Date__c
      FROM OI_Org_Health_Finding__c
      WHERE Id = :existing.Id
    ];
    System.assertEquals(
      null,
      afterReopen.Resolved_Date__c,
      'Moving a finding away from Resolved must clear Resolved_Date__c so it never falsely claims a current resolution.'
    );
  }

  @isTest
  static void testUpdateStatusAppliesRiskAcceptanceExpiryAndFalsePositiveJustification() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objA', 'Warning')
      },
      'run-1',
      Datetime.now()
    );
    OI_Org_Health_Finding__c existing = [
      SELECT Id
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c = 'objA'
    ];

    repo.updateStatus(
      existing.Id,
      'Risk Accepted',
      null,
      null,
      null,
      null,
      Date.today().addMonths(6),
      null
    );
    repo.updateStatus(
      existing.Id,
      'False Positive',
      null,
      null,
      null,
      null,
      null,
      'Confirmed as expected platform behavior.'
    );

    OI_Org_Health_Finding__c afterUpdate = [
      SELECT Risk_Acceptance_Expiry__c, False_Positive_Justification__c
      FROM OI_Org_Health_Finding__c
      WHERE Id = :existing.Id
    ];
    System.assertEquals(
      Date.today().addMonths(6),
      afterUpdate.Risk_Acceptance_Expiry__c
    );
    System.assertEquals(
      'Confirmed as expected platform behavior.',
      afterUpdate.False_Positive_Justification__c
    );
  }

  @isTest
  static void testGetRelatedByComponentKeyExcludesTheFindingItselfAndOtherComponents() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    OI_OrgHealthFindingCandidate sameComponentOtherRule = buildCandidate(
      'objA',
      'Critical'
    );
    sameComponentOtherRule.ruleId = 'MetadataHealth.HighDegree';
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objA', 'Warning'),
        sameComponentOtherRule,
        buildCandidate('objB', 'Warning')
      },
      'run-1',
      Datetime.now()
    );
    OI_Org_Health_Finding__c primary = [
      SELECT Id
      FROM OI_Org_Health_Finding__c
      WHERE
        Component_Key__c = 'objA'
        AND Rule_Id__c = 'MetadataHealth.HighFieldCount'
    ];

    List<OI_Org_Health_Finding__c> related = repo.getRelatedByComponentKey(
      'objA',
      primary.Id
    );

    System.assertEquals(
      1,
      related.size(),
      'Only the other rule\'s finding on the SAME component must come back — never the finding itself, never a different component.'
    );
    System.assertEquals('MetadataHealth.HighDegree', related[0].Rule_Id__c);
  }

  @isTest
  static void testUpdateStatusOnlyTouchesFieldsExplicitlyProvided() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objA', 'Warning')
      },
      'run-1',
      Datetime.now()
    );
    OI_Org_Health_Finding__c existing = [
      SELECT Id
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c = 'objA'
    ];
    update new OI_Org_Health_Finding__c(
      Id = existing.Id,
      Notes__c = 'Original note.'
    );

    repo.updateStatus(
      existing.Id,
      'In Progress',
      null,
      Date.today().addDays(7),
      null,
      null,
      null,
      null
    );

    OI_Org_Health_Finding__c afterUpdate = [
      SELECT Status__c, Notes__c, Due_Date__c
      FROM OI_Org_Health_Finding__c
      WHERE Id = :existing.Id
    ];
    System.assertEquals('In Progress', afterUpdate.Status__c);
    System.assertEquals(Date.today().addDays(7), afterUpdate.Due_Date__c);
    System.assertEquals(
      'Original note.',
      afterUpdate.Notes__c,
      'A null notes parameter must never clobber the existing note.'
    );
  }

  @isTest
  static void testGetBySectionKeyReturnsOnlyThatSectionsFindings() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    OI_OrgHealthFindingCandidate other = buildCandidate(
      'objSecurity',
      'Critical'
    );
    other.sectionKey = 'SecurityHealth';
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objA', 'Warning'),
        other
      },
      'run-1',
      Datetime.now()
    );

    List<OI_Org_Health_Finding__c> results = repo.getBySectionKey(
      'MetadataHealth'
    );

    System.assertEquals(1, results.size());
    System.assertEquals('objA', results[0].Component_Key__c);
  }

  @isTest
  static void testGetFindingsByFilterFiltersBySectionSeverityStatusAndOwner() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    OI_OrgHealthFindingCandidate securityCandidate = buildCandidate(
      'objSecurity',
      'Critical'
    );
    securityCandidate.sectionKey = 'SecurityHealth';
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objA', 'Warning'),
        securityCandidate
      },
      'run-1',
      Datetime.now()
    );
    /** A brand-new finding defaults OwnerId to its creator (the running test user) — reassigning to a second, genuinely different user is required to prove the owner filter actually narrows rather than trivially matching everything the test itself created. That second user is created in @TestSetup (see setupSecondTestUser), not here, so its User/PermissionSetAssignment DML never shares a transaction with this method's own OI_Org_Health_Finding__c DML. */
    OI_Org_Health_Finding__c securityRecord = [
      SELECT Id
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c = 'objSecurity'
    ];
    Id secondOwnerId = [
      SELECT Id
      FROM User
      WHERE LastName LIKE 'SecondOwner%'
      LIMIT 1
    ]
    .Id;
    update new OI_Org_Health_Finding__c(
      Id = securityRecord.Id,
      OwnerId = secondOwnerId
    );

    OI_RemediationFilterDTO sectionFilter = new OI_RemediationFilterDTO();
    sectionFilter.sectionKeys = new List<String>{ 'SecurityHealth' };
    System.assertEquals(
      1,
      repo.getFindingsByFilter(sectionFilter).size(),
      'Section filter must return only that section\'s findings.'
    );

    OI_RemediationFilterDTO severityFilter = new OI_RemediationFilterDTO();
    severityFilter.severityKeys = new List<String>{ 'Critical' };
    System.assertEquals(
      1,
      repo.getFindingsByFilter(severityFilter).size(),
      'Severity filter must return only Critical findings.'
    );

    OI_RemediationFilterDTO statusFilter = new OI_RemediationFilterDTO();
    statusFilter.statuses = new List<String>{ 'Open' };
    System.assertEquals(
      2,
      repo.getFindingsByFilter(statusFilter).size(),
      'Both fixtures start Open.'
    );

    OI_RemediationFilterDTO ownerFilter = new OI_RemediationFilterDTO();
    ownerFilter.ownerId = secondOwnerId;
    System.assertEquals(
      1,
      repo.getFindingsByFilter(ownerFilter).size(),
      'Owner filter must return only the finding explicitly assigned to that user.'
    );
  }

  @isTest
  static void testGetFindingsByFilterSearchTextMatchesLiterallyNotAsAWildcard() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    OI_OrgHealthFindingCandidate percentCandidate = buildCandidate(
      'objPercent',
      'Warning'
    );
    percentCandidate.title = '50% Complete Rollout';
    OI_OrgHealthFindingCandidate decoyCandidate = buildCandidate(
      'objDecoy',
      'Warning'
    );
    decoyCandidate.title = '50X Complete Rollout';
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        percentCandidate,
        decoyCandidate
      },
      'run-1',
      Datetime.now()
    );

    OI_RemediationFilterDTO filter = new OI_RemediationFilterDTO();
    filter.searchText = '50%';
    List<OI_Org_Health_Finding__c> results = repo.getFindingsByFilter(filter);

    System.assertEquals(
      1,
      results.size(),
      'A literal "%" in the search text must not act as a SOQL wildcard matching every title.'
    );
    System.assertEquals('objPercent', results[0].Component_Key__c);
  }

  /** Salesforce's TRANSFER_REQUIRES_READ rule checks the new owner's own access, independent of the running user's mode — a plain Standard User with no permission set assigned cannot become a finding's owner at all, so this fixture must carry OI_Viewer (read access to OI_Org_Health_Finding__c) before any test reassigns ownership to it. */
  private static User createSecondTestUser() {
    Profile standardProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    String uniqueSuffix = String.valueOf(Crypto.getRandomInteger()).right(8);
    User u = new User(
      FirstName = 'OI Repo Test',
      LastName = 'SecondOwner' + uniqueSuffix,
      Email = 'oi.repo.test.' + uniqueSuffix + '@example.invalid',
      Username = 'oi.repo.test.' + uniqueSuffix + '@example.invalid',
      Alias = 'oirt' + uniqueSuffix.left(3),
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = standardProfile.Id
    );
    insert u;
    PermissionSet viewerPermSet = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'OI_Viewer'
      LIMIT 1
    ];
    insert new PermissionSetAssignment(
      AssigneeId = u.Id,
      PermissionSetId = viewerPermSet.Id
    );
    return u;
  }

  @isTest
  static void testGetFindingsByFilterDefaultSortIsWorstSeverityFirst() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objGood', 'Good'),
        buildCandidate('objCritical', 'Critical'),
        buildCandidate('objWarning', 'Warning')
      },
      'run-1',
      Datetime.now()
    );

    List<OI_Org_Health_Finding__c> results = repo.getFindingsByFilter(
      new OI_RemediationFilterDTO()
    );

    System.assertEquals(3, results.size());
    System.assertEquals(
      'objCritical',
      results[0].Component_Key__c,
      'Default sort must be worst-first via Severity_Rank__c — a plain alphabetical Severity__c sort would incorrectly place Good before Warning.'
    );
    System.assertEquals('objWarning', results[1].Component_Key__c);
    System.assertEquals('objGood', results[2].Component_Key__c);
  }

  @isTest
  static void testGetFindingsByFilterPaginatesCorrectly() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    List<OI_OrgHealthFindingCandidate> candidates = new List<OI_OrgHealthFindingCandidate>();
    for (Integer i = 0; i < 5; i++) {
      candidates.add(buildCandidate('objPage' + i, 'Warning'));
    }
    repo.upsertCandidates(candidates, 'run-1', Datetime.now());

    OI_RemediationFilterDTO firstPage = new OI_RemediationFilterDTO();
    firstPage.pageSize = 2;
    firstPage.pageNumber = 1;
    firstPage.sortField = 'title';
    firstPage.sortDirection = 'ASC';
    List<OI_Org_Health_Finding__c> page1 = repo.getFindingsByFilter(firstPage);

    OI_RemediationFilterDTO secondPage = new OI_RemediationFilterDTO();
    secondPage.pageSize = 2;
    secondPage.pageNumber = 2;
    secondPage.sortField = 'title';
    secondPage.sortDirection = 'ASC';
    List<OI_Org_Health_Finding__c> page2 = repo.getFindingsByFilter(secondPage);

    System.assertEquals(2, page1.size());
    System.assertEquals(2, page2.size());
    System.assertNotEquals(
      page1[0].Id,
      page2[0].Id,
      'Page 2 must return different rows than page 1.'
    );
    System.assertEquals(
      5,
      repo.getFindingsCountByFilter(new OI_RemediationFilterDTO()),
      'The count must reflect every matching row, unaffected by pagination.'
    );
  }

  @isTest
  static void testGetFindingsByFilterOnlyExpiringRiskAcceptance() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objExpiringSoon', 'Warning'),
        buildCandidate('objFarOut', 'Warning')
      },
      'run-1',
      Datetime.now()
    );
    OI_Org_Health_Finding__c expiringSoon = [
      SELECT Id
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c = 'objExpiringSoon'
    ];
    OI_Org_Health_Finding__c farOut = [
      SELECT Id
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c = 'objFarOut'
    ];
    repo.updateStatus(
      expiringSoon.Id,
      'Risk Accepted',
      null,
      null,
      null,
      null,
      Date.today().addDays(10),
      null
    );
    repo.updateStatus(
      farOut.Id,
      'Risk Accepted',
      null,
      null,
      null,
      null,
      Date.today().addYears(1),
      null
    );

    OI_RemediationFilterDTO filter = new OI_RemediationFilterDTO();
    filter.onlyExpiringRiskAcceptance = true;
    List<OI_Org_Health_Finding__c> results = repo.getFindingsByFilter(filter);

    System.assertEquals(
      1,
      results.size(),
      'Only the Risk Accepted finding expiring within the lookahead window must come back.'
    );
    System.assertEquals('objExpiringSoon', results[0].Component_Key__c);
  }

  @isTest
  static void testGetFindingsByFilterOnlyOverdueExcludesTerminalStatuses() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objOverdue', 'Warning'),
        buildCandidate('objOverdueButResolved', 'Warning')
      },
      'run-1',
      Datetime.now()
    );
    OI_Org_Health_Finding__c overdue = [
      SELECT Id
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c = 'objOverdue'
    ];
    OI_Org_Health_Finding__c overdueButResolved = [
      SELECT Id
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c = 'objOverdueButResolved'
    ];
    repo.updateStatus(
      overdue.Id,
      null,
      null,
      Date.today().addDays(-3),
      null,
      null,
      null,
      null
    );
    repo.updateStatus(
      overdueButResolved.Id,
      'Resolved',
      null,
      Date.today().addDays(-3),
      null,
      null,
      null,
      null
    );

    OI_RemediationFilterDTO filter = new OI_RemediationFilterDTO();
    filter.onlyOverdue = true;
    List<OI_Org_Health_Finding__c> results = repo.getFindingsByFilter(filter);

    System.assertEquals(
      1,
      results.size(),
      'A Resolved finding with a past due date is no longer actionable and must not count as overdue.'
    );
    System.assertEquals('objOverdue', results[0].Component_Key__c);
  }

  @isTest
  static void testGetFindingsForExportIgnoresPageSizeAndReturnsEveryMatchingRow() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    List<OI_OrgHealthFindingCandidate> candidates = new List<OI_OrgHealthFindingCandidate>();
    for (Integer i = 0; i < 5; i++) {
      candidates.add(buildCandidate('objExport' + i, 'Warning'));
    }
    repo.upsertCandidates(candidates, 'run-1', Datetime.now());

    OI_RemediationFilterDTO filter = new OI_RemediationFilterDTO();
    filter.pageSize = 1;
    filter.pageNumber = 1;
    List<OI_Org_Health_Finding__c> exported = repo.getFindingsForExport(filter);

    System.assertEquals(
      5,
      exported.size(),
      'Export must return every matching row regardless of the filter\'s own interactive pageSize.'
    );
  }

  @isTest
  static void testSummaryAggregateCountsGroupCorrectlyAndExcludeOrIncludeTerminalStatusesAsDocumented() {
    OI_OrgHealthFindingRepository repo = new OI_OrgHealthFindingRepository();
    OI_OrgHealthFindingCandidate securityCandidate = buildCandidate(
      'objSecuritySummary',
      'Critical'
    );
    securityCandidate.sectionKey = 'SecurityHealth';
    repo.upsertCandidates(
      new List<OI_OrgHealthFindingCandidate>{
        buildCandidate('objMetaSummary', 'Warning'),
        securityCandidate
      },
      'run-1',
      Datetime.now()
    );
    OI_Org_Health_Finding__c resolvedTarget = [
      SELECT Id
      FROM OI_Org_Health_Finding__c
      WHERE Component_Key__c = 'objMetaSummary'
    ];
    repo.updateStatus(
      resolvedTarget.Id,
      'Resolved',
      null,
      null,
      null,
      null,
      null,
      null
    );

    System.assertEquals(
      1,
      repo.getTotalOpenCount(),
      'Only the still-open (non-terminal) SecurityHealth finding must count as open — the Resolved one must not.'
    );

    Map<String, Integer> bySeverity = new Map<String, Integer>();
    for (AggregateResult ar : repo.getOpenCountsBySeverity()) {
      bySeverity.put((String) ar.get('sev'), (Integer) ar.get('total'));
    }
    System.assertEquals(
      1,
      bySeverity.get('Critical'),
      'Open-counts-by-severity must exclude the Resolved Warning finding.'
    );
    System.assertEquals(
      false,
      bySeverity.containsKey('Warning'),
      'The Resolved Warning finding must not appear in the open severity breakdown at all.'
    );

    Map<String, Integer> byStatus = new Map<String, Integer>();
    for (AggregateResult ar : repo.getCountsByStatus()) {
      byStatus.put((String) ar.get('stat'), (Integer) ar.get('total'));
    }
    System.assertEquals(
      1,
      byStatus.get('Resolved'),
      'Counts-by-status must INCLUDE terminal statuses — this is the one view where Resolved volume is the point.'
    );
    System.assertEquals(1, byStatus.get('Open'));

    Map<String, Integer> bySection = new Map<String, Integer>();
    for (AggregateResult ar : repo.getOpenCountsBySection()) {
      bySection.put((String) ar.get('sec'), (Integer) ar.get('total'));
    }
    System.assertEquals(1, bySection.get('SecurityHealth'));
    System.assertEquals(
      false,
      bySection.containsKey('MetadataHealth'),
      'The Resolved MetadataHealth finding must not appear in the open section breakdown.'
    );
  }

  private static OI_OrgHealthFindingCandidate buildCandidate(
    String componentKey,
    String severityKey
  ) {
    OI_OrgHealthFindingCandidate candidate = new OI_OrgHealthFindingCandidate();
    candidate.sectionKey = 'MetadataHealth';
    candidate.ruleId = 'MetadataHealth.HighFieldCount';
    candidate.ruleVersion = 1;
    candidate.title = 'Test finding for ' + componentKey;
    candidate.severityKey = severityKey;
    candidate.confidence = 'Medium';
    candidate.componentKey = componentKey;
    candidate.componentType = 'Custom';
    candidate.componentLabel = componentKey;
    candidate.isManaged = false;
    candidate.evidence = 'Evidence for ' + componentKey;
    candidate.measuredValue = '100 fields';
    candidate.expectedValue = '< 60 fields';
    candidate.explanation = 'Explanation text.';
    candidate.orgRisk = 'Org risk text.';
    candidate.potentialImpact = 'Impact text.';
    candidate.remediation = 'Remediation text.';
    candidate.validationSteps = 'Validation text.';
    return candidate;
  }
}
