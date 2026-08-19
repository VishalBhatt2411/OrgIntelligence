/**
 * Purpose: The @AuraEnabled boundary for Hierarchy Definition/Level admin configuration
 *          (FR-001/002) — backs oiHierarchyManager.
 * Responsibilities: Permission check -> OI_HierarchyDefinitionService only -> DTO map ->
 *                    return, or translate to a sanitized AuraHandledException, matching
 *                    OI_GraphController's established pattern.
 * Dependencies: OI_HierarchyDefinitionService, OI_SecurityService.
 * Limitations: Reads gated by OI_View_Hierarchy; writes gated by OI_Manage_Hierarchy — the
 *              admin-configuration permission, distinct from OI_Create/Edit/Delete_Hierarchy
 *              which govern day-to-day relationship assignment (ADR-0022).
 */
public with sharing class OI_HierarchyDefinitionController {
    @AuraEnabled(cacheable=true)
    public static List<OI_HierarchyDefinitionDTO> getDefinitions() {
        try {
            OI_SecurityService.assertPermission('OI_View_Hierarchy');
            List<OI_HierarchyDefinitionDTO> results = new List<OI_HierarchyDefinitionDTO>();
            for (OI_Hierarchy_Definition__c definition : new OI_HierarchyDefinitionService().getAllDefinitions()) {
                results.add(new OI_HierarchyDefinitionDTO(definition));
            }
            return results;
        } catch (Exception e) {
            throw translate(e);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<OI_HierarchyLevelDTO> getLevels(Id definitionId) {
        try {
            OI_SecurityService.assertPermission('OI_View_Hierarchy');
            List<OI_HierarchyLevelDTO> results = new List<OI_HierarchyLevelDTO>();
            for (OI_Hierarchy_Level__c level : new OI_HierarchyDefinitionService().getLevels(definitionId)) {
                results.add(new OI_HierarchyLevelDTO(level));
            }
            return results;
        } catch (Exception e) {
            throw translate(e);
        }
    }

    @AuraEnabled
    public static OI_HierarchyDefinitionDTO saveDefinition(
        Id definitionId,
        String recordName,
        String description,
        String objectApiName,
        String status,
        Integer maxLevels,
        String relationshipType,
        Boolean allowMultipleParents,
        Boolean allowMultipleHierarchies
    ) {
        try {
            OI_SecurityService.assertPermission('OI_Manage_Hierarchy');
            OI_Hierarchy_Definition__c definition = new OI_Hierarchy_Definition__c(
                Id = definitionId,
                Name = recordName,
                Description__c = description,
                Object_Api_Name__c = objectApiName,
                Status__c = status,
                Max_Levels__c = maxLevels,
                Relationship_Type__c = relationshipType,
                Allow_Multiple_Parents__c = allowMultipleParents,
                Allow_Multiple_Hierarchies__c = allowMultipleHierarchies
            );
            return new OI_HierarchyDefinitionDTO(new OI_HierarchyDefinitionService().saveDefinition(definition));
        } catch (Exception e) {
            throw translate(e);
        }
    }

    @AuraEnabled
    public static OI_HierarchyLevelDTO saveLevel(Id levelId, Id definitionId, String levelName, Integer levelNumber, String objectApiName, Boolean isRequired, String relationshipFieldApiName) {
        try {
            OI_SecurityService.assertPermission('OI_Manage_Hierarchy');
            OI_Hierarchy_Level__c level = new OI_Hierarchy_Level__c(
                Id = levelId,
                Hierarchy_Definition__c = definitionId,
                Name = levelName,
                Level_Number__c = levelNumber,
                Object_Api_Name__c = objectApiName,
                Is_Required__c = isRequired,
                Relationship_Field_Api_Name__c = relationshipFieldApiName
            );
            return new OI_HierarchyLevelDTO(new OI_HierarchyDefinitionService().saveLevel(level));
        } catch (Exception e) {
            throw translate(e);
        }
    }

    @AuraEnabled
    public static void deleteLevel(Id levelId) {
        try {
            OI_SecurityService.assertPermission('OI_Manage_Hierarchy');
            new OI_HierarchyDefinitionService().deleteLevel(levelId);
        } catch (Exception e) {
            throw translate(e);
        }
    }

    private static AuraHandledException translate(Exception e) {
        String message;
        if (e instanceof OI_SecurityException) {
            message = 'You don\'t have permission to manage hierarchy configuration.';
        } else if (e instanceof OI_ValidationException || e instanceof OI_ServiceException) {
            message = e.getMessage();
        } else {
            message = 'Something went wrong saving the hierarchy configuration. Please try again.';
        }
        AuraHandledException handled = new AuraHandledException(message);
        handled.setMessage(message);
        return handled;
    }
}
