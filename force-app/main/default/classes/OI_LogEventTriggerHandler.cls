/**
 * Purpose: Bulk-safe delegate for OI_LogEventTrigger (CodingStandards.md §3) — maps
 *          OI_Log_Event__e records to OI_Log__c rows.
 * Responsibilities: No business logic beyond field mapping; persistence is
 *                    OI_LogRepository's job.
 * Dependencies: OI_LogRepository.
 * Limitations: None.
 */
public without sharing class OI_LogEventTriggerHandler {
    public void handleAfterInsert(List<OI_Log_Event__e> events) {
        List<OI_Log__c> logs = new List<OI_Log__c>();
        for (OI_Log_Event__e event : events) {
            logs.add(
                new OI_Log__c(
                    Timestamp__c = Datetime.now(),
                    Level__c = event.Level__c,
                    Correlation_Id__c = event.Correlation_Id__c,
                    Source__c = event.Source__c,
                    Message__c = event.Message__c,
                    Stack_Trace__c = event.Stack_Trace__c,
                    Running_User__c = UserInfo.getUserId()
                )
            );
        }
        new OI_LogRepository().insertLogs(logs);
    }
}
