@IsTest
private class OI_OrgHealthSnapshotRepositoryTest {
  @IsTest
  static void testGetLatestReturnsNullWhenNoSnapshotExists() {
    System.assertEquals(
      null,
      new OI_OrgHealthSnapshotRepository().getLatest('DataHealth')
    );
  }

  @IsTest
  static void testGetLatestReturnsNullForBlankSectionKeyWithoutQuerying() {
    System.assertEquals(
      null,
      new OI_OrgHealthSnapshotRepository().getLatest('')
    );
  }

  @IsTest
  static void testPutThenGetLatestReturnsTheMostRecentlyInsertedRowForThatSection() {
    OI_OrgHealthSnapshotRepository repo = new OI_OrgHealthSnapshotRepository();
    repo.put(
      'DataHealth',
      'run-1',
      70,
      '{"a":1}',
      'first run',
      Datetime.now().addMinutes(-10),
      100,
      false,
      UserInfo.getUserId()
    );
    repo.put(
      'DataHealth',
      'run-2',
      85,
      '{"a":2}',
      'second run',
      Datetime.now(),
      150,
      true,
      UserInfo.getUserId()
    );

    OI_Org_Health_Snapshot__c latest = repo.getLatest('DataHealth');

    System.assertEquals(
      'run-2',
      latest.Compute_Run_Id__c,
      'The most recently computed row must win, not insertion order.'
    );
    System.assertEquals(85, latest.Score__c);
    System.assertEquals(true, latest.Is_Truncated__c);
  }

  @IsTest
  static void testPutIsAlwaysAnInsertNeverAnUpdate() {
    OI_OrgHealthSnapshotRepository repo = new OI_OrgHealthSnapshotRepository();
    repo.put(
      'DataHealth',
      'run-1',
      70,
      '{}',
      'note',
      Datetime.now(),
      1,
      false,
      UserInfo.getUserId()
    );
    repo.put(
      'DataHealth',
      'run-1',
      90,
      '{}',
      'note',
      Datetime.now(),
      1,
      false,
      UserInfo.getUserId()
    );

    List<OI_Org_Health_Snapshot__c> rows = [
      SELECT Id
      FROM OI_Org_Health_Snapshot__c
      WHERE Section_Key__c = 'DataHealth'
    ];
    System.assertEquals(
      2,
      rows.size(),
      'This object is append-only — even a repeated Compute_Run_Id__c must produce a new row, never overwrite one.'
    );
  }
}
