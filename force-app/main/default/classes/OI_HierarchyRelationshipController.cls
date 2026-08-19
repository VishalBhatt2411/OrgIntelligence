/**
 * Purpose: The @AuraEnabled boundary for hierarchy relationship assignment and history
 *          (FR-003/004/005/017) — backs oiHierarchyManager's relationship editing and
 *          oiHierarchyTree's history view.
 * Responsibilities: Permission check -> OI_HierarchyRelationshipService/OI_HierarchyRecordResolver
 *                    only -> DTO map (with resolved, accessibility-checked labels, ADR-0022)
 *                    -> return, or translate to a sanitized AuraHandledException.
 * Dependencies: OI_HierarchyRelationshipService, OI_HierarchyRelationshipHistorySelector,
 *               OI_HierarchyRecordResolver, OI_SecurityService.
 * Limitations: assignParent accepts either OI_Create_Hierarchy or OI_Edit_Hierarchy, since
 *              the same endpoint transparently serves both "create" and "move" depending on
 *              whether the child already has an active parent (OI_HierarchyRelationshipService's
 *              own documented behavior) — a dedicated move-only endpoint is not introduced
 *              for a distinction the service layer itself doesn't draw.
 */
public with sharing class OI_HierarchyRelationshipController {
    @AuraEnabled
    public static OI_HierarchyRelationshipDTO assignParent(
        Id definitionId,
        String parentObjectApiName,
        String parentRecordId,
        String childObjectApiName,
        String childRecordId,
        Id hierarchyLevelId,
        String relationshipType,
        Date effectiveStartDate,
        Date effectiveEndDate
    ) {
        try {
            assertAnyPermission(new List<String>{ 'OI_Create_Hierarchy', 'OI_Edit_Hierarchy' });
            OI_Hierarchy_Relationship__c saved = new OI_HierarchyRelationshipService()
                .assignParent(definitionId, parentObjectApiName, parentRecordId, childObjectApiName, childRecordId, hierarchyLevelId, relationshipType, effectiveStartDate, effectiveEndDate);
            return toDTO(saved);
        } catch (Exception e) {
            throw translate(e);
        }
    }

    @AuraEnabled
    public static void deactivateRelationship(Id relationshipId) {
        try {
            OI_SecurityService.assertPermission('OI_Delete_Hierarchy');
            new OI_HierarchyRelationshipService().deactivateRelationship(relationshipId);
        } catch (Exception e) {
            throw translate(e);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<OI_HierarchyRelationshipDTO> getRelationships(Id definitionId) {
        try {
            OI_SecurityService.assertPermission('OI_View_Hierarchy');
            List<OI_Hierarchy_Relationship__c> relationships = new OI_HierarchyRelationshipSelector().selectAllByDefinitionId(definitionId);
            Map<String, String> labelByRecordId = resolveLabelsFor(relationships);
            List<OI_HierarchyRelationshipDTO> results = new List<OI_HierarchyRelationshipDTO>();
            for (OI_Hierarchy_Relationship__c relationship : relationships) {
                results.add(new OI_HierarchyRelationshipDTO(relationship, labelByRecordId));
            }
            return results;
        } catch (Exception e) {
            throw translate(e);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<OI_HierarchyHistoryDTO> getHistory(Id definitionId, String childObjectApiName, String childRecordId) {
        try {
            OI_SecurityService.assertPermission('OI_View_Hierarchy_History');
            List<OI_Hierarchy_Relationship_History__c> historyRows = new OI_HierarchyRelationshipHistorySelector().selectByDefinitionAndChild(definitionId, childObjectApiName, childRecordId);
            List<OI_HierarchyRecordResolver.RecordRef> refs = new List<OI_HierarchyRecordResolver.RecordRef>();
            for (OI_Hierarchy_Relationship_History__c row : historyRows) {
                refs.add(new OI_HierarchyRecordResolver.RecordRef(childObjectApiName, row.Previous_Parent_Record_Id__c));
                refs.add(new OI_HierarchyRecordResolver.RecordRef(childObjectApiName, row.New_Parent_Record_Id__c));
            }
            Map<String, String> labelByRecordId = new OI_HierarchyRecordResolver().resolveLabels(refs);
            List<OI_HierarchyHistoryDTO> results = new List<OI_HierarchyHistoryDTO>();
            for (OI_Hierarchy_Relationship_History__c row : historyRows) {
                results.add(new OI_HierarchyHistoryDTO(row, labelByRecordId));
            }
            return results;
        } catch (Exception e) {
            throw translate(e);
        }
    }

    private static OI_HierarchyRelationshipDTO toDTO(OI_Hierarchy_Relationship__c relationship) {
        return new OI_HierarchyRelationshipDTO(relationship, resolveLabelsFor(new List<OI_Hierarchy_Relationship__c>{ relationship }));
    }

    private static Map<String, String> resolveLabelsFor(List<OI_Hierarchy_Relationship__c> relationships) {
        List<OI_HierarchyRecordResolver.RecordRef> refs = new List<OI_HierarchyRecordResolver.RecordRef>();
        for (OI_Hierarchy_Relationship__c relationship : relationships) {
            refs.add(new OI_HierarchyRecordResolver.RecordRef(relationship.Parent_Object_Api_Name__c, relationship.Parent_Record_Id__c));
            refs.add(new OI_HierarchyRecordResolver.RecordRef(relationship.Child_Object_Api_Name__c, relationship.Child_Record_Id__c));
        }
        return new OI_HierarchyRecordResolver().resolveLabels(refs);
    }

    private static void assertAnyPermission(List<String> customPermissionApiNames) {
        for (String permissionName : customPermissionApiNames) {
            if (OI_SecurityService.hasPermission(permissionName)) {
                return;
            }
        }
        throw new OI_SecurityException('Access denied.');
    }

    private static AuraHandledException translate(Exception e) {
        String message;
        if (e instanceof OI_SecurityException) {
            message = 'You don\'t have permission to modify this hierarchy.';
        } else if (e instanceof OI_ValidationException || e instanceof OI_ServiceException) {
            message = e.getMessage();
        } else {
            message = 'Something went wrong saving the hierarchy relationship. Please try again.';
        }
        AuraHandledException handled = new AuraHandledException(message);
        handled.setMessage(message);
        return handled;
    }
}
