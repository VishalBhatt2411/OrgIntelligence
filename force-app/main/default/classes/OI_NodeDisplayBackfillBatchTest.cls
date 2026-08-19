/**
 * Purpose: Verifies OI_NodeDisplayBackfillBatch corrects exactly Label__c/Attributes_Json__c/
 *          Checksum__c on already-scanned current CustomObject/CustomField rows, never
 *          touches identity/topology fields, never touches out-of-scope rows, and is
 *          idempotent across repeated runs.
 */
@isTest
private class OI_NodeDisplayBackfillBatchTest {
    @isTest
    static void testBackfillsFriendlyLabelForCustomFieldNode() {
        OI_Graph_Node__c fieldNode = insertNode(
            'field1',
            'SalesforceMetadata.CustomField',
            'Account.OwnerId',
            'Account.OwnerId',
            '{"label":"Owner ID","type":"REFERENCE"}',
            'preFixChecksum',
            true
        );

        Test.startTest();
        Database.executeBatch(new OI_NodeDisplayBackfillBatch(), 200);
        Test.stopTest();

        OI_Graph_Node__c result = [SELECT Label__c, Checksum__c, Node_Key__c, Version_Number__c, Is_Current__c FROM OI_Graph_Node__c WHERE Id = :fieldNode.Id];
        System.assertEquals('Owner ID', result.Label__c, 'Label__c must be corrected to the friendly Describe label already in Attributes_Json__c.');
        System.assertEquals('preFixChecksum', result.Checksum__c, 'Checksum__c must not change for a label-only fix — label was always part of the attributes the checksum already covers.');
        System.assertEquals('field1', result.Node_Key__c, 'Node_Key__c (graph identity) must be untouched.');
        System.assertEquals(1, result.Version_Number__c, 'Version_Number__c must be untouched — no new version created.');
        System.assertEquals(true, result.Is_Current__c);
    }

    @isTest
    static void testBackfillsFriendlyLabelForCustomObjectNode() {
        OI_Graph_Node__c objectNode = insertNode(
            'obj1',
            'SalesforceMetadata.CustomObject',
            'MyCustomThing__c',
            'MyCustomThing__c',
            '{"label":"My Custom Thing","custom":true,"namespace":null}',
            'objChecksum',
            true
        );

        Test.startTest();
        Database.executeBatch(new OI_NodeDisplayBackfillBatch(), 200);
        Test.stopTest();

        OI_Graph_Node__c result = [SELECT Label__c FROM OI_Graph_Node__c WHERE Id = :objectNode.Id];
        System.assertEquals('My Custom Thing', result.Label__c);
    }

    @isTest
    static void testBackfillsNamespaceForCustomObjectNodeMissingIt() {
        Map<String, Object> originalAttributes = new Map<String, Object>{ 'label' => 'Account', 'custom' => false };
        OI_Graph_Node__c objectNode = insertNode('obj2', 'SalesforceMetadata.CustomObject', 'Account', 'Account', JSON.serialize(originalAttributes), 'staleChecksum', true);

        Test.startTest();
        Database.executeBatch(new OI_NodeDisplayBackfillBatch(), 200);
        Test.stopTest();

        OI_Graph_Node__c result = [SELECT Attributes_Json__c, Checksum__c FROM OI_Graph_Node__c WHERE Id = :objectNode.Id];
        Map<String, Object> updatedAttributes = OI_JsonUtil.toMap(result.Attributes_Json__c);
        System.assert(updatedAttributes.containsKey('namespace'), 'Attributes_Json__c must gain a namespace key.');
        System.assertEquals(null, updatedAttributes.get('namespace'), 'Account is unpackaged/standard — namespace must resolve to null.');

        String expectedChecksum = OI_ChecksumUtil.computeChecksum('CustomObject', 'Account', updatedAttributes);
        System.assertEquals(expectedChecksum, result.Checksum__c, 'Checksum__c must be recomputed to match the corrected attributes, so a future real scan sees no spurious diff.');
        System.assertNotEquals('staleChecksum', result.Checksum__c);
    }

