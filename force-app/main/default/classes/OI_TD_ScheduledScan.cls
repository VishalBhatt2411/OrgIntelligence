/**
 * Purpose: 15-minute check that starts a recurring Tech Debt scan when one is due.
 * Responsibilities: Delegate to OI_TD_ScanService.runDueScan (frequency and next-run time live
 *                    in OI_TD_Settings__c, managed from the Scan Schedule dialog).
 * Dependencies: OI_TD_ScanService.
 * Limitations: Scheduled as four hourly jobs (:00/:15/:30/:45), so up to 15 minutes of lag after
 *              the due time — the same as the reference app.
 */
public with sharing class OI_TD_ScheduledScan implements Schedulable {
  public void execute(SchedulableContext sc) {
    OI_TD_ScanService.runDueScan();
  }
}
