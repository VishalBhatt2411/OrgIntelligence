/**
 * Purpose: Verifies OI_MetadataNavigationService resolves real, correctly-shaped Setup
 *          navigation targets — with particular emphasis on the two identifier traps a real org
 *          audit confirmed: a relationship field's Setup route uses its DurableId suffix (which
 *          drops the "Id" from the field's own API name), and a custom object is addressed by
 *          EntityDefinition DurableId, never by its API name.
 *
 * Assertions run against this package's own real, already-deployed metadata (OI_GraphEngine,
 * OI_Graph_Edge__c, standard Account/Account.OwnerId) rather than fixtures, because the whole
 * point under test is durable-identifier resolution against the ACTUAL org schema — a synthetic
 * fixture would not exercise the real EntityDefinition/FieldDefinition data this depends on.
 */
@isTest
private class OI_MetadataNavigationServiceTest {
    @isTest
    static void testStandardObjectResolvesToObjectManagerByItsOwnApiName() {
        OI_NavigationTargetDTO target = new OI_MetadataNavigationService().resolve('SalesforceMetadata.CustomObject', 'Account');

        System.assertEquals(OI_NavigationTargetDTO.KIND_SETUP_PAGE, target.kind);
        System.assertEquals('/lightning/setup/ObjectManager/Account/Details/view', target.url, 'A standard object\'s DurableId happens to equal its API name — this must still resolve correctly, not by coincidence.');
    }

    /**
     * The custom-object trap: a hand-built URL using the API name would produce
     * ".../ObjectManager/OI_Graph_Edge__c/..." — wrong, and would 404 in a real org. The correct
     * address is the object's EntityDefinition DurableId, a synthetic id unrelated to its name.
     */
    @isTest
    static void testCustomObjectResolvesToItsEntityDefinitionDurableIdNeverItsApiName() {
        OI_NavigationTargetDTO target = new OI_MetadataNavigationService().resolve('SalesforceMetadata.CustomObject', 'OI_Graph_Edge__c');

        System.assertEquals(OI_NavigationTargetDTO.KIND_SETUP_PAGE, target.kind);
        System.assert(!target.url.contains('OI_Graph_Edge__c'), 'The URL must never contain the raw API name for a custom object — that is exactly the wrong-but-plausible mistake this service exists to prevent. Got: ' + target.url);
        List<EntityDefinition> definitions = [SELECT DurableId FROM EntityDefinition WHERE QualifiedApiName = 'OI_Graph_Edge__c' LIMIT 1];
        System.assertEquals('/lightning/setup/ObjectManager/' + definitions[0].DurableId + '/Details/view', target.url);
    }

    /**
     * The field trap, verified against the real org: Account.OwnerId's own FieldDefinition
     * DurableId is "Account.Owner" — the relationship name, with the "Id" suffix dropped. A URL
     * built from the field's own API name ("OwnerId") would be wrong and would 404.
     */
    @isTest
    static void testRelationshipFieldResolvesUsingItsDurableIdSuffixNotItsRawApiName() {
        OI_NavigationTargetDTO target = new OI_MetadataNavigationService().resolve('SalesforceMetadata.CustomField', 'Account.OwnerId');

        System.assertEquals(OI_NavigationTargetDTO.KIND_SETUP_PAGE, target.kind);
        List<FieldDefinition> definitions = [
            SELECT DurableId, EntityDefinitionId
            FROM FieldDefinition
            WHERE EntityDefinition.QualifiedApiName = 'Account' AND QualifiedApiName = 'OwnerId'
            LIMIT 1
        ];
        String expectedSuffix = definitions[0].DurableId.substringAfter(definitions[0].EntityDefinitionId + '.');
        System.assert(!expectedSuffix.equals('OwnerId'), 'Precondition: this test only proves something if the DurableId suffix genuinely differs from the raw API name.');
        System.assertEquals('/lightning/setup/ObjectManager/Account/FieldsAndRelationships/' + expectedSuffix + '/view', target.url);
    }

