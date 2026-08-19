/**
 * Purpose: The @AuraEnabled boundary for Impact Analysis (Architecture.md §7) — backs
 *          oiNodeDetailPanel's "What does this depend on?" / "What depends on this?"
 *          actions.
 * Responsibilities: Permission check -> call OI_DependencyEngineService only -> map to
 *                    OI_ImpactResultDTO -> return, or translate to a sanitized
 *                    AuraHandledException, exactly matching OI_GraphController's own
 *                    established pattern.
 * Dependencies: OI_DependencyEngineService, OI_SecurityService, OI_ImpactResultDTO.
 * Limitations: Gated by the existing OI_View_Graph permission, not a new one — Impact
 *              Analysis is a heavier read of the same graph a Viewer already sees
 *              (OI_View_Graph's own description already names "view impact analysis" as
 *              part of its scope), so a dedicated permission would be an unjustified new
 *              surface for a distinction the platform's own permission model never drew.
 */
public with sharing class OI_DependencyController {
    @AuraEnabled
    public static OI_ImpactResultDTO getImpact(String nodeKey, String direction, Integer depth) {
        try {
            OI_SecurityService.assertPermission('OI_View_Graph');
            OI_ImpactResult result = new OI_DependencyEngineService().getImpact(nodeKey, direction, depth);
            return new OI_ImpactResultDTO(result);
        } catch (Exception e) {
            throw translate(e);
        }
    }

    /** Sanitized Controller-boundary translation (CodingStandards.md §6) — mirrors OI_GraphController.translate exactly. */
    private static AuraHandledException translate(Exception e) {
        String message;
        if (e instanceof OI_SecurityException) {
            message = 'You don\'t have permission to view org graph data.';
        } else if (e instanceof OI_ValidationException || e instanceof OI_ServiceException) {
            message = e.getMessage();
        } else {
            message = 'Something went wrong computing impact analysis. Please try again.';
        }
        AuraHandledException handled = new AuraHandledException(message);
        handled.setMessage(message);
        return handled;
    }
}
