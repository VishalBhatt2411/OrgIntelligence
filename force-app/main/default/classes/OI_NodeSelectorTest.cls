/**
 * Purpose: Verifies OI_NodeSelector's bulk, key-set-shaped reads and Is_Current__c
 *          centralization (CodingStandards.md §4).
 */
@isTest
private class OI_NodeSelectorTest {
    @isTest
    static void testSelectCurrentByKeysReturnsOnlyCurrentRows() {
        insert new List<OI_Graph_Node__c>{
            new OI_Graph_Node__c(Node_Key__c = 'n1', Node_Version_Key__c = 'n1::v1', Version_Number__c = 1, Node_Type__c = 'T', State__c = 'Active', Is_Current__c = false),
            new OI_Graph_Node__c(Node_Key__c = 'n1', Node_Version_Key__c = 'n1::v2', Version_Number__c = 2, Node_Type__c = 'T', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Node__c(Node_Key__c = 'n2', Node_Version_Key__c = 'n2::v1', Version_Number__c = 1, Node_Type__c = 'T', State__c = 'Active', Is_Current__c = true)
        };
        List<OI_Graph_Node__c> results = new OI_NodeSelector().selectCurrentByKeys(new Set<String>{ 'n1', 'n2' });
        System.assertEquals(2, results.size());
        for (OI_Graph_Node__c row : results) {
            System.assertEquals(true, row.Is_Current__c);
        }
    }

    @isTest
    static void testSelectCurrentByKeysEmptySetReturnsEmpty() {
        System.assertEquals(0, new OI_NodeSelector().selectCurrentByKeys(new Set<String>()).size());
    }

    @isTest
    static void testSelectCurrentKeysByTypePagination() {
        List<OI_Graph_Node__c> rows = new List<OI_Graph_Node__c>();
        for (Integer i = 0; i < 5; i++) {
            rows.add(new OI_Graph_Node__c(Node_Key__c = 'p' + i, Node_Version_Key__c = 'p' + i + '::v1', Version_Number__c = 1, Node_Type__c = 'Paginated.Type', State__c = 'Active', Is_Current__c = true));
        }
        insert rows;
        List<OI_Graph_Node__c> page1 = new OI_NodeSelector().selectCurrentKeysByType('Paginated.Type', null, 2);
        System.assertEquals(2, page1.size());
        List<OI_Graph_Node__c> page2 = new OI_NodeSelector().selectCurrentKeysByType('Paginated.Type', page1[1].Node_Version_Key__c, 2);
        System.assertEquals(2, page2.size());
        System.assertNotEquals(page1[0].Node_Version_Key__c, page2[0].Node_Version_Key__c);
    }

    @isTest
    static void testSelectCurrentByLabelOrSecondaryKeyPrefixMatchesEitherFieldCaseOfCurrentRowsOnly() {
        insert new List<OI_Graph_Node__c>{
            new OI_Graph_Node__c(Node_Key__c = 's1', Node_Version_Key__c = 's1::v1', Version_Number__c = 1, Node_Type__c = 'T', Label__c = 'Account', Secondary_Key__c = 'Account', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Node__c(Node_Key__c = 's2', Node_Version_Key__c = 's2::v1', Version_Number__c = 1, Node_Type__c = 'T', Label__c = 'AccountContactRoles', Secondary_Key__c = 'AccountContactRoles', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Node__c(Node_Key__c = 's3', Node_Version_Key__c = 's3::v1', Version_Number__c = 1, Node_Type__c = 'T', Label__c = 'Contact', Secondary_Key__c = 'Contact', State__c = 'Active', Is_Current__c = true),
            new OI_Graph_Node__c(Node_Key__c = 's1', Node_Version_Key__c = 's1::v0', Version_Number__c = 0, Node_Type__c = 'T', Label__c = 'Account', Secondary_Key__c = 'Account', State__c = 'Stale', Is_Current__c = false)
        };
        List<OI_Graph_Node__c> results = new OI_NodeSelector().selectCurrentByLabelOrSecondaryKeyPrefix('Account', 20);
        System.assertEquals(2, results.size(), 'Only current rows matching the prefix (Account, AccountContactRoles) must be returned — Contact must not match, the Stale duplicate must not be returned.');
    }

    @isTest
    static void testBulkInsertAndSelect() {
        List<OI_Graph_Node__c> rows = new List<OI_Graph_Node__c>();
        Set<String> keys = new Set<String>();
        for (Integer i = 0; i < 200; i++) {
            String key = 'bulk' + i;
            keys.add(key);
            rows.add(new OI_Graph_Node__c(Node_Key__c = key, Node_Version_Key__c = key + '::v1', Version_Number__c = 1, Node_Type__c = 'Bulk.Type', State__c = 'Active', Is_Current__c = true));
        }
        insert rows;
        System.assertEquals(200, new OI_NodeSelector().selectCurrentByKeys(keys).size());
    }
}
