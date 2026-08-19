/**
 * Purpose: The @AuraEnabled boundary for object-scoped record search (Record Analysis,
 *          ADR-0021) — backs oiRecordPicker. A separate Custom Permission from graph reads
 *          (OI_View_Records, not OI_View_Graph) since this reads arbitrary customer record
 *          data, not this platform's own scanned metadata.
 * Responsibilities: Permission check -> OI_RecordSearchService only -> return, or translate
 *                    to a sanitized AuraHandledException, matching every other Controller's
 *                    established pattern exactly.
 * Dependencies: OI_RecordSearchService, OI_SecurityService.
 * Limitations: None.
 */
public with sharing class OI_RecordSearchController {
    @AuraEnabled(cacheable=true)
    public static List<OI_RecordSummaryDTO> searchRecords(String objectApiName, String queryTerm) {
        try {
            OI_SecurityService.assertPermission('OI_View_Records');
            return new OI_RecordSearchService().search(objectApiName, queryTerm);
        } catch (Exception e) {
            throw translate(e);
        }
    }

    private static AuraHandledException translate(Exception e) {
        String message;
        if (e instanceof OI_SecurityException) {
            message = 'You don\'t have permission to search records.';
        } else if (e instanceof OI_ValidationException || e instanceof OI_ServiceException) {
            message = e.getMessage();
        } else {
            message = 'Something went wrong searching records. Please try again.';
        }
        AuraHandledException handled = new AuraHandledException(message);
        handled.setMessage(message);
        return handled;
    }
}
