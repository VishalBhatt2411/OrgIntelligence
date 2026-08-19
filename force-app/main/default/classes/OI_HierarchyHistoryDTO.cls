/**
 * Purpose: The @AuraEnabled wire shape for OI_Hierarchy_Relationship_History__c — same
 *          resolved-label discipline as OI_HierarchyRelationshipDTO (ADR-0022).
 * Dependencies: OI_Hierarchy_Relationship_History__c, a pre-resolved Map<recordId, label>.
 * Limitations: See OI_HierarchyRelationshipDTO's note on null labels.
 */
public class OI_HierarchyHistoryDTO {
    @AuraEnabled
    public Id historyId;
    @AuraEnabled
    public String childObjectApiName;
    @AuraEnabled
    public String childRecordId;
    @AuraEnabled
    public String previousParentRecordId;
    @AuraEnabled
    public String previousParentLabel;
    @AuraEnabled
    public String newParentRecordId;
    @AuraEnabled
    public String newParentLabel;
    @AuraEnabled
    public String changedByName;
    @AuraEnabled
    public Datetime changedDate;
    @AuraEnabled
    public String changeType;

    public OI_HierarchyHistoryDTO(OI_Hierarchy_Relationship_History__c history, Map<String, String> labelByRecordId) {
        this.historyId = history.Id;
        this.childObjectApiName = history.Child_Object_Api_Name__c;
        this.childRecordId = history.Child_Record_Id__c;
        this.previousParentRecordId = history.Previous_Parent_Record_Id__c;
        this.previousParentLabel = String.isBlank(history.Previous_Parent_Record_Id__c) ? null : labelByRecordId.get(history.Previous_Parent_Record_Id__c);
        this.newParentRecordId = history.New_Parent_Record_Id__c;
        this.newParentLabel = String.isBlank(history.New_Parent_Record_Id__c) ? null : labelByRecordId.get(history.New_Parent_Record_Id__c);
        this.changedByName = history.Changed_By__r != null ? history.Changed_By__r.Name : null;
        this.changedDate = history.Changed_Date__c;
        this.changeType = history.Change_Type__c;
    }
}
