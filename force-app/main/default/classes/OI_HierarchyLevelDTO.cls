/**
 * Purpose: The @AuraEnabled wire shape for OI_Hierarchy_Level__c.
 * Dependencies: None.
 * Limitations: None.
 */
public class OI_HierarchyLevelDTO {
    @AuraEnabled
    public Id levelId;
    @AuraEnabled
    public Id definitionId;
    @AuraEnabled
    public String levelName;
    @AuraEnabled
    public Integer levelNumber;
    @AuraEnabled
    public String objectApiName;
    @AuraEnabled
    public Boolean isRequired;
    @AuraEnabled
    public String relationshipFieldApiName;

    public OI_HierarchyLevelDTO(OI_Hierarchy_Level__c level) {
        this.levelId = level.Id;
        this.definitionId = level.Hierarchy_Definition__c;
        this.levelName = level.Name;
        this.levelNumber = level.Level_Number__c == null ? null : Integer.valueOf(level.Level_Number__c);
        this.objectApiName = level.Object_Api_Name__c;
        this.isRequired = level.Is_Required__c;
        this.relationshipFieldApiName = level.Relationship_Field_Api_Name__c;
    }
}
