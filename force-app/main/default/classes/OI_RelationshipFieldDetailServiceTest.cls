@isTest
private class OI_RelationshipFieldDetailServiceTest {
  @isTest
  static void testReturnsOnlyReferenceFieldsClassifiedAsLookupOrMasterDetailWithRequiredAndCardinality() {
    insert new List<OI_Graph_Node__c>{
      new OI_Graph_Node__c(
        Node_Key__c = 'plainField',
        Node_Version_Key__c = 'plainField::v1',
        Version_Number__c = 1,
        Node_Type__c = 'SalesforceMetadata.CustomField',
        Label__c = 'Name',
        Secondary_Key__c = 'TestObj.Name',
        Attributes_Json__c = '{"custom":false,"type":"STRING","nillable":true}',
        Checksum__c = 'c1',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'lookupField',
        Node_Version_Key__c = 'lookupField::v1',
        Version_Number__c = 1,
        Node_Type__c = 'SalesforceMetadata.CustomField',
        Label__c = 'Owner',
        Secondary_Key__c = 'TestObj.OwnerId',
        Attributes_Json__c = '{"custom":false,"type":"REFERENCE","nillable":true,"referenceTo":["User"],"masterDetail":false}',
        Checksum__c = 'c1',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'mdField',
        Node_Version_Key__c = 'mdField::v1',
        Version_Number__c = 1,
        Node_Type__c = 'SalesforceMetadata.CustomField',
        Label__c = 'Parent',
        Secondary_Key__c = 'TestObj.Parent__c',
        Attributes_Json__c = '{"custom":true,"type":"REFERENCE","nillable":false,"referenceTo":["Account"],"masterDetail":true}',
        Checksum__c = 'c1',
        State__c = 'Active',
        Is_Current__c = true
      )
    };
    insert new List<OI_Graph_Edge__c>{
      new OI_Graph_Edge__c(
        Edge_Key__c = 'rf1',
        Edge_Version_Key__c = 'rf1::v1',
        Version_Number__c = 1,
        Edge_Type__c = 'SalesforceMetadata.HAS_FIELD',
        Source_Node_Key__c = 'testObj',
        Target_Node_Key__c = 'plainField',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Edge__c(
        Edge_Key__c = 'rf2',
        Edge_Version_Key__c = 'rf2::v1',
        Version_Number__c = 1,
        Edge_Type__c = 'SalesforceMetadata.HAS_FIELD',
        Source_Node_Key__c = 'testObj',
        Target_Node_Key__c = 'lookupField',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Edge__c(
        Edge_Key__c = 'rf3',
        Edge_Version_Key__c = 'rf3::v1',
        Version_Number__c = 1,
        Edge_Type__c = 'SalesforceMetadata.HAS_FIELD',
        Source_Node_Key__c = 'testObj',
        Target_Node_Key__c = 'mdField',
        State__c = 'Active',
        Is_Current__c = true
      )
    };

    OI_RelationshipFieldDetailDTO result = new OI_RelationshipFieldDetailService()
      .getRelationshipFieldDetail('testObj');

    System.assertEquals(
      2,
      result.fields.size(),
      'The plain, non-reference field (Name) must never appear — only fields with a referenceTo.'
    );
    Map<String, OI_RelationshipFieldDTO> byApiName = new Map<String, OI_RelationshipFieldDTO>();
    for (OI_RelationshipFieldDTO field : result.fields) {
      byApiName.put(field.apiName, field);
    }

    OI_RelationshipFieldDTO lookup = byApiName.get('TestObj.OwnerId');
    System.assertNotEquals(null, lookup);
    System.assertEquals('Lookup', lookup.relationshipType);
    System.assertEquals(
      false,
      lookup.isRequired,
      'nillable=true must invert to isRequired=false.'
    );
    System.assertEquals(
      null,
      lookup.cascadeDeleteBehavior,
      'A Lookup\'s delete constraint is not Describe-accessible and must be left null, never guessed.'
    );
    System.assertEquals(1, lookup.targetObjects.size());
    System.assertEquals('User', lookup.targetObjects[0].objectApiName);
    System.assertNotEquals(
      null,
      lookup.targetObjects[0].recordCount,
      'User is always accessible/queryable, so its live count must resolve.'
    );

    OI_RelationshipFieldDTO masterDetail = byApiName.get('TestObj.Parent__c');
    System.assertNotEquals(null, masterDetail);
    System.assertEquals('Master-Detail', masterDetail.relationshipType);
    System.assertEquals(
      true,
      masterDetail.isRequired,
      'nillable=false must invert to isRequired=true.'
    );
    System.assertEquals(
      'Cascade',
      masterDetail.cascadeDeleteBehavior,
      'Master-Detail cascade-delete is a fixed platform invariant, always known.'
    );
    System.assertEquals('Account', masterDetail.targetObjects[0].objectApiName);

    System.assertEquals(false, result.cardinalityTruncated);
  }

  @isTest
  static void testReturnsEmptyForAnObjectWithNoReferenceFields() {
    insert new OI_Graph_Node__c(
      Node_Key__c = 'onlyPlainField',
      Node_Version_Key__c = 'onlyPlainField::v1',
      Version_Number__c = 1,
      Node_Type__c = 'SalesforceMetadata.CustomField',
      Label__c = 'Description',
      Secondary_Key__c = 'TestObj.Description__c',
      Attributes_Json__c = '{"custom":true,"type":"TEXTAREA","nillable":true}',
      Checksum__c = 'c1',
      State__c = 'Active',
      Is_Current__c = true
    );
    insert new OI_Graph_Edge__c(
      Edge_Key__c = 'rf4',
      Edge_Version_Key__c = 'rf4::v1',
      Version_Number__c = 1,
      Edge_Type__c = 'SalesforceMetadata.HAS_FIELD',
      Source_Node_Key__c = 'testObjNoRefs',
      Target_Node_Key__c = 'onlyPlainField',
      State__c = 'Active',
      Is_Current__c = true
    );

    OI_RelationshipFieldDetailDTO result = new OI_RelationshipFieldDetailService()
      .getRelationshipFieldDetail('testObjNoRefs');

    System.assertEquals(0, result.fields.size());
    System.assertEquals(false, result.cardinalityTruncated);
  }

  /**
   * A polymorphic field (WhatId/OwnerId-style) referencing multiple objects must keep every
   * target as its own row with its own independent record count — collapsing them into a
   * single number, as the old aggregate count did, is exactly what this rework replaces.
   */
  @isTest
  static void testPolymorphicFieldReturnsOneCardinalityRowPerTargetObject() {
    insert new OI_Graph_Node__c(
      Node_Key__c = 'polyField',
      Node_Version_Key__c = 'polyField::v1',
      Version_Number__c = 1,
      Node_Type__c = 'SalesforceMetadata.CustomField',
      Label__c = 'What Id',
      Secondary_Key__c = 'TestObj.WhatId',
      Attributes_Json__c = '{"custom":false,"type":"REFERENCE","nillable":true,"referenceTo":["Account","Opportunity"],"masterDetail":false}',
      Checksum__c = 'c1',
      State__c = 'Active',
      Is_Current__c = true
    );
    insert new OI_Graph_Edge__c(
      Edge_Key__c = 'rf5',
      Edge_Version_Key__c = 'rf5::v1',
      Version_Number__c = 1,
      Edge_Type__c = 'SalesforceMetadata.HAS_FIELD',
      Source_Node_Key__c = 'polyObj',
      Target_Node_Key__c = 'polyField',
      State__c = 'Active',
      Is_Current__c = true
    );

    OI_RelationshipFieldDetailDTO result = new OI_RelationshipFieldDetailService()
      .getRelationshipFieldDetail('polyObj');

    System.assertEquals(1, result.fields.size());
    System.assertEquals(
      2,
      result.fields[0].targetObjects.size(),
      'Account and Opportunity must both appear as their own rows, never merged into one count.'
    );
  }
}
