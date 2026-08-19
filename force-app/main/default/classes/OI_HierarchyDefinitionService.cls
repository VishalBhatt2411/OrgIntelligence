/**
 * Purpose: CRUD for Hierarchy Definitions and Levels (FR-001/002) — admin configuration,
 *          distinct from day-to-day relationship assignment (OI_HierarchyRelationshipService).
 * Responsibilities: List/get definitions and their levels; save (create/update) a definition
 *                    or level, validating the configured object API name via the same
 *                    OI_RecordSchemaUtil describe check Record Analysis already uses (reuse,
 *                    not a second describe-validation implementation).
 * Dependencies: OI_HierarchyDefinitionSelector, OI_RecordSchemaUtil.
 * Limitations: Deletion of a Definition is intentionally not exposed — Status__c = Inactive
 *              is the supported deactivation path (FRD Business Rule 7); Hierarchy_Definition__c
 *              is Restrict-delete-constrained from OI_Hierarchy_Relationship__c/History
 *              specifically to make a silent hard-delete of an in-use definition impossible.
 */
public with sharing class OI_HierarchyDefinitionService {
    private final OI_HierarchyDefinitionSelector selector;

    public OI_HierarchyDefinitionService() {
        this(new OI_HierarchyDefinitionSelector());
    }

    public OI_HierarchyDefinitionService(OI_HierarchyDefinitionSelector selector) {
        this.selector = selector;
    }

    public List<OI_Hierarchy_Definition__c> getAllDefinitions() {
        return selector.selectAll();
    }

    public OI_Hierarchy_Definition__c getDefinition(Id definitionId) {
        OI_Hierarchy_Definition__c definition = selector.selectById(definitionId);
        if (definition == null) {
            throw new OI_ValidationException('Unknown hierarchy definition.');
        }
        return definition;
    }

    public List<OI_Hierarchy_Level__c> getLevels(Id definitionId) {
        return selector.selectLevelsByDefinitionId(definitionId);
    }

    public OI_Hierarchy_Definition__c saveDefinition(OI_Hierarchy_Definition__c definition) {
        OI_RecordSchemaUtil.describeAccessibleObject(definition.Object_Api_Name__c);
        upsert definition;
        return definition;
    }

    public OI_Hierarchy_Level__c saveLevel(OI_Hierarchy_Level__c level) {
        if (level.Hierarchy_Definition__c == null) {
            throw new OI_ValidationException('A hierarchy level must belong to a hierarchy definition.');
        }
        OI_RecordSchemaUtil.describeAccessibleObject(level.Object_Api_Name__c);
        upsert level;
        return level;
    }

    public void deleteLevel(Id levelId) {
        if (levelId == null) {
            return;
        }
        delete [SELECT Id FROM OI_Hierarchy_Level__c WHERE Id = :levelId];
    }
}