    @isTest
    static void testApexClassResolvesByRealId() {
        List<ApexClass> classes = [SELECT Id FROM ApexClass WHERE Name = 'OI_GraphEngine' LIMIT 1];
        System.assertEquals(1, classes.size(), 'Precondition: OI_GraphEngine must exist as a deployed class in this org.');

        OI_NavigationTargetDTO target = new OI_MetadataNavigationService().resolve('SalesforceMetadata.ApexClass', 'OI_GraphEngine');

        System.assertEquals(OI_NavigationTargetDTO.KIND_SETUP_PAGE, target.kind);
        System.assert(target.url.contains(classes[0].Id), 'The URL must address the class by its real Id. Got: ' + target.url);
    }

    @isTest
    static void testPermissionSetResolvesByRealId() {
        List<PermissionSet> permissionSets = [SELECT Id FROM PermissionSet WHERE Name = 'OI_Viewer' LIMIT 1];
        System.assertEquals(1, permissionSets.size(), 'Precondition: OI_Viewer must exist as a deployed permission set in this org.');

        OI_NavigationTargetDTO target = new OI_MetadataNavigationService().resolve('SalesforceMetadata.PermissionSet', 'OI_Viewer');

        System.assertEquals(OI_NavigationTargetDTO.KIND_SETUP_PAGE, target.kind);
        System.assert(target.url.contains(permissionSets[0].Id));
    }

    /** Flow Builder has no stable, Apex-queryable direct-navigation identifier — this must degrade to a working list page with an honest caveat, never a guessed link that might 404. */
    @isTest
    static void testFlowDegradesToTheFlowsListWithAnExplicitCaveatRatherThanAGuessedLink() {
        OI_NavigationTargetDTO target = new OI_MetadataNavigationService().resolve('SalesforceMetadata.Flow', 'AnyFlow');

        System.assertEquals(OI_NavigationTargetDTO.KIND_SETUP_PAGE, target.kind);
        System.assertEquals('/lightning/setup/Flows/home', target.url);
        System.assert(String.isNotBlank(target.reason), 'A caveated destination must always explain itself — landing somewhere other than the exact component must never look identical to a full success.');
    }

    @isTest
    static void testUnresolvableObjectReturnsUnsupportedWithAnHonestReasonRatherThanABrokenLink() {
        OI_NavigationTargetDTO target = new OI_MetadataNavigationService().resolve('SalesforceMetadata.CustomObject', 'ThisObjectDoesNotExist__c');

        System.assertEquals(OI_NavigationTargetDTO.KIND_UNSUPPORTED, target.kind);
        System.assertEquals(null, target.url, 'An unsupported target must carry no URL at all — never a link that would 404.');
        System.assert(String.isNotBlank(target.reason));
    }

    @isTest
    static void testAnUnrecognizedComponentKindIsUnsupportedNotAGuess() {
        OI_NavigationTargetDTO target = new OI_MetadataNavigationService().resolve('SalesforceMetadata.Report', 'AnyReport');

        System.assertEquals(OI_NavigationTargetDTO.KIND_UNSUPPORTED, target.kind);
    }

    @isTest
    static void testBlankInputsAreUnsupportedNotAnException() {
        OI_NavigationTargetDTO target = new OI_MetadataNavigationService().resolve(null, null);
        System.assertEquals(OI_NavigationTargetDTO.KIND_UNSUPPORTED, target.kind);
    }

    /** A namespaced Apex class name must resolve against the class's own bare Name field, which never carries the namespace prefix. */
    @isTest
    static void testNamespacedApexClassNameIsUnqualifiedBeforeLookup() {
        OI_NavigationTargetDTO target = new OI_MetadataNavigationService().resolve('SalesforceMetadata.ApexClass', 'SomeNamespace.OI_GraphEngine');

        System.assertEquals(OI_NavigationTargetDTO.KIND_SETUP_PAGE, target.kind, 'The namespace prefix must be stripped before matching Name, or a namespaced reference to a real local class would incorrectly resolve as unsupported.');
    }
}
