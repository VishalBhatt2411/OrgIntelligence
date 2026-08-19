/**
 * Purpose: The @AuraEnabled boundary for a record's live hierarchy fragment (Record
 *          Analysis, ADR-0021 / Backlog RA-2) — backs the graph explorer's Record analyze
 *          mode. Gated by OI_View_Records, distinct from OI_View_Graph (metadata reads),
 *          since this reads arbitrary customer record data.
 * Responsibilities: Permission check -> OI_RecordHierarchyService only -> return, or
 *                    translate to a sanitized AuraHandledException, matching
 *                    OI_GraphController's own established pattern exactly.
 * Dependencies: OI_RecordHierarchyService, OI_SecurityService.
 * Limitations: None.
 */
public with sharing class OI_RecordHierarchyController {
    @AuraEnabled(cacheable=true)
    public static OI_RecordFragmentDTO getRecordFragment(String objectApiName, String recordId) {
        try {
            OI_SecurityService.assertPermission('OI_View_Records');
            return new OI_RecordHierarchyService().getRecordFragment(objectApiName, recordId);
        } catch (Exception e) {
            throw translate(e);
        }
    }

    private static AuraHandledException translate(Exception e) {
        String message;
        if (e instanceof OI_SecurityException) {
            message = 'You don\'t have permission to view record data.';
        } else if (e instanceof OI_ValidationException || e instanceof OI_ServiceException) {
            message = e.getMessage();
        } else {
            message = 'Something went wrong retrieving the record. Please try again.';
        }
        AuraHandledException handled = new AuraHandledException(message);
        handled.setMessage(message);
        return handled;
    }
}
