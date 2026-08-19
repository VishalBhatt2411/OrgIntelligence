/**
 * Purpose: Query construction for OI_Hierarchy_Relationship_History__c — the only class that
 *          writes SOQL against this object (CodingStandards.md §4).
 * Responsibilities: Bulk reads of a record's change history within one definition (FR-017).
 * Dependencies: OI_Hierarchy_Relationship_History__c.
 * Limitations: Every method is bulk-shaped.
 */
public with sharing class OI_HierarchyRelationshipHistorySelector {
    public List<OI_Hierarchy_Relationship_History__c> selectByDefinitionAndChild(Id definitionId, String childObjectApiName, String childRecordId) {
        if (definitionId == null || String.isBlank(childRecordId)) {
            return new List<OI_Hierarchy_Relationship_History__c>();
        }
        return [
            SELECT Id, Hierarchy_Definition__c, Child_Object_Api_Name__c, Child_Record_Id__c, Previous_Parent_Record_Id__c, New_Parent_Record_Id__c, Changed_By__c, Changed_By__r.Name, Changed_Date__c, Change_Type__c
            FROM OI_Hierarchy_Relationship_History__c
            WHERE Hierarchy_Definition__c = :definitionId AND Child_Object_Api_Name__c = :childObjectApiName AND Child_Record_Id__c = :childRecordId
            ORDER BY Changed_Date__c DESC
        ];
    }
}
