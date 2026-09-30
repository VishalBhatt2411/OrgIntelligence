/**
 * Purpose: Verifies OI_ObjectScopeFilter's structural exclusions and the ADR-0031 scan
 *          scope policy (override records, custom objects, customized standard objects,
 *          managed-package namespaces).
 */
@isTest
private class OI_ObjectScopeFilterTest {
  @isTest
  static void testAccountIsInScope() {
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isInScope(Account.SObjectType.getDescribe()),
      'Account ships as an always-include core object.'
    );
  }

  @isTest
  static void testAccountHistoryIsExcluded() {
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isInScope(
        Schema.getGlobalDescribe().get('AccountHistory').getDescribe()
      )
    );
  }

  @isTest
  static void testAccountShareIsExcluded() {
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isInScope(
        Schema.getGlobalDescribe().get('AccountShare').getDescribe()
      )
    );
  }

  @isTest
  static void testNullIsNotInScope() {
    System.assertEquals(false, OI_ObjectScopeFilter.isInScope(null));
  }

  @isTest
  static void testLocalCustomObjectIsInScopeWithoutAnOverrideRecord() {
    useEmptyPolicy();
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isInScope(OI_Scan_Run__c.SObjectType.getDescribe())
    );
  }

  @isTest
  static void testUncustomizedStandardObjectIsOutOfScopeByDefault() {
    useEmptyPolicy();
    // Organization never carries custom fields, so it can only enter scope via an override record.
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isInScope(Organization.SObjectType.getDescribe())
    );
  }

  @isTest
  static void testAlwaysIncludeRecordAddsAStandardObject() {
    OI_ObjectScopeFilter.ScopePolicy policy = useEmptyPolicy();
    policy.alwaysInclude.add('organization');
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isInScope(Organization.SObjectType.getDescribe())
    );
  }

  @isTest
  static void testAlwaysExcludeRecordWinsOverACustomObject() {
    OI_ObjectScopeFilter.ScopePolicy policy = useEmptyPolicy();
    policy.alwaysExclude.add('oi_scan_run__c');
    policy.alwaysInclude.add('oi_scan_run__c');
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isInScope(OI_Scan_Run__c.SObjectType.getDescribe()),
      'An explicit exclusion must beat every include rule.'
    );
  }

  @isTest
  static void testCustomizedStandardObjectsSwitchOffDropsThem() {
    OI_ObjectScopeFilter.ScopePolicy policy = useEmptyPolicy();
    policy.includeCustomizedStandardObjects = false;
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isInScope(Account.SObjectType.getDescribe())
    );
  }

  @isTest
  static void testForeignNamespaceDetection() {
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isForeignNamespaced('Account', '')
    );
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isForeignNamespaced('Invoice__c', '')
    );
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isForeignNamespaced('FSL__Work_Rule__c', '')
    );
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isForeignNamespaced('oi__Scan_Run__c', 'oi'),
      'The org\'s own namespace is local, not foreign.'
    );
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isForeignNamespaced('FSL__Work_Rule__c', 'oi')
    );
  }

  @isTest
  static void testFieldNamespaceScopeFollowsThePackageSwitch() {
    OI_ObjectScopeFilter.ScopePolicy policy = useEmptyPolicy();
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isFieldNamespaceInScope('Region__c')
    );
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isFieldNamespaceInScope('OwnerId')
    );
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isFieldNamespaceInScope('FSL__Territory__c')
    );
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isFieldNamespaceInScope(null)
    );

    policy.includeManagedPackages = true;
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isFieldNamespaceInScope('FSL__Territory__c')
    );
  }

  @isTest
  static void testCodeNamespaceScopeFollowsThePackageSwitch() {
    OI_ObjectScopeFilter.ScopePolicy policy = useEmptyPolicy();
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isNamespaceInScope(null),
      'Un-namespaced code belongs to this org.'
    );
    System.assertEquals(true, OI_ObjectScopeFilter.isNamespaceInScope(''));
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isNamespaceInScope('FSL'),
      'Installed-package code is skipped by default.'
    );

    policy.localNamespace = 'oi';
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isNamespaceInScope('OI'),
      'The local namespace matches case-insensitively.'
    );

    policy.includeManagedPackages = true;
    System.assertEquals(true, OI_ObjectScopeFilter.isNamespaceInScope('FSL'));
  }

  @isTest
  static void testDecisionsAreMemoizedPerTransaction() {
    OI_ObjectScopeFilter.ScopePolicy policy = useEmptyPolicy();
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isInScope(OI_Scan_Run__c.SObjectType.getDescribe())
    );
    policy.alwaysExclude.add('oi_scan_run__c');
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isInScope(OI_Scan_Run__c.SObjectType.getDescribe()),
      'A decision is fixed for the transaction so every scanner sees the same answer.'
    );

    OI_ObjectScopeFilter.resetCache();
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isInScope(OI_Scan_Run__c.SObjectType.getDescribe())
    );
  }

  /** The real settings + CMT load path: shipped defaults exclude packages and keep customized standard objects. */
  @isTest
  static void testShippedPolicyLoadsWithoutAnOverride() {
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isInScope(OI_Scan_Run__c.SObjectType.getDescribe())
    );
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isFieldNamespaceInScope('zzpkg__Anything__c')
    );
  }

  private static OI_ObjectScopeFilter.ScopePolicy useEmptyPolicy() {
    OI_ObjectScopeFilter.ScopePolicy policy = new OI_ObjectScopeFilter.ScopePolicy();
    OI_ObjectScopeFilter.policyOverride = policy;
    OI_ObjectScopeFilter.resetCache();
    return policy;
  }
}
