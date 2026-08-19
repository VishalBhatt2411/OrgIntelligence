/**
 * Purpose: The @AuraEnabled boundary for Hierarchy Search (FR-011, HA-6).
 * Responsibilities: Permission check -> OI_HierarchySearchService only -> DTO map (with
 *                    resolved, accessibility-checked labels, ADR-0022, identical to
 *                    OI_HierarchyQueryController's own convention) -> return, or translate to a
 *                    sanitized AuraHandledException.
 * Dependencies: OI_HierarchySearchService, OI_HierarchyRecordResolver, OI_SecurityService.
 * Limitations: None beyond OI_HierarchySearchService's own documented ones.
 */
public with sharing class OI_HierarchySearchController {
    @AuraEnabled(cacheable=true)
    public static List<OI_HierarchyRelationshipDTO> search(Id definitionId, String queryTerm, Id hierarchyLevelId, Boolean includeInactive) {
        try {
            OI_SecurityService.assertPermission('OI_View_Hierarchy');
            List<OI_Hierarchy_Relationship__c> matches = new OI_HierarchySearchService().search(definitionId, queryTerm, hierarchyLevelId, includeInactive);
            return toDTOs(matches);
        } catch (Exception e) {
            throw translate(e);
        }
    }

    private static List<OI_HierarchyRelationshipDTO> toDTOs(List<OI_Hierarchy_Relationship__c> relationships) {
        List<OI_HierarchyRecordResolver.RecordRef> refs = new List<OI_HierarchyRecordResolver.RecordRef>();
        for (OI_Hierarchy_Relationship__c relationship : relationships) {
            refs.add(new OI_HierarchyRecordResolver.RecordRef(relationship.Parent_Object_Api_Name__c, relationship.Parent_Record_Id__c));
            refs.add(new OI_HierarchyRecordResolver.RecordRef(relationship.Child_Object_Api_Name__c, relationship.Child_Record_Id__c));
        }
        Map<String, String> labelByRecordId = new OI_HierarchyRecordResolver().resolveLabels(refs);
        List<OI_HierarchyRelationshipDTO> results = new List<OI_HierarchyRelationshipDTO>();
        for (OI_Hierarchy_Relationship__c relationship : relationships) {
            results.add(new OI_HierarchyRelationshipDTO(relationship, labelByRecordId));
        }
        return results;
    }

    private static AuraHandledException translate(Exception e) {
        String message;
        if (e instanceof OI_SecurityException) {
            message = 'You don\'t have permission to search this hierarchy.';
        } else if (e instanceof OI_ValidationException || e instanceof OI_ServiceException) {
            message = e.getMessage();
        } else {
            message = 'Something went wrong searching the hierarchy. Please try again.';
        }
        AuraHandledException handled = new AuraHandledException(message);
        handled.setMessage(message);
        return handled;
    }
}
