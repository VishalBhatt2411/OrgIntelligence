/**
 * Purpose: The single, shared definition of which SObjects OI_ObjectScanner and
 *          OI_FieldScanner treat as "CustomObject" components this sprint
 *          (MetadataScanner.md §1's "faithful, not generic" Scanner philosophy, applied
 *          to a real platform-scale bound).
 * Responsibilities: Answer "is this describe result in scope" identically for both
 *                    scanners, so an object either has both a node AND its fields, or
 *                    neither — never a half-scanned object.
 * Dependencies: None.
 * Limitations: Sprint 8 MVP scope, documented explicitly rather than left implicit —
 *              excludes Custom Metadata Types (__mdt), Platform Events (__e), Big Objects
 *              (__b), and External Objects (__x), each a structurally distinct Salesforce
 *              metadata concept that would warrant its own future Scanner/componentKind
 *              rather than being folded into "CustomObject". Also excludes the
 *              automatically-generated companion objects every object gets
 *              (History/Feed/Share/ChangeEvent) — these are platform artifacts of the
 *              underlying object, not independently meaningful metadata components.
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

    public static Boolean isInScope(Schema.DescribeSObjectResult describeResult) {
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
}
