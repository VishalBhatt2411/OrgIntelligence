/**
 * Purpose: Verifies OI_PermissionSetScanner (Backlog DE-11) discovers Permission Sets, emits
 *          exact GRANTS_ACCESS_TO edges toward the objects and Apex classes they actually grant
 *          access to, excludes profile-owned permission sets, and never emits a dangling or
 *          empty grant.
 *
 * Test data strategy: unlike the Flow scanner (whose source view is read-only), PermissionSet
 *          and ObjectPermissions ARE insertable in a test context — so these assertions run
 *          against real fixtures this test creates and controls, not merely properties over
 *          whatever the org happens to contain.
 */
@isTest
private class OI_PermissionSetScannerTest {
    @isTest
    static void testDiscoversAPermissionSetAndTheObjectItGrantsAccessTo() {
        PermissionSet permissionSet = new PermissionSet(Name = 'OI_Test_Grant_Set', Label = 'OI Test Grant Set');
        insert permissionSet;
        insert new ObjectPermissions(
            ParentId = permissionSet.Id,
            SobjectType = 'Account',
            PermissionsRead = true,
            PermissionsEdit = true
        );

        OI_DiscoveryBatch batch = new OI_PermissionSetScanner().scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        String permissionSetKey = componentKeyFor(batch, 'OI_Test_Grant_Set');
        System.assertNotEquals(null, permissionSetKey, 'The inserted permission set must be discovered as a component.');

        String accountKey = OI_ComponentKeyUtil.build('CustomObject', null, 'Account');
        OI_DiscoveredRelationship grant = findRelationship(batch, permissionSetKey, accountKey);
        System.assertNotEquals(null, grant, 'A permission set granting Read/Edit on Account must produce a GRANTS_ACCESS_TO edge toward the Account object node.');
        System.assertEquals('GRANTS_ACCESS_TO', grant.relationshipKind);

        List<String> granted = (List<String>) grant.rawAttributes.get('grantedPermissions');
        System.assert(granted.contains('read'), 'The edge must record the real conferred permissions; expected read. Got: ' + granted);
        System.assert(granted.contains('edit'), 'The edge must record the real conferred permissions; expected edit. Got: ' + granted);
    }

    /**
     * A grant row conferring nothing is a no-op, not a dependency — emitting an edge for it
     * would inflate every impact result with permission sets that grant no actual access.
     *
     * Asserted against the permission-describing method directly, with an IN-MEMORY row and no
     * DML, because the platform itself refuses to persist an all-false ObjectPermissions row
     * ("FIELD_INTEGRITY_EXCEPTION: You must enable at least one permission") — the scenario is
     * genuinely unreachable through insert, so a DML-based test of it cannot exist. The skip in
     * OI_PermissionSetScanner.buildObjectGrants is therefore defensive rather than a response
     * to an observed state, and is documented as such rather than presented as load-bearing.
     */
    @isTest
    static void testAGrantConferringNoPermissionsIsRecognizedAsEmptyAndSkipped() {
        OI_PermissionSetScanner scanner = new OI_PermissionSetScanner();

        List<String> nothingGranted = scanner.describeObjectPermissions(new ObjectPermissions(SobjectType = 'Account'));
        System.assertEquals(0, nothingGranted.size(), 'A row with no permission flags set must describe as granting nothing, which is what causes buildObjectGrants to skip it.');

        List<String> readOnly = scanner.describeObjectPermissions(new ObjectPermissions(SobjectType = 'Account', PermissionsRead = true));
        System.assertEquals(new List<String>{ 'read' }, readOnly, 'Only the flags actually set may be reported as granted.');
    }

    /**
     * Every Profile has an implicit system-owned PermissionSet. Including those would double-
     * count profile grants under synthetic names no admin recognizes from Setup — Profiles get
     * their own componentKind (Backlog MS-7) instead.
     */
    @isTest
    static void testExcludesProfileOwnedPermissionSets() {
        OI_DiscoveryBatch batch = new OI_PermissionSetScanner().scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        Set<String> discoveredNames = new Set<String>();
        for (OI_DiscoveredComponent component : batch.components) {
            discoveredNames.add(component.fullyQualifiedName);
        }

        for (PermissionSet profileOwned : [SELECT Name FROM PermissionSet WHERE IsOwnedByProfile = true LIMIT 50]) {
            System.assert(
                !discoveredNames.contains(profileOwned.Name),
                'A profile-owned permission set must never be discovered as a PermissionSet component: ' + profileOwned.Name
            );
        }
    }

