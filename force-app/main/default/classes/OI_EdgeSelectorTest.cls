/**
 * Purpose: Verifies OI_EdgeSelector's bulk, key-set-shaped reads (CodingStandards.md §4).
 */
@isTest
private class OI_EdgeSelectorTest {
    @isTest
    static void testSelectCurrentByKeysReturnsOnlyCurrentRows() {
        insert new List<OI_Graph_Edge__c>{
            new OI_Graph_Edge__c(Edge_Key__c = 'e1', Edge_Version_Key__c = 'e1::v1', Version_Number__c = 1, Edge_Type__c = 'T', Source_Node_Key__c = 's', Target_Node_Key__c = 't', State__c = 'Active', Is_Current__c = false),
            new OI_Graph_Edge__c(Edge_Key__c = 'e1', Edge_Version_Key__c = 'e1::v2', Version_Number__c = 2, Edge_Type__c = 'T', Source_Node_Key__c = 's', Target_Node_Key__c = 't', State__c = 'Active', Is_Current__c = true)
        };
        List<OI_Graph_Edge__c> results = new OI_EdgeSelector().selectCurrentByKeys(new Set<String>{ 'e1' });
        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].Is_Current__c);
    }

    @isTest
    static void testSelectCurrentBySourceAndTargetKeys() {
        insert new OI_Graph_Edge__c(Edge_Key__c = 'e2', Edge_Version_Key__c = 'e2::v1', Version_Number__c = 1, Edge_Type__c = 'T', Source_Node_Key__c = 'srcA', Target_Node_Key__c = 'tgtA', State__c = 'Active', Is_Current__c = true);
        System.assertEquals(1, new OI_EdgeSelector().selectCurrentBySourceKeys(new Set<String>{ 'srcA' }).size());
        System.assertEquals(1, new OI_EdgeSelector().selectCurrentByTargetKeys(new Set<String>{ 'tgtA' }).size());
    }

    @isTest
    static void testSelectCurrentKeysByTypePagination() {
        List<OI_Graph_Edge__c> rows = new List<OI_Graph_Edge__c>();
        for (Integer i = 0; i < 5; i++) {
            rows.add(new OI_Graph_Edge__c(Edge_Key__c = 'p' + i, Edge_Version_Key__c = 'p' + i + '::v1', Version_Number__c = 1, Edge_Type__c = 'Paginated.Type', Source_Node_Key__c = 's', Target_Node_Key__c = 't', State__c = 'Active', Is_Current__c = true));
        }
        insert rows;
        List<OI_Graph_Edge__c> page1 = new OI_EdgeSelector().selectCurrentKeysByType('Paginated.Type', null, 2);
        System.assertEquals(2, page1.size());
    }

    @isTest
    static void testEmptySetsReturnEmpty() {
        OI_EdgeSelector selector = new OI_EdgeSelector();
        System.assertEquals(0, selector.selectCurrentByKeys(new Set<String>()).size());
        System.assertEquals(0, selector.selectCurrentBySourceKeys(new Set<String>()).size());
        System.assertEquals(0, selector.selectCurrentByTargetKeys(new Set<String>()).size());
    }

    @isTest
    static void testCountCurrentBySourceKeyGroupedByType() {
        insert new List<OI_Graph_Edge__c>{
            new OI_Graph_Edge__c(Edge_Key__c = 'ce1', Edge_Version_Key__c = 'ce1::v1', Version_Number__c = 1, Edge_Type__c = 'SalesforceMetadata.HAS_FIELD', Source_Node_Key__c = 'objA', Target_Node_Key__c = 'fieldA', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Edge__c(Edge_Key__c = 'ce2', Edge_Version_Key__c = 'ce2::v1', Version_Number__c = 1, Edge_Type__c = 'SalesforceMetadata.HAS_FIELD', Source_Node_Key__c = 'objA', Target_Node_Key__c = 'fieldB', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Edge__c(Edge_Key__c = 'ce3', Edge_Version_Key__c = 'ce3::v1', Version_Number__c = 1, Edge_Type__c = 'SalesforceMetadata.LOOKUP_TO', Source_Node_Key__c = 'objA', Target_Node_Key__c = 'objB', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Edge__c(Edge_Key__c = 'ce4', Edge_Version_Key__c = 'ce4::v1', Version_Number__c = 1, Edge_Type__c = 'SalesforceMetadata.HAS_FIELD', Source_Node_Key__c = 'objA', Target_Node_Key__c = 'fieldC', State__c = 'Active', Is_Current__c = false)
        };

        Map<String, Integer> counts = new OI_EdgeSelector().countCurrentBySourceKeyGroupedByType('objA');

        System.assertEquals(2, counts.get('SalesforceMetadata.HAS_FIELD'), 'Expected only the two current HAS_FIELD edges to be counted, excluding the non-current one.');
        System.assertEquals(1, counts.get('SalesforceMetadata.LOOKUP_TO'));
    }

    @isTest
    static void testCountCurrentByTargetKeyGroupedByType() {
        insert new List<OI_Graph_Edge__c>{
            new OI_Graph_Edge__c(Edge_Key__c = 'ce5', Edge_Version_Key__c = 'ce5::v1', Version_Number__c = 1, Edge_Type__c = 'SalesforceMetadata.LOOKUP_TO', Source_Node_Key__c = 'fieldD', Target_Node_Key__c = 'objTarget', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Edge__c(Edge_Key__c = 'ce6', Edge_Version_Key__c = 'ce6::v1', Version_Number__c = 1, Edge_Type__c = 'SalesforceMetadata.MASTER_DETAIL_TO', Source_Node_Key__c = 'fieldE', Target_Node_Key__c = 'objTarget', State__c = 'Active', Is_Current__c = true)
        };

        Map<String, Integer> counts = new OI_EdgeSelector().countCurrentByTargetKeyGroupedByType('objTarget');

        System.assertEquals(1, counts.get('SalesforceMetadata.LOOKUP_TO'));
        System.assertEquals(1, counts.get('SalesforceMetadata.MASTER_DETAIL_TO'));
    }

    @isTest
    static void testCountGroupedByTypeReturnsEmptyMapForBlankKey() {
        OI_EdgeSelector selector = new OI_EdgeSelector();
        System.assertEquals(0, selector.countCurrentBySourceKeyGroupedByType(null).size());
        System.assertEquals(0, selector.countCurrentByTargetKeyGroupedByType('').size());
    }
}
