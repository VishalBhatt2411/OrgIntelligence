/**
 * Purpose: Verifies OI_GraphController's thin permission-check -> call -> DTO-map contract
 *          (API.md §2.1).
 */
@isTest
private class OI_GraphControllerTest {
    @isTest
    static void testGetGraphFragmentReturnsTheCenterNodeForAZeroHopFetch() {
        insert new OI_Graph_Node__c(
            Node_Key__c = 'ctrl1',
            Node_Version_Key__c = 'ctrl1::v1',
            Version_Number__c = 1,
            Node_Type__c = 'SalesforceMetadata.TestType',
            Label__c = 'Ctrl1',
            Secondary_Key__c = 'Sec.Ctrl1',
            Checksum__c = 'c1',
            State__c = 'Active',
            Is_Current__c = true
        );

        OI_GraphFragmentDTO result = OI_GraphController.getGraphFragment('ctrl1', 0, null, new Map<String, String>());

        System.assertEquals(1, result.nodes.size());
        System.assertEquals('ctrl1', result.nodes[0].nodeKey);
        System.assertEquals('Ctrl1', result.nodes[0].label);
    }

    @isTest
    static void testGetNodeDetailReturnsFullAttributes() {
        insert new OI_Graph_Node__c(
            Node_Key__c = 'detail1',
            Node_Version_Key__c = 'detail1::v1',
            Version_Number__c = 1,
            Node_Type__c = 'SalesforceMetadata.TestType',
            Label__c = 'Detail1',
            Secondary_Key__c = 'Sec.Detail1',
            Attributes_Json__c = '{"custom":true}',
            Checksum__c = 'c1',
            State__c = 'Active',
            Is_Current__c = true
        );

        OI_NodeDetailDTO result = OI_GraphController.getNodeDetail('detail1');

        System.assertEquals('detail1', result.nodeKey);
        System.assertEquals('Detail1', result.label);
        System.assertEquals(true, result.attributes.get('custom'));
    }

