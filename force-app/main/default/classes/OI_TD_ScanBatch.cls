/**
 * Purpose: Drives a Tech Debt scan to completion as a chain of callout-enabled batch jobs.
 * Responsibilities: Each execute (scope 1, fresh governor limits) hands the carried
 *                    OI_TD_ScanState to OI_TD_ScanEngine for one budgeted slice of work. When the
 *                    ticks of one job run out before the scan finishes, finish() chains the next job.
 *                    An execute that dies on an uncatchable limit exception rolls its state back;
 *                    the next execute sees the job's error count rise and skips that section, so a
 *                    single bad section can never stall a scan. Three consecutive failures fail it.
 * Dependencies: OI_TD_ScanEngine, OI_TD_ScanState, OI_TD_Scan__c.
 * Limitations: One scan at a time (enforced by OI_TD_ScanService).
 */
public with sharing class OI_TD_ScanBatch implements Database.Batchable<Integer>, Database.AllowsCallouts, Database.Stateful {
  @TestVisible
  private static final Integer TICKS_PER_JOB = 15;
  private static final Integer MAX_FAIL_STREAK = 3;

  private OI_TD_ScanState st;
  private Integer errorsSeen = 0;
  private Boolean done = false;

  public OI_TD_ScanBatch(OI_TD_ScanState st) {
    this.st = st;
  }

  public Iterable<Integer> start(Database.BatchableContext bc) {
    List<Integer> ticks = new List<Integer>();
    Integer n = Test.isRunningTest() ? 1 : TICKS_PER_JOB;
    for (Integer i = 0; i < n; i++) {
      ticks.add(i);
    }
    return ticks;
  }

  public void execute(Database.BatchableContext bc, List<Integer> scope) {
    if (done) {
      return;
    }
    if (!scanStillRunning()) {
      done = true;
      return;
    }
    Integer errors = jobErrors(bc);
    if (errors > errorsSeen) {
      errorsSeen = errors;
      recordFailure(
        'A scan step ran out of Salesforce resources and was skipped.'
      );
      if (done) {
        return;
      }
    }
    done = OI_TD_ScanEngine.runExecute(st);
    st.failStreak = 0;
  }

  public void finish(Database.BatchableContext bc) {
    if (done) {
      return;
    }
    Integer errors = jobErrors(bc);
    if (errors > errorsSeen) {
      errorsSeen = errors;
      recordFailure(
        'A scan step ran out of Salesforce resources and was skipped.'
      );
    }
    if (!done && !Test.isRunningTest()) {
      Database.executeBatch(new OI_TD_ScanBatch(st), 1);
    }
  }

  private void recordFailure(String error) {
    st.failStreak++;
    if (st.failStreak >= MAX_FAIL_STREAK) {
      OI_TD_ScanEngine.markScanFailed(
        st.scanId,
        'The scan failed repeatedly and was stopped: ' + error,
        st.sections
      );
      done = true;
      return;
    }
    OI_TD_ScanEngine.skipSection(st, error);
    if (st.failed) {
      OI_TD_ScanEngine.markScanFailed(st.scanId, st.error, st.sections);
      done = true;
    }
  }

  private Boolean scanStillRunning() {
    List<OI_TD_Scan__c> rows = [
      SELECT Status__c
      FROM OI_TD_Scan__c
      WHERE Id = :st.scanId
      LIMIT 1
    ];
    return !rows.isEmpty() &&
      rows[0].Status__c == OI_TD_ScanEngine.STATUS_RUNNING;
  }

  private static Integer jobErrors(Database.BatchableContext bc) {
    if (bc == null || bc.getJobId() == null) {
      return 0;
    }
    List<AsyncApexJob> jobs = [
      SELECT NumberOfErrors
      FROM AsyncApexJob
      WHERE Id = :bc.getJobId()
      LIMIT 1
    ];
    return jobs.isEmpty() || jobs[0].NumberOfErrors == null
      ? 0
      : jobs[0].NumberOfErrors;
  }
}
