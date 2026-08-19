/**
 * Purpose: Resolves display labels for the polymorphic (objectApiName, recordId) references
 *          OI_Hierarchy_Relationship__c/History store — the ADR-0022-mandated per-read
 *          accessibility re-check ("batch-verify object accessibility and re-query the
 *          actual referenced records WITH USER_MODE before returning any relationship row").
 *          Used by every Hierarchy Controller that returns relationship-shaped data; never
 *          bypassed by returning a raw Parent/Child_Record_Id__c label straight from the
 *          junction row, which would leak a value the running user might not actually be
 *          allowed to see.
 * Responsibilities: Batch by distinct object type (one query per type, never one per
 *                    reference — CLAUDE.md's bulkification rule), query WITH USER_MODE,
 *                    return a Map<recordId, label> — a reference that fails the
 *                    accessibility check or resolves to a nonexistent record is silently
 *                    absent from the result, never surfaced as an error (the same
 *                    skip-never-fail discipline OI_RecordHierarchyService already
 *                    establishes for Record Analysis, ADR-0021).
 * Dependencies: OI_RecordSchemaUtil.
 * Limitations: Resolves only the designated Name field per object — the same "one label,
 *              not a full record" scope OI_RecordHierarchyService already keeps to.
 */
public with sharing class OI_HierarchyRecordResolver {
    public class RecordRef {
        public final String objectApiName;
        public final String recordId;

        public RecordRef(String objectApiName, String recordId) {
            this.objectApiName = objectApiName;
            this.recordId = recordId;
        }
    }

    public Map<String, String> resolveLabels(List<RecordRef> refs) {
        Map<String, String> labelByRecordId = new Map<String, String>();
        if (refs == null || refs.isEmpty()) {
            return labelByRecordId;
        }

        Map<String, Set<Id>> idsByObjectApiName = new Map<String, Set<Id>>();
        for (RecordRef ref : refs) {
            if (ref == null || String.isBlank(ref.objectApiName) || String.isBlank(ref.recordId)) {
                continue;
            }
            if (!idsByObjectApiName.containsKey(ref.objectApiName)) {
                idsByObjectApiName.put(ref.objectApiName, new Set<Id>());
            }
            try {
                idsByObjectApiName.get(ref.objectApiName).add((Id) ref.recordId);
            } catch (Exception malformedId) {
                continue;
            }
        }

        for (String objectApiName : idsByObjectApiName.keySet()) {
            Schema.DescribeSObjectResult describe;
            try {
                describe = OI_RecordSchemaUtil.describeAccessibleObject(objectApiName);
            } catch (Exception inaccessibleOrUnknown) {
                continue;
            }
            String nameField = OI_RecordSchemaUtil.resolveNameField(describe);
            if (nameField == null) {
                continue;
            }
            Set<Id> ids = idsByObjectApiName.get(objectApiName);
            String soql = 'SELECT Id, ' + nameField + ' FROM ' + describe.getName() + ' WHERE Id IN :ids';
            List<SObject> rows;
            try {
                rows = Database.query(soql, AccessLevel.USER_MODE);
            } catch (QueryException notActuallyQueryable) {
                continue;
            }
            for (SObject row : rows) {
                labelByRecordId.put((String) row.get('Id'), OI_RecordSchemaUtil.labelFor(row, nameField));
            }
        }
        return labelByRecordId;
    }
}
