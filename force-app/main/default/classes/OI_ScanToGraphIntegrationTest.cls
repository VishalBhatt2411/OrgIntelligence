/**
 * Purpose: The end-to-end proof required by Sprint 8 §16 — Scanner-shaped Discovery Model
 *          -> Mutation Generator -> Graph Builder -> Graph Repository -> real, persisted
 *          OI_Graph_Node__c/OI_Graph_Edge__c rows — proving the graph actually contains
 *          Object -> Field -> referenced Object, not just that the in-memory pipeline
 *          produces the right Mutations.
 * Note: Uses realistic, hand-built Discovery Model fixtures (matching exactly what
 *       OI_ObjectScanner/OI_FieldScanner would emit for this slice — verified independently
 *       by OI_ObjectScannerTest/OI_FieldScannerTest against the real org schema) rather than
 *       invoking the real Describe-based Scanners for a full-org sweep in this test: a
 *       full-org OI_FieldScanner run can discover thousands of fields, and OI_GraphBuilder's
 *       per-key commitVersion cost (GraphRepository.md §11 — cannot be bulked across keys)
 *       would need many chunked Queueable hops to stay governor-safe at that scale (exactly
 *       what OI_ScanOrchestratorQueueable's chunking exists for). This test targets the
 *       specific, deterministic slice §16 asks to be proven, through the real (non-fake)
 *       Mutation Generator / Graph Builder / Graph Repository / Custom Object DML path,
 *       without the orchestration layer's chunking being a variable in this test's
 *       runtime. OI_ScanOrchestratorQueueableTest separately proves the full chain
 *       including real Scanner + Orchestrator chunking, scoped to ApexClass to stay fast.
 */
