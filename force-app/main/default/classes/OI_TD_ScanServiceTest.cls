/**
 * Purpose: Verifies OI_TD_ScanService — scan start (one at a time), stale-scan healing and the
 *          org-level recurring schedule — plus the hourly OI_TD_ScheduledScan job and the
 *          OI_TD_ScanBatch chain driver.
 */
@isTest
private class OI_TD_ScanServiceTest {
  @isTest
  static void startScanCreatesRunningScanAndBatch() {
    OI_TD_TestSupport.installEngineFakes();
    Test.startTest();
    Id scanId = OI_TD_ScanService.startScan(OI_TD_ScanService.TRIGGER_MANUAL);
    Boolean threw = false;
    try {
      OI_TD_ScanService.startScan(OI_TD_ScanService.TRIGGER_MANUAL);
    } catch (OI_ValidationException e) {
      threw = true;
      System.assert(
        e.getMessage().startsWith('A scan is already running'),
        e.getMessage()
      );
    }
    System.assert(
      [
        SELECT COUNT()
        FROM OI_TD_Scan__c
        WHERE Status__c = :OI_TD_ScanEngine.STATUS_RUNNING
      ] <= 1,
      'never more than one running scan (threw=' + threw + ')'
    );
    Test.stopTest();
    OI_TD_Scan__c s = [
      SELECT Triggered_By__c, Current_Stage__c
      FROM OI_TD_Scan__c
      WHERE Id = :scanId
    ];
    System.assertEquals('manual', s.Triggered_By__c);
    System.assertNotEquals(null, s.Current_Stage__c);
  }

  @isTest
  static void staleRunningScansAreHealed() {
    OI_TD_Scan__c stale = OI_TD_TestSupport.insertScan(
      OI_TD_ScanEngine.STATUS_RUNNING,
      System.now().addHours(-3),
      null
    );
    OI_TD_ScanService.healStaleScans();
    OI_TD_Scan__c s = [
      SELECT Status__c, Error__c
      FROM OI_TD_Scan__c
      WHERE Id = :stale.Id
    ];
    System.assertEquals(OI_TD_ScanEngine.STATUS_FAILED, s.Status__c);
    System.assertEquals(
      'The scan was interrupted before it could finish.',
      s.Error__c
    );
  }

  @isTest
  static void scheduleOnAndOff() {
    System.assertEquals(
      'off',
      OI_TD_ScanService.getSchedule().scheduleFrequency
    );
    System.assertEquals(null, OI_TD_ScanService.getSchedule().nextScanAt);

    Test.startTest();
    OI_TD_ScanService.ScheduleInfo daily = OI_TD_ScanService.updateSchedule(
      'daily'
    );
    System.assertEquals('daily', daily.scheduleFrequency);
    System.assertNotEquals(null, daily.nextScanAt);
    Id jobId = OI_TD_Settings__c.getOrgDefaults().Scheduled_Job_Id__c;
    System.assertNotEquals(null, jobId);
    // A check every 15 minutes: four hourly jobs at :00, :15, :30 and :45.
    System.assertEquals(4, activeScheduleJobs());

    // Changing frequency keeps the same jobs.
    OI_TD_ScanService.updateSchedule('monthly');
    System.assertEquals(
      jobId,
      OI_TD_Settings__c.getOrgDefaults().Scheduled_Job_Id__c
    );

    OI_TD_ScanService.ScheduleInfo off = OI_TD_ScanService.updateSchedule(
      'off'
    );
    Test.stopTest();
    System.assertEquals('off', off.scheduleFrequency);
    System.assertEquals(
      null,
      OI_TD_Settings__c.getOrgDefaults().Scheduled_Job_Id__c
    );
    System.assertEquals(0, activeScheduleJobs());
  }

  private static Integer activeScheduleJobs() {
    String pattern = OI_TD_ScanService.JOB_NAME + '%';
    return [
      SELECT COUNT()
      FROM CronTrigger
      WHERE
        CronJobDetail.Name LIKE :pattern
        AND State NOT IN ('DELETED', 'COMPLETE', 'ERROR')
    ];
  }

