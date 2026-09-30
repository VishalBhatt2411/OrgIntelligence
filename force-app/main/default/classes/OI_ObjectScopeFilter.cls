/**
 * Purpose: The single, shared definition of which SObjects the metadata scan persists as
 *          "CustomObject" components (MetadataScanner.md §1's "faithful, not generic"
 *          Scanner philosophy, applied to a real platform-scale bound), and which of an
 *          object's fields belong to an in-scope namespace.
 * Responsibilities: Answer "is this describe result in scope" identically for every
 *                    scanner (ObjectScanner, FieldScanner, SharingRuleScanner directly;
 *                    the automation/security scanners via OI_ScannerObjectResolver), so an
 *                    object either has its node, its fields AND its inbound edges, or
 *                    none of them — never a half-scanned object or a dangling edge.
 * Dependencies: OI_Settings__mdt (via OI_SettingsService), OI_Scan_Object_Scope__mdt,
 *               OI_LoggerService.
 * Inputs/Outputs: A DescribeSObjectResult in, a Boolean out. Decisions are memoized per
 *                 transaction by lowercase API name.
 * Scope policy (ADR-0031), evaluated in this order after the structural exclusions:
 *   1. An OI_Scan_Object_Scope__mdt record with Enabled = false always excludes.
 *   2. An OI_Scan_Object_Scope__mdt record with Enabled = true always includes (the
 *      shipped records are the core CRM objects).
 *   3. A custom object from this org's own namespace (or no namespace) is included; one
 *      from another namespace (an installed managed package) only when
 *      Scan_Managed_Package_Objects__c is checked.
 *   4. A standard object is included when Scan_Customized_Standard_Objects__c is checked
 *      and it carries at least one custom field from an in-scope namespace.
 *   5. Everything else — the several hundred uncustomized standard/setup objects every
 *      org has — is out of scope. This is what keeps graph storage proportional to the
 *      org's own customisation instead of the platform's size.
 * The same managed-package rule applies to code components by NamespacePrefix
 * (isComponentInScope), so Apex classes, triggers, flows and permission sets from installed
 * packages are skipped by default too.
 * This app never maps itself: its own objects, fields, classes, triggers, flows and
 * permission sets are always out of scope. Installed as a package they are recognised by the
 * package's namespace; deployed un-namespaced (development) by the OI_ prefix every app
 * component carries. Only the second case can collide with a customer's own OI_-prefixed
 * components, and only in an org running the app un-namespaced.
 * "Local" namespace means the org's own (Organization.NamespacePrefix), not the package's:
 * in a subscriber org the two differ, and only the org's own components are the customer's.
 * Limitations: The structural exclusions are unchanged — Custom Metadata Types (__mdt),
 *              Platform Events (__e), Big Objects (__b), External Objects (__x), and the
 *              platform-generated History/Feed/Share/ChangeEvent companions are never in
 *              scope. A missing settings record degrades to the documented defaults
 *              (packages excluded, customized standard objects included) rather than
 *              failing the scan. The local namespace is derived from this class's own
 *              runtime type name, so it needs no SOQL and is correct in a namespaced
 *              packaging org and in an unmanaged/dev org alike.
 */