    /**
     * The dangling-edge guard: ObjectPermissions really does carry rows for objects
     * OI_ObjectScanner does not node-ify, so every emitted object grant must be verified
     * in-scope. Asserted through OI_ScannerObjectResolver rather than by re-deriving describes
     * in this loop — an earlier version did the latter and hit the Apex CPU limit on a real
     * org, which is the same scalability trap the resolver's own memo exists to close.
     */
    @isTest
    static void testEveryObjectGrantTargetsAnObjectTheObjectScannerWouldAlsoCreate() {
        OI_DiscoveryBatch batch = new OI_PermissionSetScanner().scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        for (OI_DiscoveredRelationship relationship : batch.relationships) {
            OI_ComponentKeyUtil.ParsedComponentKey parsed = OI_ComponentKeyUtil.parse(relationship.toComponentKey);
            System.assertNotEquals(null, parsed);
            if (parsed.componentKind != 'CustomObject') {
                continue;
            }
            System.assertEquals(
                parsed.fullyQualifiedName,
                OI_ScannerObjectResolver.canonicalInScopeName(parsed.fullyQualifiedName),
                'Grant target ' + parsed.fullyQualifiedName + ' must resolve to itself as an in-scope, node-producing object, or the edge would dangle.'
            );
        }
    }

    /** Every emitted edge must target a componentKind some scanner in this package actually produces — an edge toward an unscanned kind would dangle exactly like an out-of-scope object. */
    @isTest
    static void testEveryGrantTargetsAComponentKindSomeScannerActuallyProduces() {
        OI_DiscoveryBatch batch = new OI_PermissionSetScanner().scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        Set<String> scannedComponentKinds = new Set<String>{ 'CustomObject', 'ApexClass' };
        for (OI_DiscoveredRelationship relationship : batch.relationships) {
            OI_ComponentKeyUtil.ParsedComponentKey parsed = OI_ComponentKeyUtil.parse(relationship.toComponentKey);
            System.assertNotEquals(null, parsed);
            System.assert(
                scannedComponentKinds.contains(parsed.componentKind),
                'This scanner must only emit grants toward componentKinds another scanner creates nodes for. Found: ' + parsed.componentKind
            );
        }
    }

    @isTest
    static void testComponentIdentityIsDeterministicAcrossRepeatedScans() {
        PermissionSet permissionSet = new PermissionSet(Name = 'OI_Test_Deterministic', Label = 'OI Test Deterministic');
        insert permissionSet;

        OI_PermissionSetScanner scanner = new OI_PermissionSetScanner();
        OI_DiscoveryBatch first = scanner.scan(new OI_ScanContext(null, 200, null, 'SOQL'));
        OI_DiscoveryBatch second = scanner.scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        OI_DiscoveredComponent firstComponent = findComponent(first, 'OI_Test_Deterministic');
        OI_DiscoveredComponent secondComponent = findComponent(second, 'OI_Test_Deterministic');
        System.assertNotEquals(null, firstComponent);
        System.assertEquals(firstComponent.componentKey, secondComponent.componentKey);
        System.assertEquals(firstComponent.rawChecksum, secondComponent.rawChecksum);
    }

    private static OI_DiscoveredComponent findComponent(OI_DiscoveryBatch batch, String name) {
        for (OI_DiscoveredComponent component : batch.components) {
            if (component.fullyQualifiedName == name) {
                return component;
            }
        }
        return null;
    }

    private static String componentKeyFor(OI_DiscoveryBatch batch, String name) {
        OI_DiscoveredComponent component = findComponent(batch, name);
        return component == null ? null : component.componentKey;
    }

    private static OI_DiscoveredRelationship findRelationship(OI_DiscoveryBatch batch, String fromKey, String toKey) {
        for (OI_DiscoveredRelationship relationship : batch.relationships) {
            if (relationship.fromComponentKey == fromKey && relationship.toComponentKey == toKey) {
                return relationship;
            }
        }
        return null;
    }
}
