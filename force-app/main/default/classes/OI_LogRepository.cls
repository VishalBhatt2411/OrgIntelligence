/**
 * Purpose: Bulk persistence of OI_Log__c — the only class that writes this object
 *          (CodingStandards.md §1's Repository role).
 * Responsibilities: Insert log rows. No business logic — that lives in OI_LoggerService.
 * Dependencies: OI_Log__c.
 * Limitations: without sharing — logging must never fail because the triggering user
 *              (whoever is running when a Platform Event fires) lacks CRUD on OI_Log__c;
 *              these are application-internal diagnostic records (ADR-0006).
 */
public without sharing class OI_LogRepository {
    public void insertLogs(List<OI_Log__c> logs) {
        if (logs == null || logs.isEmpty()) {
            return;
        }
        insert logs;
    }
}
