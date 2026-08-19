/**
 * Purpose: Runtime availability gate for the four scan-coverage fields on OI_Scan_Task__c
 *          (Coverage_Status__c, Coverage_Detail__c, Relationships_Discovered__c,
 *          Relationships_Skipped__c), so coverage reporting degrades to a no-op instead of
 *          throwing when those fields are not visible in the running org.
 * Responsibilities: Answer "can I read/write the coverage fields here?" once per transaction,
 *                    and provide the dynamic read/write paths that answer depends on.
 * Dependencies: Schema describe only.
 *
 * Why this exists — a real, reproduced org-level defect, not defensive paranoia:
 * in the `entTrial` org this package is validated against, these four fields deploy
 * successfully (the deploy reports them as present, and Apex referencing them COMPILES and
 * DEPLOYS without error), yet they remain invisible to both `Schema.describe` and SOQL. A static
 * `SELECT Coverage_Status__c FROM OI_Scan_Task__c` therefore throws
 * `System.QueryException: No such column` at RUNTIME in an org where the very same field
 * reference compiled fine. This is a known behaviour of that org — previously hit on a different
 * field in this same package, and resolved only by re-creating the field through the Setup UI.
 *
 * Two consequences shape this class:
 *  1. Coverage reporting must never be load-bearing for a scan. A scan's job is to produce graph
 *     data; failing that because a diagnostic field is missing would trade something valuable for
 *     something merely useful. Every path here is best-effort.
 *  2. Field access must be DYNAMIC (`Schema.describe` + `Database.query`), because static field
 *     references are exactly what cannot be relied upon here. That is the only reason this class
 *     uses dynamic SOQL, which this codebase otherwise avoids — the justification is recorded
 *     here rather than left as an unexplained deviation from CodingStandards.
 *
 * The moment the fields become genuinely visible (created via Setup UI, or in any org without
 * this defect), every method here starts working with no code change and no configuration.
 */
public inherited sharing class OI_ScanCoverageFields {
    private static final String STATUS_FIELD = 'Coverage_Status__c';
    private static final String DETAIL_FIELD = 'Coverage_Detail__c';
    private static final String DISCOVERED_FIELD = 'Relationships_Discovered__c';
    private static final String SKIPPED_FIELD = 'Relationships_Skipped__c';

    /** Memoized per transaction — a describe call per coverage write during a large scan would be pure waste. */
    private static Boolean available;

    /**
     * True only when every coverage field is actually visible AND updateable. All-or-nothing
     * deliberately: a partially-visible set would produce half-populated coverage rows, which is
     * more misleading to an admin than no coverage data at all.
     */
    public static Boolean isAvailable() {
        if (available == null) {
            Map<String, Schema.SObjectField> fields = Schema.SObjectType.OI_Scan_Task__c.fields.getMap();
            available =
                isUsable(fields, STATUS_FIELD) &&
                isUsable(fields, DETAIL_FIELD) &&
                isUsable(fields, DISCOVERED_FIELD) &&
                isUsable(fields, SKIPPED_FIELD);
        }
        return available;
    }

    private static Boolean isUsable(Map<String, Schema.SObjectField> fields, String fieldName) {
        Schema.SObjectField field = fields.get(fieldName.toLowerCase());
        return field != null && field.getDescribe().isUpdateable();
    }

    /** Writes a Scanner's coverage declaration onto its task. No-op when the fields are unavailable. */
    public static void writeCoverage(Id scanTaskId, OI_ScanCoverage coverage) {
        if (!isAvailable() || scanTaskId == null || coverage == null) {
            return;
        }
        /** The OBJECT is always visible here — only its coverage FIELDS are not — so a static sObject with dynamic put() is both safe and cheaper than a getGlobalDescribe round-trip. */
        OI_Scan_Task__c task = new OI_Scan_Task__c(Id = scanTaskId);
        task.put(DISCOVERED_FIELD, coverage.relationshipsDiscovered);
        task.put(STATUS_FIELD, coverage.status);
        task.put(DETAIL_FIELD, coverage.reason);
        update task;
    }

    /** Adds to the task's skipped tally. Additive because chunked ingestion discovers skips across many Batch Apex scopes, each knowing only its own share. */
    public static void addSkipped(Id scanTaskId, Integer skippedCount) {
        if (!isAvailable() || scanTaskId == null || skippedCount == null || skippedCount <= 0) {
            return;
        }
        List<SObject> existing = Database.query('SELECT Id, ' + SKIPPED_FIELD + ' FROM OI_Scan_Task__c WHERE Id = :scanTaskId LIMIT 1');
        if (existing.isEmpty()) {
            return;
        }
        Object current = existing[0].get(SKIPPED_FIELD);
        Decimal currentValue = current == null ? 0 : (Decimal) current;
        OI_Scan_Task__c task = new OI_Scan_Task__c(Id = scanTaskId);
        task.put(SKIPPED_FIELD, currentValue + skippedCount);
        update task;
    }

    /**
     * Whether any task on the given run reported less-than-Complete coverage. Returns false when
     * the fields are unavailable — the honest reading, since "we cannot tell" must not be
     * presented to a user as "there are limitations" (which would be a fabricated warning) nor
     * suppress the separate, always-shown per-section coverage notes that do not depend on these
     * fields at all.
     */
    public static Boolean hasLimitations(Id scanRunId) {
        if (!isAvailable() || scanRunId == null) {
            return false;
        }
        /** Bound by name into the dynamic query below — declared here rather than inlined so the query text stays free of concatenated literals. */
        String completeStatus = OI_ScanCoverage.STATUS_COMPLETE;
        List<SObject> limited = Database.query(
            'SELECT Id FROM OI_Scan_Task__c WHERE Scan_Run__c = :scanRunId AND ' +
            STATUS_FIELD + ' != NULL AND ' + STATUS_FIELD + ' != :completeStatus LIMIT 1'
        );
        return !limited.isEmpty();
    }

    /** Reset hook for tests that need to re-evaluate availability within one transaction. */
    @TestVisible
    private static void clearCacheForTests() {
        available = null;
    }
}
