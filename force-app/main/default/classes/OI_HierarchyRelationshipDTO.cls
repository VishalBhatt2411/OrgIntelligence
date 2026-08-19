/**
 * Purpose: The @AuraEnabled wire shape for OI_Hierarchy_Relationship__c — never carries a
 *          raw Parent/Child_Record_Id__c straight from the junction row without a resolved,
 *          accessibility-checked label alongside it (ADR-0022, OI_HierarchyRecordResolver).
 * Dependencies: OI_Hierarchy_Relationship__c, a pre-resolved Map<recordId, label>.
 * Limitations: parentLabel/childLabel are null when the referenced record failed the
 *              accessibility re-check or no longer exists — the client must treat a null
 *              label as "not visible," never assume the record is gone.
 */
public class OI_HierarchyRelationshipDTO {
    @AuraEnabled
    public Id relationshipId;
    @AuraEnabled
    public Id definitionId;
    @AuraEnabled
    public Id levelId;
    @AuraEnabled
    public String parentObjectApiName;
    @AuraEnabled
    public String parentRecordId;
    @AuraEnabled
    public String parentLabel;
    @AuraEnabled
    public String childObjectApiName;
    @AuraEnabled
    public String childRecordId;
    @AuraEnabled
    public String childLabel;
    @AuraEnabled
    public Date effectiveStartDate;
    @AuraEnabled
    public Date effectiveEndDate;
    @AuraEnabled
    public Boolean isActive;
    @AuraEnabled
    public String relationshipType;

    public OI_HierarchyRelationshipDTO(OI_Hierarchy_Relationship__c relationship, Map<String, String> labelByRecordId) {
        this.relationshipId = relationship.Id;
        this.definitionId = relationship.Hierarchy_Definition__c;
        this.levelId = relationship.Hierarchy_Level__c;
        this.parentObjectApiName = relationship.Parent_Object_Api_Name__c;
        this.parentRecordId = relationship.Parent_Record_Id__c;
        this.parentLabel = String.isBlank(relationship.Parent_Record_Id__c) ? null : labelByRecordId.get(relationship.Parent_Record_Id__c);
        this.childObjectApiName = relationship.Child_Object_Api_Name__c;
        this.childRecordId = relationship.Child_Record_Id__c;
        this.childLabel = labelByRecordId.get(relationship.Child_Record_Id__c);
        this.effectiveStartDate = relationship.Effective_Start_Date__c;
        this.effectiveEndDate = relationship.Effective_End_Date__c;
        this.isActive = relationship.Is_Active__c;
        this.relationshipType = relationship.Relationship_Type__c;
    }
}
