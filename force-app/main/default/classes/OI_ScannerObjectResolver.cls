/**
 * Purpose: The single, shared answer to "this metadata component points at some object — what
 *          is the real, node-producing object API name, if any?" Used by every Scanner that
 *          emits an edge toward a CustomObject component (OI_ApexTriggerScanner,
 *          OI_FlowScanner, OI_PermissionSetScanner).
 * Responsibilities: Canonicalize a candidate object reference to the exact API name
 *                    OI_ObjectScanner would use for that object's node — or null when no such
 *                    node will exist. Deliberately conservative: null means "emit no edge,"
 *                    never "guess."
 * Dependencies: OI_ObjectScopeFilter, Schema.getGlobalDescribe.
 *
 * Two distinct correctness problems this centralizes, both of which silently corrupt the graph
 * if a scanner solves them ad hoc (or forgets to):
 *
 *  1. CASING. componentKey — and therefore the derived nodeKey — is case-sensitive, while the
 *     sources scanners read from are not. A trigger declared `on account`, or a metadata row
 *     carrying "ACCOUNT", must resolve to the same "Account" node OI_ObjectScanner creates, or
 *     the edge silently points at a node that never exists.
 *
 *  2. SCOPE / DANGLING EDGES. OI_ObjectScanner only creates nodes for objects passing
 *     OI_ObjectScopeFilter — which excludes Platform Events (__e), Custom Metadata Types
 *     (__mdt), Big Objects (__b), External Objects (__x), and generated companion objects
 *     (History/Share/Feed/ChangeEvent). An edge toward an excluded object points at a nodeKey
 *     nothing ever creates; Impact Analysis would then report an affected component with no
 *     node behind it. Filtering here keeps "an edge exists only if both endpoints do" true by
 *     construction rather than by each scanner remembering to check. When that filter later
 *     widens (a dedicated Platform Event scanner is named future work), those edges begin
 *     appearing automatically, with no change to any scanner.
 *
 * Performance — not an optimization, a correctness requirement at scale: both
 * Schema.getGlobalDescribe() and SObjectType.getDescribe() are expensive, and the callers here
 * are row-oriented — OI_PermissionSetScanner resolves an object per ObjectPermissions row, of
 * which a mature org has many thousands, overwhelmingly repeats of the same few hundred
 * objects. Resolving naively per call exceeds the Apex CPU limit and fails the entire scan
 * (observed, not theorized: this class's first version did exactly that against a real org).
 * Two transaction-scoped memos fix it: the global describe map is fetched at most once, and
 * each DISTINCT candidate string is resolved at most once. That makes total describe cost a
 * function of how many distinct objects exist, never of how many rows reference them.
 * The negative result is cached deliberately too — an unresolvable candidate is the common
 * case for out-of-scope objects appearing on thousands of rows, and re-deriving "still null"
 * each time is exactly the cost this memo exists to avoid.
 *
 * Limitations: Resolves only what Schema.getGlobalDescribe() can see, so an object the running
 *              user cannot access at all resolves to null — correctly, since this platform must
 *              never surface metadata the user has no visibility into. Accepts an opaque
 *              durable/entity Id (ApexTrigger.TableEnumOrId and FlowDefinitionView's
 *              TriggerObjectOrEventId both carry an object NAME for standard objects but an Id
 *              for custom ones) but cannot translate such an Id back to a name — that case
 *              resolves to null rather than to a fabricated object, which is why every caller
 *              should prefer a real API name source (a parsed declaration, a SobjectType field)
 *              and treat the Id-bearing field as a fallback only.
 */
public inherited sharing class OI_ScannerObjectResolver {
    /** Transaction-scoped memos — see this class's Performance note for why these are a correctness requirement, not a micro-optimization. */
    private static Map<String, Schema.SObjectType> globalDescribeCache;
    private static final Map<String, String> RESOLVED_NAME_BY_CANDIDATE = new Map<String, String>();

    /**
     * The canonical, in-scope object API name for a candidate reference, or null when this org
     * has no such object OR OI_ObjectScanner would not create a node for it (see this class's
     * doc comment for why both cases must return null rather than a best guess).
     */
    public static String canonicalInScopeName(String candidate) {
        if (String.isBlank(candidate)) {
            return null;
        }
        String cacheKey = candidate.toLowerCase();
        /** containsKey, not a null check on get() — a cached null is a real, meaningful answer ("resolved, and it is not usable"), and treating it as a cache miss would defeat the memo precisely in the repeat-heavy case it exists for. */
        if (RESOLVED_NAME_BY_CANDIDATE.containsKey(cacheKey)) {
            return RESOLVED_NAME_BY_CANDIDATE.get(cacheKey);
        }

        String resolved = null;
        Schema.SObjectType objectType = describeByLowercaseName().get(cacheKey);
        if (objectType != null) {
            Schema.DescribeSObjectResult describeResult = objectType.getDescribe();
            resolved = OI_ObjectScopeFilter.isInScope(describeResult) ? describeResult.getName() : null;
        }
        RESOLVED_NAME_BY_CANDIDATE.put(cacheKey, resolved);
        return resolved;
    }

    /** Schema.getGlobalDescribe() is already keyed by lowercase API name, so this is a straight memo of that one expensive call rather than a re-keyed copy of it. */
    private static Map<String, Schema.SObjectType> describeByLowercaseName() {
        if (globalDescribeCache == null) {
            globalDescribeCache = Schema.getGlobalDescribe();
        }
        return globalDescribeCache;
    }

    /** The componentKey of the CustomObject component a resolved name belongs to — the exact key OI_ObjectScanner builds for that object, so edges and nodes always agree. Returns null for an unresolvable/out-of-scope candidate, so callers can skip in one check. */
    public static String toObjectComponentKey(String candidate) {
        String resolvedName = canonicalInScopeName(candidate);
        if (resolvedName == null) {
            return null;
        }
        return OI_ComponentKeyUtil.build('CustomObject', OI_ComponentKeyUtil.extractNamespaceFromApiName(resolvedName), resolvedName);
    }
}