    @isTest
    static void testDoesNotTouchNonCurrentRows() {
        OI_Graph_Node__c staleNode = insertNode('field2', 'SalesforceMetadata.CustomField', 'Account.ParentId', 'Account.ParentId', '{"label":"Parent Account ID"}', 'c', false);

        Test.startTest();
        Database.executeBatch(new OI_NodeDisplayBackfillBatch(), 200);
        Test.stopTest();

        OI_Graph_Node__c result = [SELECT Label__c FROM OI_Graph_Node__c WHERE Id = :staleNode.Id];
        System.assertEquals('Account.ParentId', result.Label__c, 'A non-current (historical) version must never be touched by this backfill.');
    }

    @isTest
    static void testDoesNotTouchUnrelatedNodeTypes() {
        OI_Graph_Node__c apexNode = insertNode('apex1', 'SalesforceMetadata.ApexClass', 'MyClass', 'MyClass', '{"status":"Active"}', 'c', true);

        Test.startTest();
        Database.executeBatch(new OI_NodeDisplayBackfillBatch(), 200);
        Test.stopTest();

        OI_Graph_Node__c result = [SELECT Label__c FROM OI_Graph_Node__c WHERE Id = :apexNode.Id];
        System.assertEquals('MyClass', result.Label__c, 'ApexClass nodes are out of scope for this backfill — never had a distinct friendly label to begin with.');
    }

    /**
     * Idempotency is proven by construction: this seeds rows already in exactly the state
     * the first real run leaves behind (Label__c already equal to attributes.label; a
     * CustomObject's attributes already carrying 'namespace') and asserts nothing about
     * those rows changes and no duplicate row appears for either Node_Key__c — i.e. running
     * the fix again (or for the first time against data that's already correct) is a
     * genuine no-op, never a duplicate write. (Database.Stateful counters on the client-held
     * batch instance are not asserted on directly — Batch Apex reconstructs the Batchable
     * instance server-side even within test context, so the persisted row state, not the
     * original reference's fields, is the reliable signal.)
     */
    @isTest
    static void testRunningAgainstAlreadyCorrectDataUpdatesNothing() {
        insertNode('field3', 'SalesforceMetadata.CustomField', 'Account.OwnerId', 'Owner ID', '{"label":"Owner ID"}', 'c1', true);
        insertNode('obj3', 'SalesforceMetadata.CustomObject', 'Account', 'Account', '{"label":"Account","custom":false,"namespace":null}', 'c2', true);

        Test.startTest();
        Database.executeBatch(new OI_NodeDisplayBackfillBatch(), 200);
        Test.stopTest();

        List<OI_Graph_Node__c> fieldRows = [SELECT Label__c, Attributes_Json__c, Checksum__c FROM OI_Graph_Node__c WHERE Node_Key__c = 'field3'];
        System.assertEquals(1, fieldRows.size(), 'No duplicate row must be created for an already-correct Node_Key__c.');
        System.assertEquals('Owner ID', fieldRows[0].Label__c);
        System.assertEquals('c1', fieldRows[0].Checksum__c);

        List<OI_Graph_Node__c> objectRows = [SELECT Label__c, Attributes_Json__c, Checksum__c FROM OI_Graph_Node__c WHERE Node_Key__c = 'obj3'];
        System.assertEquals(1, objectRows.size(), 'No duplicate row must be created for an already-correct Node_Key__c.');
        System.assertEquals('Account', objectRows[0].Label__c);
        System.assertEquals('c2', objectRows[0].Checksum__c, 'Checksum__c must not be recomputed when namespace is already present.');
    }

    private static OI_Graph_Node__c insertNode(String nodeKey, String typeKey, String secondaryKey, String label, String attributesJson, String checksum, Boolean isCurrent) {
        OI_Graph_Node__c node = new OI_Graph_Node__c(
            Node_Key__c = nodeKey,
            Node_Version_Key__c = nodeKey + '::v1',
            Version_Number__c = 1,
            Node_Type__c = typeKey,
            Label__c = label,
            Secondary_Key__c = secondaryKey,
            Attributes_Json__c = attributesJson,
            Checksum__c = checksum,
            State__c = 'Active',
            Is_Current__c = isCurrent
        );
        insert node;
        return node;
    }
}
