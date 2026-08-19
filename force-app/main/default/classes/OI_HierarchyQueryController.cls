/**
 * Purpose: The @AuraEnabled boundary for read-only hierarchy traversal (FR-008/009/010/012)
 *          — backs oiHierarchyTree/oiHierarchyPath/oiHierarchyViewer.
 * Responsibilities: Permission check -> OI_HierarchyQueryService only -> DTO map (with
 *                    resolved, accessibility-checked labels, ADR-0022) -> return, or
 *                    translate to a sanitized AuraHandledException.
 * Dependencies: OI_HierarchyQueryService, OI_HierarchyRecordResolver, OI_SecurityService.
 * Limitations: None beyond OI_HierarchyQueryService's own documented ones.
 */
public with sharing class OI_HierarchyQueryController {
    @AuraEnabled(cacheable=true)
    public static List<OI_HierarchyRelationshipDTO> getAncestors(Id definitionId, String childObjectApiName, String childRecordId) {
        try {
            OI_SecurityService.assertPermission('OI_View_Hierarchy');
            List<OI_Hierarchy_Relationship__c> ancestors = new OI_HierarchyQueryService().getAncestors(definitionId, childObjectApiName, childRecordId);
            return toDTOs(ancestors);
        } catch (Exception e) {
            throw translate(e);
        }
    }

    @AuraEnabled(cacheable=true)
    public static OI_HierarchyDescendantsResultDTO getDescendants(Id definitionId, String parentObjectApiName, String parentRecordId) {
        try {
            OI_SecurityService.assertPermission('OI_View_Hierarchy');
            OI_HierarchyDescendantsResult result = new OI_HierarchyQueryService().getDescendants(definitionId, parentRecordId);
            return new OI_HierarchyDescendantsResultDTO(toDTOs(result.descendants), result.hasMore);
        } catch (Exception e) {
            throw translate(e);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<OI_HierarchyRelationshipDTO> getPath(Id definitionId, String childObjectApiName, String childRecordId) {
        try {
            OI_SecurityService.assertPermission('OI_View_Hierarchy');
            List<OI_Hierarchy_Relationship__c> path = new OI_HierarchyQueryService().getPath(definitionId, childObjectApiName, childRecordId);
            return toDTOs(path);
        } catch (Exception e) {
            throw translate(e);
        }
    }

    /** FR-008: every hierarchy (across all definitions) a record participates in — the Record 360 view embedded on a Lightning Record Page. */
    @AuraEnabled(cacheable=true)
    public static List<OI_HierarchyRelationshipDTO> getHierarchyMembership(String objectApiName, String recordId) {
        try {
            OI_SecurityService.assertPermission('OI_View_Hierarchy');
            List<OI_Hierarchy_Relationship__c> memberships = new OI_HierarchyQueryService().getHierarchyMembership(objectApiName, recordId);
            return toDTOs(memberships);
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
            message = 'You don\'t have permission to view this hierarchy.';
        } else if (e instanceof OI_ValidationException || e instanceof OI_ServiceException) {
            message = e.getMessage();
        } else {
            message = 'Something went wrong retrieving the hierarchy. Please try again.';
        }
        AuraHandledException handled = new AuraHandledException(message);
        handled.setMessage(message);
        return handled;
    }
}
