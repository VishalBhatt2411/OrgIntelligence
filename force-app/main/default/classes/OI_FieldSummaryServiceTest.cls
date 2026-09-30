/**
 * Purpose: Verifies OI_FieldSummaryService lists every field from live Describe, attaches
 *          the graph node key only to persisted fields, keeps persisted fields Describe no
 *          longer returns, and degrades to persisted-only rows when the object is unknown
 *          (ADR-0031).
 */
@isTest
private class OI_FieldSummaryServiceTest {
  @isTest
  static void testMergesLiveDescribeWithPersistedFieldNodes() {
    insertObjectWithPersistedFields('Account');

    List<OI_FieldSummaryDTO> summaries = new OI_FieldSummaryService()
      .getFieldSummaries('acctObj');

    Map<String, OI_FieldSummaryDTO> byRowKey = byRowKey(summaries);
    Integer describedCount = Account.SObjectType.getDescribe()
      .fields.getMap()
      .size();
    System.assert(
      summaries.size() >= describedCount,
      'Every described field must be listed, not only persisted ones.'
    );

    OI_FieldSummaryDTO owner = byRowKey.get('Account.OwnerId');
    System.assertNotEquals(null, owner);
    System.assertEquals(
      'acctOwner',
      owner.nodeKey,
      'A persisted field keeps its graph node key so the row stays navigable.'
    );
    System.assertEquals(true, owner.isInGraph);
    System.assertEquals('REFERENCE', owner.dataType);
    System.assert(owner.referenceTo.contains('User'));

    OI_FieldSummaryDTO name = byRowKey.get('Account.Name');
    System.assertNotEquals(
      null,
      name,
      'A plain data field comes from Describe even with no graph node.'
    );
    System.assertEquals(null, name.nodeKey);
    System.assertEquals(false, name.isInGraph);
    System.assertEquals(false, name.isCustom);
    System.assertEquals(true, name.isRequired);

    OI_FieldSummaryDTO gone = byRowKey.get('Account.Retired_Lookup__c');
    System.assertNotEquals(
      null,
      gone,
      'A persisted field Describe no longer returns must still be listed until the next scan retires it.'
    );
    System.assertEquals('acctGone', gone.nodeKey);
  }

  @isTest
  static void testUnknownObjectNodeFallsBackToPersistedFieldsOnly() {
    insertObjectWithPersistedFields('Not_A_Real_Object_In_Any_Org__c');

    List<OI_FieldSummaryDTO> summaries = new OI_FieldSummaryService()
      .getFieldSummaries('acctObj');

    System.assertEquals(
      2,
      summaries.size(),
      'With no describable object only the persisted field nodes can be listed.'
    );
  }

  @isTest
  static void testMissingObjectNodeReturnsEmptyList() {
    System.assertEquals(
      0,
      new OI_FieldSummaryService().getFieldSummaries('noSuchNode').size()
    );
    System.assertEquals(
      0,
      new OI_FieldSummaryService().getFieldSummaries(null).size()
    );
  }

  private static void insertObjectWithPersistedFields(String objectApiName) {
    insert new List<OI_Graph_Node__c>{
      node(
        'acctObj',
        'SalesforceMetadata.CustomObject',
        objectApiName,
        objectApiName,
        '{}'
      ),
      node(
        'acctOwner',
        'SalesforceMetadata.CustomField',
        'Owner ID',
        'Account.OwnerId',
        '{"custom":false,"type":"REFERENCE","nillable":false,"referenceTo":["User"]}'
      ),
      node(
        'acctGone',
        'SalesforceMetadata.CustomField',
        'Retired Lookup',
        'Account.Retired_Lookup__c',
        '{"custom":true,"type":"REFERENCE","nillable":true}'
      )
    };
    insert new List<OI_Graph_Edge__c>{
      hasField('hf1', 'acctOwner'),
      hasField('hf2', 'acctGone')
    };
  }

  private static OI_Graph_Node__c node(
    String key,
    String typeKey,
    String label,
    String secondaryKey,
    String attributesJson
  ) {
    return new OI_Graph_Node__c(
      Node_Key__c = key,
      Node_Version_Key__c = key + '::v1',
      Version_Number__c = 1,
      Node_Type__c = typeKey,
      Label__c = label,
      Secondary_Key__c = secondaryKey,
      Attributes_Json__c = attributesJson,
      Checksum__c = 'c1',
      State__c = 'Active',
      Is_Current__c = true
    );
  }

  private static OI_Graph_Edge__c hasField(String key, String fieldKey) {
    return new OI_Graph_Edge__c(
      Edge_Key__c = key,
      Edge_Version_Key__c = key + '::v1',
      Version_Number__c = 1,
      Edge_Type__c = 'SalesforceMetadata.HAS_FIELD',
      Source_Node_Key__c = 'acctObj',
      Target_Node_Key__c = fieldKey,
      State__c = 'Active',
      Is_Current__c = true
    );
  }

  private static Map<String, OI_FieldSummaryDTO> byRowKey(
    List<OI_FieldSummaryDTO> summaries
  ) {
    Map<String, OI_FieldSummaryDTO> result = new Map<String, OI_FieldSummaryDTO>();
    for (OI_FieldSummaryDTO summary : summaries) {
      result.put(summary.rowKey, summary);
    }
    return result;
  }
}