@isTest
private class OI_ScanToGraphIntegrationTest {
    @isTest
    static void testObjectFieldAndReferenceGraphIsPersistedEndToEnd() {
        String accountKey = OI_ComponentKeyUtil.build('CustomObject', null, 'Account');
        String ownerKey = OI_ComponentKeyUtil.build('CustomObject', null, 'User');
        String nameFieldKey = OI_ComponentKeyUtil.build('CustomField', null, 'Account.Name');
        String ownerFieldKey = OI_ComponentKeyUtil.build('CustomField', null, 'Account.OwnerId');

        OI_DiscoveredComponent accountComponent = new OI_DiscoveredComponent(
            accountKey,
            'CustomObject',
            'Account',
            null,
            'Describe',
            new Map<String, Object>{ 'custom' => false, 'label' => 'Account' },
            'accChecksum',
            null,
            null
        );
        OI_MutationGenerator objectGenerator = new OI_MutationGenerator();
        objectGenerator.translateAndIngest(
            new OI_DiscoveryBatch(null, 'CustomObject', new List<OI_DiscoveredComponent>{ accountComponent }, new List<OI_DiscoveredRelationship>(), true, 1)
        );

        OI_DiscoveredComponent nameField = new OI_DiscoveredComponent(
            nameFieldKey,
            'CustomField',
            'Account.Name',
            null,
            'Describe',
            new Map<String, Object>{ 'type' => 'STRING', 'label' => 'Account Name' },
            'nameChecksum',
            null,
            accountKey
        );
        OI_DiscoveredComponent ownerField = new OI_DiscoveredComponent(
            ownerFieldKey,
            'CustomField',
            'Account.OwnerId',
            null,
            'Describe',
            new Map<String, Object>{ 'type' => 'REFERENCE', 'label' => 'Owner ID' },
            'ownerChecksum',
            null,
            accountKey
        );
        OI_DiscoveredRelationship hasNameField = new OI_DiscoveredRelationship(
            OI_HashUtil.hash(accountKey + '::HAS_FIELD::' + nameFieldKey),
            'HAS_FIELD',
            accountKey,
            nameFieldKey,
            new Map<String, Object>()
        );
        OI_DiscoveredRelationship hasOwnerField = new OI_DiscoveredRelationship(
            OI_HashUtil.hash(accountKey + '::HAS_FIELD::' + ownerFieldKey),
            'HAS_FIELD',
            accountKey,
            ownerFieldKey,
            new Map<String, Object>()
        );
        OI_DiscoveredRelationship ownerLookupToUser = new OI_DiscoveredRelationship(
            OI_HashUtil.hash(ownerFieldKey + '::LOOKUP_TO::' + ownerKey),
            'LOOKUP_TO',
            ownerFieldKey,
            ownerKey,
            new Map<String, Object>{ 'relationshipName' => 'Owner' }
        );

        OI_MutationGenerator fieldGenerator = new OI_MutationGenerator();
        fieldGenerator.translateAndIngest(
            new OI_DiscoveryBatch(
                null,
                'CustomField',
                new List<OI_DiscoveredComponent>{ nameField, ownerField },
                new List<OI_DiscoveredRelationship>{ hasNameField, hasOwnerField, ownerLookupToUser },
                true,
                1
            )
        );

        List<OI_Graph_Node__c> accountNodes = [
            SELECT Node_Key__c
            FROM OI_Graph_Node__c
            WHERE Node_Type__c = 'SalesforceMetadata.CustomObject' AND Secondary_Key__c = 'Account' AND Is_Current__c = true
        ];
        System.assertEquals(1, accountNodes.size(), 'Expected exactly one current Account node.');
        String accountNodeKey = accountNodes[0].Node_Key__c;

        List<OI_Graph_Node__c> nameFieldNodes = [
            SELECT Node_Key__c, Parent_Key__c, Label__c
            FROM OI_Graph_Node__c
            WHERE Node_Type__c = 'SalesforceMetadata.CustomField' AND Secondary_Key__c = 'Account.Name' AND Is_Current__c = true
        ];
        System.assertEquals(1, nameFieldNodes.size());
        System.assertEquals(accountNodeKey, nameFieldNodes[0].Parent_Key__c, 'Account.Name must carry Account as its parentKey.');
        System.assertEquals('Account Name', nameFieldNodes[0].Label__c, 'Label__c must be the friendly Describe label, distinct from the API name already carried in Secondary_Key__c.');

        Integer hasFieldEdgeCount = [
            SELECT COUNT()
            FROM OI_Graph_Edge__c
            WHERE Edge_Type__c = 'SalesforceMetadata.HAS_FIELD' AND Source_Node_Key__c = :accountNodeKey AND Is_Current__c = true
        ];
        System.assertEquals(2, hasFieldEdgeCount, 'Account must have exactly two persisted HAS_FIELD edges (Name, OwnerId).');

        String ownerFieldNodeKey = [
            SELECT Node_Key__c
            FROM OI_Graph_Node__c
            WHERE Node_Type__c = 'SalesforceMetadata.CustomField' AND Secondary_Key__c = 'Account.OwnerId' AND Is_Current__c = true
        ][0]
        .Node_Key__c;

        Integer lookupEdgeCount = [
            SELECT COUNT()
            FROM OI_Graph_Edge__c
            WHERE Edge_Type__c = 'SalesforceMetadata.LOOKUP_TO' AND Source_Node_Key__c = :ownerFieldNodeKey
        ];
        System.assert(lookupEdgeCount > 0, 'Account.OwnerId must have a persisted LOOKUP_TO edge, proving Field -> referenced Object graph data exists.');
    }

    @isTest
    static void testRepeatingTheSameScanDoesNotDuplicateTheAccountNode() {
        OI_DiscoveredComponent accountComponent = new OI_DiscoveredComponent(
            OI_ComponentKeyUtil.build('CustomObject', null, 'Account'),
            'CustomObject',
            'Account',
            null,
            'Describe',
            new Map<String, Object>{ 'custom' => false },
            'stableChecksum',
            null,
            null
        );
        OI_DiscoveryBatch batch = new OI_DiscoveryBatch(
            null,
            'CustomObject',
            new List<OI_DiscoveredComponent>{ accountComponent },
            new List<OI_DiscoveredRelationship>(),
            true,
            1
        );

        new OI_MutationGenerator().translateAndIngest(batch);
        new OI_MutationGenerator().translateAndIngest(batch);

        Integer currentAccountNodeCount = [
            SELECT COUNT()
            FROM OI_Graph_Node__c
            WHERE Node_Type__c = 'SalesforceMetadata.CustomObject' AND Secondary_Key__c = 'Account' AND Is_Current__c = true
        ];
        System.assertEquals(1, currentAccountNodeCount, 'Scanning the same unchanged component twice must not create a second current node.');
    }
}
