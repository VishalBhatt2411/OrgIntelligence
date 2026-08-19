/**
 * Purpose: The @AuraEnabled boundary for finding a starting node to graph (Sprint 10) —
 *          backs oiSearchBar.
 * Responsibilities: Permission check -> OI_NodeSelector prefix lookup -> map to DTOs ->
 *                    return, or translate to a sanitized AuraHandledException.
 * Dependencies: OI_NodeSelector, OI_SecurityService, OI_SettingsService,
 *               OI_NodeSummaryDTO.
 * Limitations: This is a deliberately minimal substitute for the full, unbuilt
 *              SearchEngine.md epic (OI_SearchService, multi-domain SOSL ranking, Record
 *              domain, provider abstraction — all Backlog Phase 3, SR-0 through SR-7).
 *              It exists only so a user can select a starting node for the graph in this
 *              MVP; it is not the platform's eventual Search subsystem and should be
 *              replaced, not extended, when Search is actually built.
 */
public with sharing class OI_SearchController {
    @AuraEnabled(cacheable=true)
    public static List<OI_NodeSummaryDTO> search(String queryTerm) {
        try {
            OI_SecurityService.assertPermission('OI_View_Graph');
            Integer minLength = safeInt(new OI_SettingsService().getSettings().Min_Search_Query_Length__c, 2);
            if (String.isBlank(queryTerm) || queryTerm.trim().length() < minLength) {
                return new List<OI_NodeSummaryDTO>();
            }
            Integer maxResults = safeInt(new OI_SettingsService().getSettings().Max_Search_Results__c, 20);
            List<OI_NodeSummaryDTO> results = new List<OI_NodeSummaryDTO>();
            for (OI_Graph_Node__c node : new OI_NodeSelector().selectCurrentByLabelOrSecondaryKeyPrefix(queryTerm.trim(), maxResults)) {
                results.add(new OI_NodeSummaryDTO(node));
            }
            return results;
        } catch (Exception e) {
            throw translate(e);
        }
    }

    private static Integer safeInt(Decimal value, Integer fallback) {
        return value == null ? fallback : Integer.valueOf(value);
    }

    private static AuraHandledException translate(Exception e) {
        String message;
        if (e instanceof OI_SecurityException) {
            message = 'You don\'t have permission to search org graph data.';
        } else if (e instanceof OI_ValidationException || e instanceof OI_ServiceException) {
            message = e.getMessage();
        } else {
            message = 'Something went wrong searching. Please try again.';
        }
        AuraHandledException handled = new AuraHandledException(message);
        handled.setMessage(message);
        return handled;
    }
}
