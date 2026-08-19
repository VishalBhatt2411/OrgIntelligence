/**
 * Purpose: Shared Schema/describe helpers for Record Analysis (ADR-0021) — used by both
 *          OI_RecordSearchService and OI_RecordHierarchyService so "resolve this object's
 *          Name field" and "is this object safe to query" are decided in exactly one place.
 * Responsibilities: Validate an arbitrary customer object API name against the global
 *                    describe (never string-built into SOQL directly — CLAUDE.md
 *                    §Security); resolve the platform-designated Name field for any object,
 *                    since not every object calls it "Name" (CLAUDE.md §Metadata
 *                    Assumptions).
 * Dependencies: None.
 * Limitations: None.
 */
public inherited sharing class OI_RecordSchemaUtil {
    public static Schema.DescribeSObjectResult describeAccessibleObject(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            throw new OI_ValidationException('An object API name is required.');
        }
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName.toLowerCase());
        if (sObjectType == null) {
            throw new OI_ValidationException('Unknown object: ' + objectApiName);
        }
        Schema.DescribeSObjectResult describe = sObjectType.getDescribe();
        if (!describe.isAccessible() || !describe.isQueryable()) {
            throw new OI_SecurityException('Access denied.');
        }
        return describe;
    }

    /** The first field flagged as this object's designated Name field, if the running user can see it — null if the object has none (some objects genuinely don't) or it isn't accessible. */
    public static String resolveNameField(Schema.DescribeSObjectResult describe) {
        for (Schema.SObjectField field : describe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (fieldDescribe.isNameField() && fieldDescribe.isAccessible()) {
                return fieldDescribe.getName();
            }
        }
        return null;
    }

    /**
     * Validates both the lexical Id shape and its embedded SObject type before any dynamic
     * record query is assembled. The Id remains a bind variable either way, but rejecting an
     * Account/Contact mismatch here produces a deterministic validation response instead of
     * an empty or platform-specific query result and prevents callers from probing arbitrary
     * object/Id combinations through this package boundary.
     */
    public static Id validateRecordIdForObject(Schema.DescribeSObjectResult describe, String recordId) {
        if (String.isBlank(recordId)) {
            throw new OI_ValidationException('A record Id is required.');
        }
        Id typedId;
        try {
            typedId = Id.valueOf(recordId.trim());
        } catch (Exception invalidId) {
            throw new OI_ValidationException('The record Id is not valid.');
        }
        if (typedId.getSObjectType() != describe.getSObjectType()) {
            throw new OI_ValidationException('The record Id does not belong to ' + describe.getName() + '.');
        }
        return typedId;
    }

    public static String labelFor(SObject record, String nameField) {
        Object rawValue = record.get(nameField);
        return rawValue == null ? '(no name)' : String.valueOf(rawValue);
    }

    /** A record's graph-canvas node key — namespaced distinctly from every metadata nodeKey format so the two can never collide (ADR-0021: records are a parallel, never-persisted concern). */
    public static String recordNodeKey(String objectApiName, String recordId) {
        return 'Record::' + objectApiName + '::' + recordId;
    }

    public static String recordTypeKey(String objectApiName) {
        return 'SalesforceRecord.' + objectApiName;
    }
}
