/**
 * Purpose: Verifies OI_FieldScanner persists only relationship-bearing fields (ADR-0031)
 *          with a correct parentComponentKey and HAS_FIELD relationship, emits edges only
 *          to in-scope targets, and correctly distinguishes Lookup from Master-Detail
 *          reference relationships (Sprint 8 objective §5/§6).
 */
@isTest
private class OI_FieldScannerTest {
  @isTest
  static void testAccountOwnerFieldHasCorrectParentAndHasFieldRelationship() {
    useAccountAndUserPolicy();
    /** Scoped to just Account — describing every object in this shared org pushes an unscoped scan() over the synchronous CPU limit; the unscoped path has its own coverage below. */
    OI_DiscoveryBatch batch = new OI_FieldScanner().scan(accountOnlyContext());

    System.assertEquals('CustomField', batch.componentKind);
    System.assertEquals(true, batch.isFullSnapshot);

    OI_DiscoveredComponent ownerField = findByName(batch, 'Account.OwnerId');
    System.assertNotEquals(
      null,
      ownerField,
      'Expected Account.OwnerId (a lookup to the in-scope User object) to be discovered.'
    );
    String expectedParentKey = OI_ComponentKeyUtil.build(
      'CustomObject',
      null,
      'Account'
    );
    System.assertEquals(expectedParentKey, ownerField.parentComponentKey);

    Boolean foundHasField = false;
    for (OI_DiscoveredRelationship relationship : batch.relationships) {
      if (
        relationship.relationshipKind == 'HAS_FIELD' &&
        relationship.toComponentKey == ownerField.componentKey
      ) {
        foundHasField = true;
        System.assertEquals(expectedParentKey, relationship.fromComponentKey);
      }
    }
    System.assert(
      foundHasField,
      'Expected a HAS_FIELD relationship from Account to Account.OwnerId.'
    );
  }

  /** Plain data fields are served live from Describe, never persisted — the storage saving ADR-0031 exists for. */
  @isTest
  static void testNonReferenceFieldIsNotPersisted() {
    useAccountAndUserPolicy();
    OI_DiscoveryBatch batch = new OI_FieldScanner().scan(accountOnlyContext());

    System.assertEquals(null, findByName(batch, 'Account.Name'));
    System.assertEquals(null, findByName(batch, 'Account.Industry'));
    for (OI_DiscoveredComponent component : batch.components) {
      System.assertEquals(
        'REFERENCE',
        String.valueOf(component.rawAttributes.get('type')),
        'Only reference fields may be persisted: ' +
        component.fullyQualifiedName
      );
    }
  }

  /** A lookup whose only target is out of scope has no graph structure to carry, so neither the field nor a dangling edge is emitted. */
  @isTest
  static void testReferenceFieldToOutOfScopeTargetIsNotPersisted() {
    OI_ObjectScopeFilter.ScopePolicy policy = new OI_ObjectScopeFilter.ScopePolicy();
    policy.includeCustomizedStandardObjects = false;
    policy.alwaysInclude.add('account');
    policy.alwaysExclude.add('user');
    OI_ObjectScopeFilter.policyOverride = policy;

    OI_DiscoveryBatch batch = new OI_FieldScanner().scan(accountOnlyContext());

    System.assertEquals(
      null,
      findByName(batch, 'Account.OwnerId'),
      'Account.OwnerId targets only User, which this policy excludes.'
    );
    String userKey = OI_ComponentKeyUtil.build('CustomObject', null, 'User');
    for (OI_DiscoveredRelationship relationship : batch.relationships) {
      System.assertNotEquals(
        userKey,
        relationship.toComponentKey,
        'No edge may point at an out-of-scope object.'
      );
    }
  }

  @isTest
  static void testLookupFieldEmitsLookupToRelationship() {
    useAccountAndUserPolicy();
    OI_DiscoveryBatch batch = new OI_FieldScanner().scan(accountOnlyContext());

    OI_DiscoveredComponent ownerField = findByName(batch, 'Account.OwnerId');
    System.assertNotEquals(null, ownerField);

    Boolean foundLookup = false;
    for (OI_DiscoveredRelationship relationship : batch.relationships) {
      if (
        relationship.relationshipKind == 'LOOKUP_TO' &&
        relationship.fromComponentKey == ownerField.componentKey
      ) {
        foundLookup = true;
      }
    }
    System.assert(
      foundLookup,
      'Account.OwnerId is a polymorphic lookup and must emit at least one LOOKUP_TO relationship.'
    );
  }

