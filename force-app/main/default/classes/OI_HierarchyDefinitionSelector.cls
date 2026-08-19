/**
 * Purpose: Query construction for OI_Hierarchy_Definition__c/OI_Hierarchy_Level__c — the only
 *          class that writes SOQL against these objects (CodingStandards.md §4).
 * Responsibilities: Bulk, keyset-shaped reads. Runs with sharing (ADR-0022 — unlike the
 *                    metadata graph's Apex-boundary objects, real Salesforce sharing applies
 *                    to Hierarchy objects).
 * Dependencies: OI_Hierarchy_Definition__c, OI_Hierarchy_Level__c.
 * Limitations: Every method is bulk-shaped.
 */
public with sharing class OI_HierarchyDefinitionSelector {
    private static final List<String> DEFINITION_FIELDS = new List<String>{
        'Id',
        'Name',
        'Description__c',
        'Object_Api_Name__c',
        'Status__c',
        'Max_Levels__c',
        'Relationship_Type__c',
        'Allow_Multiple_Parents__c',
        'Allow_Multiple_Hierarchies__c'
    };

    public OI_Hierarchy_Definition__c selectById(Id definitionId) {
        if (definitionId == null) {
            return null;
        }
        List<OI_Hierarchy_Definition__c> rows = Database.query(
            'SELECT ' + String.join(DEFINITION_FIELDS, ', ') + ' FROM OI_Hierarchy_Definition__c WHERE Id = :definitionId LIMIT 1'
        );
        return rows.isEmpty() ? null : rows[0];
    }

    public List<OI_Hierarchy_Definition__c> selectAll() {
        return Database.query('SELECT ' + String.join(DEFINITION_FIELDS, ', ') + ' FROM OI_Hierarchy_Definition__c ORDER BY Name ASC');
    }

    public List<OI_Hierarchy_Definition__c> selectActiveByObjectApiName(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return new List<OI_Hierarchy_Definition__c>();
        }
        return Database.query(
            'SELECT ' +
            String.join(DEFINITION_FIELDS, ', ') +
            ' FROM OI_Hierarchy_Definition__c WHERE Object_Api_Name__c = :objectApiName AND Status__c = \'Active\' ORDER BY Name ASC'
        );
    }

    public List<OI_Hierarchy_Level__c> selectLevelsByDefinitionId(Id definitionId) {
        if (definitionId == null) {
            return new List<OI_Hierarchy_Level__c>();
        }
        return [
            SELECT Id, Name, Hierarchy_Definition__c, Level_Number__c, Object_Api_Name__c, Is_Required__c, Relationship_Field_Api_Name__c, Validation_Rule_Json__c
            FROM OI_Hierarchy_Level__c
            WHERE Hierarchy_Definition__c = :definitionId
            ORDER BY Level_Number__c ASC
        ];
    }
}