    @isTest
    static void testGetNodeDetailIncludesRelationshipCountsFromRealEdges() {
        insert new OI_Graph_Node__c(
            Node_Key__c = 'detail2',
            Node_Version_Key__c = 'detail2::v1',
            Version_Number__c = 1,
            Node_Type__c = 'SalesforceMetadata.TestType',
            Label__c = 'Detail2',
            Secondary_Key__c = 'Sec.Detail2',
            Checksum__c = 'c1',
            State__c = 'Active',
            Is_Current__c = true
        );
        insert new List<OI_Graph_Edge__c>{
            new OI_Graph_Edge__c(Edge_Key__c = 'gc1', Edge_Version_Key__c = 'gc1::v1', Version_Number__c = 1, Edge_Type__c = 'SalesforceMetadata.HAS_FIELD', Source_Node_Key__c = 'detail2', Target_Node_Key__c = 'someField', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Edge__c(Edge_Key__c = 'gc2', Edge_Version_Key__c = 'gc2::v1', Version_Number__c = 1, Edge_Type__c = 'SalesforceMetadata.LOOKUP_TO', Source_Node_Key__c = 'someOtherField', Target_Node_Key__c = 'detail2', State__c = 'Active', Is_Current__c = true)
        };

        OI_NodeDetailDTO result = OI_GraphController.getNodeDetail('detail2');

        System.assertEquals(1, result.outgoingRelationshipCounts.get('SalesforceMetadata.HAS_FIELD'));
        System.assertEquals(1, result.incomingRelationshipCounts.get('SalesforceMetadata.LOOKUP_TO'));
        System.assertEquals(2, result.directConnectionCount, 'directConnectionCount must be the honest sum of only real, structural edges — never a fabricated impact/dependency figure.');
    }

    @isTest
    static void testGetNodeDetailForUnknownKeyThrowsAuraHandledException() {
        try {
            OI_GraphController.getNodeDetail('doesNotExist');
            System.assert(false, 'Expected AuraHandledException for an unknown node key.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testGetFieldSummariesReturnsOnlyThisObjectsOwnFieldsWithParsedAttributes() {
        insert new List<OI_Graph_Node__c>{
            new OI_Graph_Node__c(
                Node_Key__c = 'acctField1',
                Node_Version_Key__c = 'acctField1::v1',
                Version_Number__c = 1,
                Node_Type__c = 'SalesforceMetadata.CustomField',
                Label__c = 'Account Name',
                Secondary_Key__c = 'Account.Name',
                Attributes_Json__c = '{"custom":false,"type":"STRING","nillable":false}',
                Checksum__c = 'c1',
                State__c = 'Active',
                Is_Current__c = true
            ),
            new OI_Graph_Node__c(
                Node_Key__c = 'acctField2',
                Node_Version_Key__c = 'acctField2::v1',
                Version_Number__c = 1,
                Node_Type__c = 'SalesforceMetadata.CustomField',
                Label__c = 'Favorite Color',
                Secondary_Key__c = 'Account.Favorite_Color__c',
                Attributes_Json__c = '{"custom":true,"type":"PICKLIST","nillable":true}',
                Checksum__c = 'c1',
                State__c = 'Active',
                Is_Current__c = true
            ),
            new OI_Graph_Node__c(
                Node_Key__c = 'contactField1',
                Node_Version_Key__c = 'contactField1::v1',
                Version_Number__c = 1,
                Node_Type__c = 'SalesforceMetadata.CustomField',
                Label__c = 'Account Id',
                Secondary_Key__c = 'Contact.AccountId',
                Attributes_Json__c = '{"custom":false,"type":"REFERENCE","nillable":true,"referenceTo":["Account"]}',
                Checksum__c = 'c1',
                State__c = 'Active',
                Is_Current__c = true
            )
        };
        insert new List<OI_Graph_Edge__c>{
            new OI_Graph_Edge__c(Edge_Key__c = 'fs1', Edge_Version_Key__c = 'fs1::v1', Version_Number__c = 1, Edge_Type__c = 'SalesforceMetadata.HAS_FIELD', Source_Node_Key__c = 'acctObj', Target_Node_Key__c = 'acctField1', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Edge__c(Edge_Key__c = 'fs2', Edge_Version_Key__c = 'fs2::v1', Version_Number__c = 1, Edge_Type__c = 'SalesforceMetadata.HAS_FIELD', Source_Node_Key__c = 'acctObj', Target_Node_Key__c = 'acctField2', State__c = 'Active', Is_Current__c = true),
            // A field belonging to a DIFFERENT object that merely references acctObj — must never appear in acctObj's own field list.
            new OI_Graph_Edge__c(Edge_Key__c = 'fs3', Edge_Version_Key__c = 'fs3::v1', Version_Number__c = 1, Edge_Type__c = 'SalesforceMetadata.HAS_FIELD', Source_Node_Key__c = 'contactObj', Target_Node_Key__c = 'contactField1', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Edge__c(Edge_Key__c = 'fs4', Edge_Version_Key__c = 'fs4::v1', Version_Number__c = 1, Edge_Type__c = 'SalesforceMetadata.LOOKUP_TO', Source_Node_Key__c = 'contactField1', Target_Node_Key__c = 'acctObj', State__c = 'Active', Is_Current__c = true)
        };

        List<OI_FieldSummaryDTO> summaries = OI_GraphController.getFieldSummaries('acctObj');

        Map<String, OI_FieldSummaryDTO> byKey = new Map<String, OI_FieldSummaryDTO>();
        for (OI_FieldSummaryDTO summary : summaries) {
            byKey.put(summary.nodeKey, summary);
        }
        System.assertEquals(2, summaries.size(), 'Only acctObj\'s own HAS_FIELD-sourced fields must be returned — never contactField1, which merely references acctObj.');
        System.assert(!byKey.containsKey('contactField1'));

        OI_FieldSummaryDTO standardField = byKey.get('acctField1');
        System.assertEquals('Account Name', standardField.label);
        System.assertEquals('Account.Name', standardField.apiName);
        System.assertEquals('STRING', standardField.dataType);
        System.assertEquals(false, standardField.isCustom);
        System.assertEquals(true, standardField.isRequired, 'nillable=false must invert to isRequired=true.');

        OI_FieldSummaryDTO customField = byKey.get('acctField2');
        System.assertEquals(true, customField.isCustom);
        System.assertEquals(false, customField.isRequired);
    }

    @isTest
    static void testGetFieldSummariesReturnsEmptyListForAnObjectWithNoFields() {
        List<OI_FieldSummaryDTO> summaries = OI_GraphController.getFieldSummaries('objectWithNoFields');
        System.assertEquals(0, summaries.size());
    }

    @isTest
    static void testGetFieldSummariesWithoutPermissionThrowsAuraHandledException() {
        User unprivileged = createUnprivilegedTestUser();
        System.runAs(unprivileged) {
            try {
                OI_GraphController.getFieldSummaries('anyKey');
                System.assert(false, 'Expected AuraHandledException when OI_View_Graph is not assigned.');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    @isTest
    static void testGetGraphFragmentWithoutPermissionThrowsAuraHandledException() {
        User unprivileged = createUnprivilegedTestUser();
        System.runAs(unprivileged) {
            try {
                OI_GraphController.getGraphFragment('anyKey', 0, null, new Map<String, String>());
                System.assert(false, 'Expected AuraHandledException when OI_View_Graph is not assigned.');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    private static User createUnprivilegedTestUser() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniqueSuffix = String.valueOf(Crypto.getRandomInteger()).right(8);
        User u = new User(
            FirstName = 'OI Test',
            LastName = 'Unprivileged' + uniqueSuffix,
            Email = 'oi.test.' + uniqueSuffix + '@example.invalid',
            Username = 'oi.test.' + uniqueSuffix + '@example.invalid',
            Alias = 'oitst' + uniqueSuffix.left(3),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = standardProfile.Id
        );
        insert u;
        return u;
    }
}
