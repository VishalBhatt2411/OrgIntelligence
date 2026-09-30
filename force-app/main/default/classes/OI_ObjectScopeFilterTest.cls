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

    policy.localNamespace = 'acme';
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isNamespaceInScope('ACME'),
      'The org namespace matches case-insensitively.'
    );

    policy.includeManagedPackages = true;
    System.assertEquals(true, OI_ObjectScopeFilter.isNamespaceInScope('FSL'));
  }

  /** Packaged: the app's namespace is out even with managed packages switched on. */
  @isTest
  static void testAppNamespaceIsAlwaysOutOfScope() {
    OI_ObjectScopeFilter.ScopePolicy policy = useEmptyPolicy();
    policy.appNamespace = 'orgintel';
    policy.includeManagedPackages = true;

    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isNamespaceInScope('OrgIntel'),
      'The app never maps its own packaged code.'
    );
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isComponentInScope('orgintel', 'OI_GraphEngine')
    );
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isComponentInScope('FSL', 'FSL_Admin'),
      'Other packages still follow the package switch.'
    );
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isComponentInScope(null, 'OI_CustomerClass'),
      'Packaged, the name prefix is not used: a customer OI_ class stays in scope.'
    );
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isFieldNamespaceInScope('orgintel__Status__c')
    );
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isFieldNamespaceInScope('FSL__Status__c')
    );
  }

  /** Un-namespaced: the OI_ prefix identifies the app's components, case-insensitively. */
  @isTest
  static void testAppNamePrefixExcludesUnNamespacedAppComponents() {
    OI_ObjectScopeFilter.ScopePolicy policy = useEmptyPolicy();
    policy.appNamePrefix = 'oi_';

    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isComponentInScope(null, 'OI_GraphEngine')
    );
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isComponentInScope('', 'oi_logEventTrigger')
    );
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isComponentInScope(null, 'AccountService')
    );
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isComponentInScope(null, 'OIS_Helper'),
      'Only the full OI_ prefix matches.'
    );
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isComponentInScope(null, null),
      'A missing name cannot be matched, so only the namespace decides.'
    );
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isFieldNamespaceInScope('OI_Health_Score__c')
    );
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isInScope(OI_Scan_Run__c.SObjectType.getDescribe()),
      'The app never maps its own objects.'
    );
    System.assertEquals(
      true,
      OI_ObjectScopeFilter.isInScope(Account.SObjectType.getDescribe())
    );
  }

  /** The shipped policy with self-exclusion on (as in production) leaves out this app's own object and class. */
  @isTest
  static void testShippedPolicyExcludesTheAppsOwnComponents() {
    OI_ObjectScopeFilter.policyOverride = null;
    OI_ObjectScopeFilter.excludeOwnComponents = true;
    OI_ObjectScopeFilter.resetCache();

    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isInScope(OI_Scan_Run__c.SObjectType.getDescribe())
    );
    ApexClass self = [
      SELECT Name, NamespacePrefix
      FROM ApexClass
      WHERE Name = 'OI_ObjectScopeFilter'
      LIMIT 1
    ];
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.isComponentInScope(self.NamespacePrefix, self.Name)
    );
    System.assertEquals(
      false,
      OI_ObjectScopeFilter.includeStandardPermissionSets(),
      'Salesforce-supplied permission sets are off in the shipped settings.'
    );
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
