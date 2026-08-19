/**
 * Purpose: The sole writer of OI_Hierarchy_Relationship__c/OI_Hierarchy_Relationship_History__c
 *          (CodingStandards.md §1's Repository role) — atomically commits a relationship
 *          change and its audit trail together (ADR-0022), mirroring OI_GraphRepository.
 *          commitVersion's Savepoint-guarded atomicity pattern.
 * Responsibilities: One or more relationship upserts (by Relationship_Key__c) plus one
 *                    history insert, in a single Savepoint-guarded transaction — never one
 *                    without the other. A "move" writes two relationship rows (the old one
 *                    deactivated, the new one created/reactivated) alongside a single
 *                    "Moved" history row capturing both the previous and new parent — a plain
 *                    "create" writes one relationship row alongside a "Created" history row.
 * Dependencies: OI_Hierarchy_Relationship__c, OI_Hierarchy_Relationship_History__c.
 * Limitations: with sharing (unlike OI_GraphRepository/OI_LogRepository's without sharing) —
 *              ADR-0022's decision that real Salesforce sharing, not the Apex-boundary model,
 *              governs this subsystem applies to writes as much as reads.
 */
public with sharing class OI_HierarchyRelationshipWriter {
    public void commitChange(OI_Hierarchy_Relationship_History__c historyEntry, List<OI_Hierarchy_Relationship__c> relationships) {
        Savepoint sp = Database.setSavepoint();
        try {
            upsert relationships OI_Hierarchy_Relationship__c.Relationship_Key__c;
            insert historyEntry;
        } catch (DmlException dmlFailure) {
            Database.rollback(sp);
            throw new OI_ServiceException('Unable to save the hierarchy relationship change: ' + dmlFailure.getMessage());
        }
    }
}
