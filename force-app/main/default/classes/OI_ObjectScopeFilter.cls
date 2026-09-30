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
 * (isNamespaceInScope), so Apex classes, triggers and flows from installed packages are
 * skipped by default too.
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
  private static final String NAMESPACE_SEPARATOR = '__';

  /** Test seam: replaces the settings/CMT-derived policy for the running transaction. */
  @TestVisible
  private static ScopePolicy policyOverride;
  private static ScopePolicy cachedPolicy;
  private static Map<String, Boolean> decisionsByApiName = new Map<String, Boolean>();

  /**
   * The resolved scope configuration. Object names in the two override sets are
   * lowercase. localNamespace is lowercase, or blank when the code runs un-namespaced.
   */
  public class ScopePolicy {
    public Boolean includeManagedPackages = false;
    public Boolean includeCustomizedStandardObjects = true;
    public String localNamespace = '';
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
    return policy.includeManagedPackages ||
      !isForeignNamespaced(fieldApiName, policy.localNamespace);
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
    return policy.includeManagedPackages ||
      namespacePrefix.toLowerCase() == policy.localNamespace;
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
    policy.localNamespace = resolveLocalNamespace();
    try {
      OI_Settings__mdt settings = new OI_SettingsService().getSettings();
      policy.includeManagedPackages =
        settings.Scan_Managed_Package_Objects__c == true;
      policy.includeCustomizedStandardObjects =
        settings.Scan_Customized_Standard_Objects__c != false;
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

  private static String resolveLocalNamespace() {
    String qualifiedName = OI_ObjectScopeFilter.class.getName();
    return qualifiedName.contains('.')
      ? qualifiedName.substringBefore('.').toLowerCase()
      : '';
  }
}