public inherited sharing class OI_ObjectScopeFilter {
  private static final Set<String> EXCLUDED_SUFFIXES = new Set<String>{
    '__mdt',
    '__e',
    '__b',
    '__x',
    'History',
    'Share',
    'Feed',
    'ChangeEvent'
  };
  private static final String CUSTOM_SUFFIX = '__c';
  /** Every component this app ships is named with this prefix (CLAUDE.md naming convention). */
  private static final String APP_COMPONENT_PREFIX = 'oi_';
  private static final String NAMESPACE_SEPARATOR = '__';

  /** Test seam: replaces the settings/CMT-derived policy for the running transaction. */
  @TestVisible
  private static ScopePolicy policyOverride;
  /** Test seam: scanner tests use the app's own deployed components as live fixtures, so the self-exclusion is off under test unless a test turns it on. */
  @TestVisible
  private static Boolean excludeOwnComponents = !Test.isRunningTest();
  private static ScopePolicy cachedPolicy;
  private static Map<String, Boolean> decisionsByApiName = new Map<String, Boolean>();

  /**
   * The resolved scope configuration. Object names in the two override sets are
   * lowercase. localNamespace is the org's own namespace, lowercase, or blank.
   * appNamespace and appNamePrefix identify this app's own components (see the class
   * comment); both blank means nothing is treated as the app's own.
   */
  public class ScopePolicy {
    public Boolean includeManagedPackages = false;
    public Boolean includeCustomizedStandardObjects = true;
    public Boolean includeStandardPermissionSets = false;
    public String localNamespace = '';
    public String appNamespace = '';
    public String appNamePrefix = '';
    public Set<String> alwaysInclude = new Set<String>();
    public Set<String> alwaysExclude = new Set<String>();
  }

  public static Boolean isInScope(Schema.DescribeSObjectResult describeResult) {
    if (!isStructurallyEligible(describeResult)) {
      return false;
    }
    String memoKey = describeResult.getName().toLowerCase();
    Boolean decision = decisionsByApiName.get(memoKey);
    if (decision == null) {
      decision = decide(describeResult, getPolicy());
      decisionsByApiName.put(memoKey, decision);
    }
    return decision;
  }

  /**
   * Whether a field (by API name) belongs to a namespace the current policy scans. Only
   * custom fields carry a namespace; standard fields are always in scope. Used by
   * OI_FieldScanner to skip a managed package's fields on an otherwise in-scope object.
   */
  public static Boolean isFieldNamespaceInScope(String fieldApiName) {
    if (String.isBlank(fieldApiName)) {
      return false;
    }
    ScopePolicy policy = getPolicy();
    if (isAppApiName(fieldApiName.toLowerCase(), policy)) {
      return false;
    }
    return policy.includeManagedPackages ||
      !isForeignNamespaced(fieldApiName, policy.localNamespace);
  }

  /**
   * Whether a code or security component (Apex class, trigger, flow, permission set) with
   * this NamespacePrefix and API name is in scope: never when it is this app's own, else as
   * isNamespaceInScope decides.
   */
  public static Boolean isComponentInScope(
    String namespacePrefix,
    String componentName
  ) {
    if (isAppComponent(namespacePrefix, componentName)) {
      return false;
    }
    return isNamespaceInScope(namespacePrefix);
  }

  /**
   * Whether a code or security component with this NamespacePrefix and API name is this app's
   * own (see the class comment). Unlike isComponentInScope it says nothing about other
   * packages, so a caller with its own managed-package rules (the Tech Debt engine) can
   * leave only the app out.
   */
  public static Boolean isAppComponent(
    String namespacePrefix,
    String componentName
  ) {
    ScopePolicy policy = getPolicy();
    if (String.isNotBlank(namespacePrefix)) {
      return namespacePrefix.toLowerCase() == policy.appNamespace;
    }
    return String.isNotBlank(policy.appNamePrefix) &&
      String.isNotBlank(componentName) &&
      componentName.toLowerCase().startsWith(policy.appNamePrefix);
  }

  /**
   * isAppComponent for Lightning component bundles, whose names are camelCase: the app's
   * un-namespaced bundles start with "oi" followed by an upper-case letter (oiGraphExplorer).
   * Bundles the app ships without that prefix are not recognised.
   */
  public static Boolean isAppLightningComponent(
    String namespacePrefix,
    String bundleName
  ) {
    ScopePolicy policy = getPolicy();
    if (String.isNotBlank(namespacePrefix)) {
      return namespacePrefix.toLowerCase() == policy.appNamespace;
    }
    String prefix = policy.appNamePrefix.removeEnd('_');
    return String.isNotBlank(prefix) &&
      String.isNotBlank(bundleName) &&
      bundleName.length() > prefix.length() &&
      bundleName.toLowerCase().startsWith(prefix) &&
      bundleName.substring(prefix.length(), prefix.length() + 1)
        .isAllUpperCase();
  }

  /** Whether an object or field API name (ns__Name__c or OI_Name__c) belongs to this app. */
  public static Boolean isAppApiName(String apiName) {
    return String.isNotBlank(apiName) &&
      isAppApiName(apiName.toLowerCase(), getPolicy());
  }

  /**
   * Whether Salesforce-supplied permission sets (IsCustom = false: license and feature sets
   * the platform provisions) are scanned. Off by default: they are numerous, the customer did
   * not build them, and each carries many access edges (Scan_Standard_Permission_Sets__c).
   */
  public static Boolean includeStandardPermissionSets() {
    return getPolicy().includeStandardPermissionSets;
  }

  /**
   * Whether a code component (Apex class, trigger, flow) with this NamespacePrefix is in
   * scope. Blank and this org's own namespace are always in scope; any other namespace is
   * an installed managed package, scanned only when Scan_Managed_Package_Objects__c is
   * checked. Managed code bodies are hidden anyway, so persisting them buys storage cost
   * without dependency insight (ADR-0031 §1).
   */
  public static Boolean isNamespaceInScope(String namespacePrefix) {
    if (String.isBlank(namespacePrefix)) {
      return true;
    }
    ScopePolicy policy = getPolicy();
    String lowerNamespace = namespacePrefix.toLowerCase();
    if (lowerNamespace == policy.appNamespace) {
      return false;
    }
    return policy.includeManagedPackages ||
      lowerNamespace == policy.localNamespace;
  }

  /** Clears the per-transaction memo — for tests that swap policyOverride mid-method. */
  @TestVisible
  private static void resetCache() {
    cachedPolicy = null;
    decisionsByApiName = new Map<String, Boolean>();
  }

  private static Boolean isStructurallyEligible(
    Schema.DescribeSObjectResult describeResult
  ) {
    if (describeResult == null || !describeResult.isQueryable()) {
      return false;
    }
    String apiName = describeResult.getName();
    for (String suffix : EXCLUDED_SUFFIXES) {
      if (apiName.endsWith(suffix)) {
        return false;
      }
    }
    return true;
  }

  private static Boolean decide(
    Schema.DescribeSObjectResult describeResult,
    ScopePolicy policy
  ) {
    String lowerName = describeResult.getName().toLowerCase();
    if (isAppApiName(lowerName, policy)) {
      return false;
    }
    if (policy.alwaysExclude.contains(lowerName)) {
      return false;
    }
    if (policy.alwaysInclude.contains(lowerName)) {
      return true;
    }
    if (describeResult.isCustom()) {
      return policy.includeManagedPackages ||
        !isForeignNamespaced(lowerName, policy.localNamespace);
    }
    return policy.includeCustomizedStandardObjects &&
      hasInScopeCustomField(describeResult, policy);
  }

  /**
   * Field-map keys are lowercase API names, so this is a keySet scan — no per-field
   * describe call, which matters because this runs for every standard object in the org.
   */
  private static Boolean hasInScopeCustomField(
    Schema.DescribeSObjectResult describeResult,
    ScopePolicy policy
  ) {
    for (String fieldKey : describeResult.fields.getMap().keySet()) {
      if (!fieldKey.endsWith(CUSTOM_SUFFIX)) {
        continue;
      }
      if (
        policy.includeManagedPackages ||
        !isForeignNamespaced(fieldKey, policy.localNamespace)
      ) {
        return true;
      }
    }
    return false;
  }

  /**
   * A custom API name is `Name__c` un-namespaced and `ns__Name__c` namespaced. After
   * stripping this org's own namespace prefix, any remaining extra `__` separator means
   * the name belongs to some other namespace. Standard names (no `__`) are never foreign.
   */
  @TestVisible
  private static Boolean isForeignNamespaced(
    String apiName,
    String localNamespace
  ) {
    String name = apiName.toLowerCase();
    if (
      String.isNotBlank(localNamespace) &&
      name.startsWith(localNamespace + NAMESPACE_SEPARATOR)
    ) {
      name = name.substring(
        localNamespace.length() + NAMESPACE_SEPARATOR.length()
      );
    }
    Integer firstSeparator = name.indexOf(NAMESPACE_SEPARATOR);
    return firstSeparator > -1 &&
      firstSeparator != name.lastIndexOf(NAMESPACE_SEPARATOR);
  }

  /** An object or field API name (lowercase) that belongs to this app: ns__Name__c when packaged, OI_Name__c un-namespaced. */
  private static Boolean isAppApiName(String lowerApiName, ScopePolicy policy) {
    if (String.isNotBlank(policy.appNamespace)) {
      return lowerApiName.startsWith(policy.appNamespace + NAMESPACE_SEPARATOR);
    }
    return String.isNotBlank(policy.appNamePrefix) &&
      lowerApiName.startsWith(policy.appNamePrefix);
  }

  private static ScopePolicy getPolicy() {
    if (policyOverride != null) {
      return policyOverride;
    }
    if (cachedPolicy == null) {
      cachedPolicy = loadPolicy();
    }
    return cachedPolicy;
  }

  private static ScopePolicy loadPolicy() {
    ScopePolicy policy = new ScopePolicy();
    policy.localNamespace = resolveOrgNamespace();
    if (excludeOwnComponents) {
      policy.appNamespace = resolveAppNamespace();
      policy.appNamePrefix = String.isBlank(policy.appNamespace)
        ? APP_COMPONENT_PREFIX
        : '';
    }
    try {
      OI_Settings__mdt settings = new OI_SettingsService().getSettings();
      policy.includeManagedPackages =
        settings.Scan_Managed_Package_Objects__c == true;
      policy.includeCustomizedStandardObjects =
        settings.Scan_Customized_Standard_Objects__c != false;
      policy.includeStandardPermissionSets =
        settings.Scan_Standard_Permission_Sets__c == true;
    } catch (OI_ServiceException e) {
      // Documented degradation: keep the storage-light defaults and still scan.
      new OI_LoggerService()
        .warn(
          'Scan scope settings unavailable; using defaults. ' + e.getMessage(),
          'OI_ObjectScopeFilter',
          null
        );
    }
    for (
      OI_Scan_Object_Scope__mdt scopeRecord : OI_Scan_Object_Scope__mdt.getAll()
        .values()
    ) {
      if (String.isBlank(scopeRecord.Object_Api_Name__c)) {
        continue;
      }
      String lowerName = scopeRecord.Object_Api_Name__c.trim().toLowerCase();
      if (scopeRecord.Enabled__c) {
        policy.alwaysInclude.add(lowerName);
      } else {
        policy.alwaysExclude.add(lowerName);
      }
    }
    return policy;
  }

  /** The org's own namespace; blank for most orgs. One query per transaction (the policy is cached). */
  private static String resolveOrgNamespace() {
    List<Organization> orgs = [
      SELECT NamespacePrefix
      FROM Organization
      LIMIT 1
    ];
    return orgs.isEmpty() || String.isBlank(orgs[0].NamespacePrefix)
      ? ''
      : orgs[0].NamespacePrefix.toLowerCase();
  }

  /** This app's namespace, from this class's own runtime type name: blank when deployed un-namespaced. */
  private static String resolveAppNamespace() {
    String qualifiedName = OI_ObjectScopeFilter.class.getName();
    return qualifiedName.contains('.')
      ? qualifiedName.substringBefore('.').toLowerCase()
      : '';
  }
}