  /** A due run that finds a scan still running is retried at the next check, not skipped. */
  @isTest
  static void dueScanWaitsWhileAnotherScanRuns() {
    OI_TD_TestSupport.installEngineFakes();
    Datetime due = System.now().addMinutes(-5);
    insert new OI_TD_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Frequency__c = 'daily',
      Next_Scan_At__c = due
    );
    Test.startTest();
    OI_TD_ScanService.startScan(OI_TD_ScanService.TRIGGER_MANUAL);
    OI_TD_ScanService.runDueScan();
    System.assertEquals(
      due,
      OI_TD_Settings__c.getOrgDefaults().Next_Scan_At__c,
      'The due time must not move while a scan is running.'
    );
    Test.stopTest();
    System.assertEquals(1, [SELECT COUNT() FROM OI_TD_Scan__c]);
  }

  @isTest
  static void invalidFrequencyIsRejected() {
    try {
      OI_TD_ScanService.updateSchedule('hourly');
      System.assert(false, 'expected a validation error');
    } catch (OI_ValidationException e) {
      System.assertEquals(
        'frequency must be one of: off, daily, weekly, monthly',
        e.getMessage()
      );
    }
  }

  @isTest
  static void nextScanTimes() {
    Datetime t = Datetime.newInstanceGmt(2026, 1, 1, 0, 0, 0);
    System.assertEquals(
      t.addHours(24),
      OI_TD_ScanService.nextScanAtFor('daily', t)
    );
    System.assertEquals(
      t.addDays(7),
      OI_TD_ScanService.nextScanAtFor('weekly', t)
    );
    System.assertEquals(
      t.addDays(30),
      OI_TD_ScanService.nextScanAtFor('monthly', t)
    );
    System.assertEquals(null, OI_TD_ScanService.nextScanAtFor('off', t));
  }

  @isTest
  static void dueScheduledScanStarts() {
    OI_TD_TestSupport.installEngineFakes();
    insert new OI_TD_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Frequency__c = 'weekly',
      Next_Scan_At__c = System.now().addMinutes(-5)
    );
    Test.startTest();
    new OI_TD_ScheduledScan().execute(null);
    Test.stopTest();
    OI_TD_Scan__c s = [SELECT Triggered_By__c FROM OI_TD_Scan__c LIMIT 1];
    System.assertEquals('scheduled', s.Triggered_By__c);
    System.assert(
      OI_TD_Settings__c.getOrgDefaults().Next_Scan_At__c >
      System.now().addDays(6)
    );
  }

  @isTest
  static void notDueScheduledScanDoesNothing() {
    insert new OI_TD_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Frequency__c = 'daily',
      Next_Scan_At__c = System.now().addHours(5)
    );
    OI_TD_ScanService.runDueScan();
    delete OI_TD_Settings__c.getOrgDefaults();
    OI_TD_ScanService.runDueScan();
    System.assertEquals(0, [SELECT COUNT() FROM OI_TD_Scan__c]);
  }

  @isTest
  static void batchStopsWhenScanIsNoLongerRunning() {
    OI_TD_TestSupport.installEngineFakes();
    OI_TD_Scan__c scan = OI_TD_TestSupport.insertScan(
      OI_TD_ScanEngine.STATUS_FAILED,
      System.now(),
      null
    );
    Test.startTest();
    Database.executeBatch(new OI_TD_ScanBatch(new OI_TD_ScanState(scan.Id)), 1);
    Test.stopTest();
    System.assertEquals(
      OI_TD_ScanEngine.STATUS_FAILED,
      [SELECT Status__c FROM OI_TD_Scan__c WHERE Id = :scan.Id].Status__c
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM OI_TD_Scan_Data__c WHERE Scan__c = :scan.Id]
    );
  }
}
