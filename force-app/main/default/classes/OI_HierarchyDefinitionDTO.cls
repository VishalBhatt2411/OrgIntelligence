/**
 * Purpose: The @AuraEnabled wire shape for OI_Hierarchy_Definition__c.
 * Dependencies: None.
 * Limitations: None.
 */
public class OI_HierarchyDefinitionDTO {
    @AuraEnabled
    public Id definitionId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String objectApiName;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer maxLevels;
    @AuraEnabled
    public String relationshipType;
    @AuraEnabled
    public Boolean allowMultipleParents;
    @AuraEnabled
    public Boolean allowMultipleHierarchies;

    public OI_HierarchyDefinitionDTO(OI_Hierarchy_Definition__c definition) {
        this.definitionId = definition.Id;
        this.name = definition.Name;
        this.description = definition.Description__c;
        this.objectApiName = definition.Object_Api_Name__c;
        this.status = definition.Status__c;
        this.maxLevels = definition.Max_Levels__c == null ? null : Integer.valueOf(definition.Max_Levels__c);
        this.relationshipType = definition.Relationship_Type__c;
        this.allowMultipleParents = definition.Allow_Multiple_Parents__c;
        this.allowMultipleHierarchies = definition.Allow_Multiple_Hierarchies__c;
    }
}
