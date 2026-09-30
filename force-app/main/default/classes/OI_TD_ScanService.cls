/**
 * Purpose: Starts Tech Debt scans and owns the recurring-scan schedule.
 * Responsibilities: Create the OI_TD_Scan__c row and launch OI_TD_ScanBatch (one scan at a time,
 *                    with self-healing of scans whose batch chain died); read/update the org-level
 *                    schedule (OI_TD_Settings__c) and keep the OI_TD_ScheduledScan jobs (a check every
 *                    15 minutes, like the reference app) in step.
 * Dependencies: OI_TD_ScanBatch, OI_TD_ScanState, OI_TD_ScheduledScan, OI_TD_Settings__c.
 * Limitations: Schedules are org-wide, like the reference app's per-org schedule. Salesforce cron
 *              has no "every 15 minutes", so four hourly jobs run at :00, :15, :30 and :45.
 */
public with sharing class OI_TD_ScanService {
  public static final String TRIGGER_MANUAL = 'manual';
  public static final String TRIGGER_SCHEDULED = 'scheduled';
  public static final List<String> FREQUENCIES = new List<String>{
    'off',
    'daily',
    'weekly',
    'monthly'
  };
  public static final String JOB_NAME = 'OI Tech Debt scheduled scan';
  private static final List<Integer> CHECK_MINUTES = new List<Integer>{
    0,
    15,
    30,
    45
  };
  private static final Set<String> ACTIVE_JOB_STATUSES = new Set<String>{
    'Holding',
    'Queued',
    'Preparing',
    'Processing'
  };

  public class ScheduleInfo {
    @AuraEnabled
    public String scheduleFrequency;
    @AuraEnabled
    public Datetime nextScanAt;
  }

  /** Creates a scan and starts the batch chain. Throws if one is already running. */
  public static Id startScan(String triggeredBy) {
    healStaleScans();
    if (
      ![
          SELECT Id
          FROM OI_TD_Scan__c
          WHERE Status__c = :OI_TD_ScanEngine.STATUS_RUNNING
          LIMIT 1
        ]
        .isEmpty()
    ) {
      throw new OI_ValidationException(
        'A scan is already running. Wait for it to finish before starting another.'
      );
    }
    OI_TD_Scan__c scan = new OI_TD_Scan__c(
      Status__c = OI_TD_ScanEngine.STATUS_RUNNING,
      Started_At__c = System.now(),
      Triggered_By__c = triggeredBy,
      Current_Stage__c = OI_TD_ScanEngine.stageLabel(0)
    );
    insert scan;
    Database.executeBatch(new OI_TD_ScanBatch(new OI_TD_ScanState(scan.Id)), 1);
    return scan.Id;
  }

  /** A "running" scan with no live batch job was interrupted (job aborted, org maintenance…). */
  public static void healStaleScans() {
    List<OI_TD_Scan__c> running = [
      SELECT Id
      FROM OI_TD_Scan__c
      WHERE Status__c = :OI_TD_ScanEngine.STATUS_RUNNING
      LIMIT 10
    ];
    if (running.isEmpty() || hasActiveScanJob()) {
      return;
    }
    for (OI_TD_Scan__c scan : running) {
      OI_TD_ScanEngine.markScanFailed(
        scan.Id,
        'The scan was interrupted before it could finish.',
        null
      );
    }
  }

  private static Boolean hasActiveScanJob() {
    return ![
        SELECT Id
        FROM AsyncApexJob
        WHERE
          ApexClass.Name = 'OI_TD_ScanBatch'
          AND JobType = 'BatchApex'
          AND Status IN :ACTIVE_JOB_STATUSES
        LIMIT 1
      ]
      .isEmpty();
  }

  // ---------------------------------------------------------------------
  // Schedule
  // ---------------------------------------------------------------------

  public static ScheduleInfo getSchedule() {
    OI_TD_Settings__c s = OI_TD_Settings__c.getOrgDefaults();
    ScheduleInfo info = new ScheduleInfo();
    info.scheduleFrequency = String.isBlank(s.Frequency__c)
      ? 'off'
      : s.Frequency__c;
    info.nextScanAt = info.scheduleFrequency == 'off'
      ? null
      : s.Next_Scan_At__c;
    return info;
  }

  public static ScheduleInfo updateSchedule(String frequency) {
    if (String.isBlank(frequency) || !FREQUENCIES.contains(frequency)) {
      throw new OI_ValidationException(
        'frequency must be one of: ' + String.join(FREQUENCIES, ', ')
      );
    }
    OI_TD_Settings__c s = OI_TD_Settings__c.getOrgDefaults();
    s.Frequency__c = frequency;
    s.Next_Scan_At__c = nextScanAtFor(frequency, System.now());
    if (frequency == 'off') {
      abortExistingByName();
      s.Scheduled_Job_Id__c = null;
    } else if (activeJobCount() != CHECK_MINUTES.size()) {
      abortExistingByName();
      s.Scheduled_Job_Id__c = null;
      for (Integer minute : CHECK_MINUTES) {
        Id jobId = System.schedule(
          JOB_NAME + ' :' + String.valueOf(minute).leftPad(2, '0'),
          '0 ' + minute + ' * * * ?',
          new OI_TD_ScheduledScan()
        );
        if (s.Scheduled_Job_Id__c == null) {
          s.Scheduled_Job_Id__c = jobId;
        }
      }
    }
    upsert s;
    return getSchedule();
  }

  public static Datetime nextScanAtFor(String frequency, Datetime fromTime) {
    if (frequency == 'daily')
      return fromTime.addHours(24);
    if (frequency == 'weekly')
      return fromTime.addDays(7);
    if (frequency == 'monthly')
      return fromTime.addDays(30);
    return null;
  }

  /**
   * Called every 15 minutes: starts a scan when one is due and moves the next run forward.
   * While another scan is still running the due time is left alone, so the next check retries
   * instead of silently skipping this run.
   */
  public static void runDueScan() {
    OI_TD_Settings__c s = OI_TD_Settings__c.getOrgDefaults();
    if (
      String.isBlank(s.Frequency__c) ||
      s.Frequency__c == 'off' ||
      s.Next_Scan_At__c == null ||
      s.Next_Scan_At__c > System.now()
    ) {
      return;
    }
    if (isScanRunning()) {
      return;
    }
    try {
      startScan(TRIGGER_SCHEDULED);
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'Scheduled Tech Debt scan did not start: ' + e.getMessage()
      );
    }
    s.Next_Scan_At__c = nextScanAtFor(s.Frequency__c, System.now());
    upsert s;
  }

  private static Boolean isScanRunning() {
    healStaleScans();
    return ![
        SELECT Id
        FROM OI_TD_Scan__c
        WHERE Status__c = :OI_TD_ScanEngine.STATUS_RUNNING
        LIMIT 1
      ]
      .isEmpty();
  }

  private static Integer activeJobCount() {
    String pattern = JOB_NAME + '%';
    return [
      SELECT COUNT()
      FROM CronTrigger
      WHERE
        CronJobDetail.Name LIKE :pattern
        AND State NOT IN ('DELETED', 'COMPLETE', 'ERROR')
    ];
  }

  private static void abortExistingByName() {
    String pattern = JOB_NAME + '%';
    for (CronTrigger ct : [
      SELECT Id
      FROM CronTrigger
      WHERE
        CronJobDetail.Name LIKE :pattern
        AND State NOT IN ('DELETED', 'COMPLETE', 'ERROR')
      LIMIT 20
    ]) {
      System.abortJob(ct.Id);
    }
  }
}
