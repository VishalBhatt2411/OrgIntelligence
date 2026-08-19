/**
 * Purpose: The @AuraEnabled boundary for scan lifecycle operations (API.md §2.4) — backs
 *          oiScanStatusPanel.
 * Responsibilities: Permission check -> call OI_ScanOrchestratorQueueable (the scan-
 *                    lifecycle owner since Sprint 8 — no separate Service class exists for
 *                    this domain, and none is introduced here) -> map to
 *                    OI_ScanRunSummaryDTO -> return, or translate to AuraHandledException
 *                    (Backlog F-1, CodingStandards.md §6). No business logic of its own.
 * Dependencies: OI_ScanOrchestratorQueueable, OI_SecurityService, OI_ScanRunSummaryDTO.
 * Limitations: Inherits every limitation documented on OI_ScanOrchestratorQueueable — this
 *              Controller adds no behavior beyond the permission check and the DTO map.
 */
public with sharing class OI_ScanController {
    @AuraEnabled
    public static OI_ScanRunSummaryDTO startScan(String scanType, List<String> metadataTypeOverride) {
        try {
            OI_SecurityService.assertPermission('OI_Run_Scan');
            Id scanRunId = OI_ScanOrchestratorQueueable.startScan(scanType, metadataTypeOverride);
            return new OI_ScanRunSummaryDTO(OI_ScanOrchestratorQueueable.getScanStatus(scanRunId));
        } catch (Exception e) {
            throw translate(e);
        }
    }

    @AuraEnabled(cacheable=true)
    public static OI_ScanRunSummaryDTO getScanStatus(Id scanRunId) {
        try {
            OI_SecurityService.assertPermission('OI_Run_Scan');
            return new OI_ScanRunSummaryDTO(OI_ScanOrchestratorQueueable.getScanStatus(scanRunId));
        } catch (Exception e) {
            throw translate(e);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<OI_ScanRunSummaryDTO> getScanHistory(Integer pageSize, String pageCursor) {
        try {
            OI_SecurityService.assertPermission('OI_Run_Scan');
            List<OI_ScanRunSummaryDTO> results = new List<OI_ScanRunSummaryDTO>();
            for (OI_Scan_Run__c run : OI_ScanOrchestratorQueueable.getScanHistory(pageSize, pageCursor)) {
                results.add(new OI_ScanRunSummaryDTO(run));
            }
            return results;
        } catch (Exception e) {
            throw translate(e);
        }
    }

    @AuraEnabled
    public static void cancelScan(Id scanRunId) {
        try {
            OI_SecurityService.assertPermission('OI_Run_Scan');
            OI_ScanOrchestratorQueueable.cancelScan(scanRunId);
        } catch (Exception e) {
            throw translate(e);
        }
    }

    /**
     * Sanitized Controller-boundary translation (CodingStandards.md §6) — never a raw
     * platform/application exception or stack trace reaches the client. The permission
     * check is inside the same try block as the rest of each method's body (not before
     * it) specifically so a denied OI_SecurityException is also translated here — Lightning
     * otherwise strips any non-AuraHandledException down to an opaque, unhelpful "Internal
     * Server Error" on the client, silently defeating the sanitized-message intent.
     */
    private static AuraHandledException translate(Exception e) {
        String message;
        if (e instanceof OI_SecurityException) {
            message = 'You don\'t have permission to manage scans.';
        } else if (e instanceof OI_ValidationException || e instanceof OI_ServiceException) {
            message = e.getMessage();
        } else {
            message = 'Something went wrong with the scan. Please try again.';
        }
        AuraHandledException handled = new AuraHandledException(message);
        handled.setMessage(message);
        return handled;
    }
}