  /**
   * Uses this package's own OI_Scan_Task__c.Scan_Run__c — a genuine custom Master-Detail
   * field — rather than a standard-object relationship: empirically, standard
   * relationships like OpportunityLineItem -> Opportunity are not exposed through
   * getRelationshipOrder() the same way a real custom Master-Detail field is, so
   * asserting against one would test a platform assumption this Scanner does not
   * actually rely on. A custom Master-Detail field is the reliable, org-independent case.
   */
  @isTest
  static void testMasterDetailFieldEmitsMasterDetailToRelationship() {
    OI_FieldScanner scanner = new OI_FieldScanner();
    OI_DiscoveryBatch batch = scanner.scan(
      new OI_ScanContext(null, 100, null, 'Describe')
    );

    OI_DiscoveredComponent scanRunField = findByName(
      batch,
      'OI_Scan_Task__c.Scan_Run__c'
    );
    System.assertNotEquals(
      null,
      scanRunField,
      'Expected the custom Master-Detail field OI_Scan_Task__c.Scan_Run__c to be discovered.'
    );

    Boolean foundMasterDetail = false;
    for (OI_DiscoveredRelationship relationship : batch.relationships) {
      if (
        relationship.relationshipKind == 'MASTER_DETAIL_TO' &&
        relationship.fromComponentKey == scanRunField.componentKey
      ) {
        foundMasterDetail = true;
      }
    }
    System.assert(
      foundMasterDetail,
      'OI_Scan_Task__c.Scan_Run__c is a custom Master-Detail field and must emit MASTER_DETAIL_TO, not LOOKUP_TO.'
    );
  }

  /**
   * The field's own attributes bag (not just the edge kind) must carry the Lookup vs
   * Master-Detail distinction too — the Relationships-section rework (Intelligence Panel)
   * reads this directly off the field node so it never needs a second query against the
   * graph's edge rows just to label a relationship's type.
   */
  @isTest
  static void testMasterDetailAttributeIsTrueForMasterDetailAndFalseForLookup() {
    OI_FieldScanner scanner = new OI_FieldScanner();
    OI_DiscoveryBatch batch = scanner.scan(
      new OI_ScanContext(null, 100, null, 'Describe')
    );

    OI_DiscoveredComponent scanRunField = findByName(
      batch,
      'OI_Scan_Task__c.Scan_Run__c'
    );
    System.assertNotEquals(null, scanRunField);
    System.assertEquals(true, scanRunField.rawAttributes.get('masterDetail'));

    OI_DiscoveredComponent ownerField = findByName(batch, 'Account.OwnerId');
    System.assertNotEquals(null, ownerField);
    System.assertEquals(
      false,
      ownerField.rawAttributes.get('masterDetail'),
      'A plain Lookup must report masterDetail=false, never null/absent, so a consumer never has to treat a missing key as an assumption.'
    );
  }

  /**
   * Scopes both scans to just Account via OI_ScanContext.scopedApiNames — the only
   * assertion this test makes is about Account.OwnerId, so there's no need to pay for a
   * full org-wide Describe twice in one transaction. This isn't only an optimization:
   * a real org's total schema size (every installed managed package's objects/fields
   * included) is outside this test's control, and a org with a large enough schema can
   * exceed the synchronous Apex heap limit on a full org-wide scan alone, let alone two
   * back-to-back — scoping removes that dependency on the target org's total schema size
   * entirely, which holding-only-one-batch-at-a-time (the previous approach) could not.
   */
  @isTest
  static void testChecksumIsDeterministicAcrossRepeatedScans() {
    useAccountAndUserPolicy();
    OI_FieldScanner scanner = new OI_FieldScanner();
    OI_ScanContext accountOnlyScope = accountOnlyContext();

    OI_DiscoveryBatch firstBatch = scanner.scan(accountOnlyScope);
    OI_DiscoveredComponent first = findByName(firstBatch, 'Account.OwnerId');
    String firstComponentKey = first.componentKey;
    String firstChecksum = first.rawChecksum;
    firstBatch = null;
    first = null;

    OI_DiscoveryBatch secondBatch = scanner.scan(accountOnlyScope);
    OI_DiscoveredComponent second = findByName(secondBatch, 'Account.OwnerId');

    System.assertEquals(firstComponentKey, second.componentKey);
    System.assertEquals(firstChecksum, second.rawChecksum);
  }

  /** Pins the scope policy so these tests do not depend on the shipped OI_Scan_Object_Scope__mdt records or this org's customisations. */
  private static void useAccountAndUserPolicy() {
    OI_ObjectScopeFilter.ScopePolicy policy = new OI_ObjectScopeFilter.ScopePolicy();
    policy.includeCustomizedStandardObjects = false;
    policy.alwaysInclude.add('account');
    policy.alwaysInclude.add('user');
    OI_ObjectScopeFilter.policyOverride = policy;
  }

  private static OI_ScanContext accountOnlyContext() {
    return new OI_ScanContext(
      null,
      100,
      null,
      'Describe',
      new Set<String>{ 'Account' }
    );
  }

  private static OI_DiscoveredComponent findByName(
    OI_DiscoveryBatch batch,
    String fullyQualifiedName
  ) {
    for (OI_DiscoveredComponent component : batch.components) {
      if (component.fullyQualifiedName == fullyQualifiedName) {
        return component;
      }
    }
    return null;
  }
}
