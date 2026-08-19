/**
 * Purpose: Append-only archive backend for superseded/purged node and edge versions
 *          (GraphRepository.md §9) — OI_Graph_Node_Archive__b / OI_Graph_Edge_Archive__b.
 * Responsibilities: Implement the write-and-occasionally-read-back half of
 *                    OI_IGraphStorageProvider. Never implements readCurrent/markSuperseded/
 *                    touchLiveness — those have no meaning for archived data
 *                    (GraphRepository.md §9).
 * Dependencies: OI_Graph_Node_Archive__b, OI_Graph_Edge_Archive__b.
 * Limitations: writeVersion is called only by the scheduled archival job
 *              (OI_GraphArchivalBatch, Roadmap Phase 5 — not built this sprint), never
 *              inline inside commitVersion (GraphRepository.md §9). The read path
 *              (moveToArchive's inverse, "show history") is reserved for a future feature
 *              and is not implemented here — write-only for now (GraphRepository.md §29 Q4).
 */
public without sharing class OI_BigObjectStorageProvider implements OI_IGraphStorageProvider {
    public Map<String, OI_VersionRecord> readCurrent(Set<String> keys, Boolean isEdgeFlavor) {
        throw new OI_ServiceException('Archived data has no concept of "current" (GraphRepository.md §9) — never call readCurrent on the archive provider.');
    }

    public OI_KeysPage readCurrentKeysByType(String typeKey, String cursor, Integer pageSize, Boolean isEdgeFlavor) {
        throw new OI_ServiceException('Retire-detection never reads the archive provider (GraphRepository.md §9) — it is exclusively a Custom Object provider operation.');
    }

    public OI_VersionRecord writeVersion(OI_VersionRecord record, Boolean isNew) {
        if (record.isEdge()) {
            Database.insertImmediate(
                new OI_Graph_Edge_Archive__b(
                    Edge_Version_Key__c = record.versionKey,
                    Edge_Key__c = record.key,
                    Version_Number__c = formatVersionNumber(record.versionNumber),
                    Source_Node_Key__c = record.sourceKey,
                    Target_Node_Key__c = record.targetKey,
                    Edge_Type__c = record.typeKey,
                    State__c = record.state,
                    Attributes_Json__c = OI_JsonUtil.toJson(record.attributes),
                    Scan_Run_Id__c = record.lastSeenRunId,
                    Archived_At__c = Datetime.now()
                )
            );
            return record;
        }
        Database.insertImmediate(
            new OI_Graph_Node_Archive__b(
                Node_Version_Key__c = record.versionKey,
                Node_Key__c = record.key,
                Version_Number__c = formatVersionNumber(record.versionNumber),
                Node_Type__c = record.typeKey,
                Label__c = record.label,
                Secondary_Key__c = record.secondaryKey,
                Parent_Key__c = record.parentKey,
                State__c = record.state,
                Checksum__c = record.checksum,
                Attributes_Json__c = OI_JsonUtil.toJson(record.attributes),
                Scan_Run_Id__c = record.lastSeenRunId,
                Archived_At__c = Datetime.now()
            )
        );
        return record;
    }

    public void markSuperseded(String versionKey, Boolean isEdgeFlavor) {
        throw new OI_ServiceException('Archived rows are never "current" — markSuperseded has no meaning for the archive provider (GraphRepository.md §9).');
    }

    public void touchLiveness(Set<String> keys, Id runId, Boolean isEdgeFlavor) {
        throw new OI_ServiceException('Archived rows are never live — touchLiveness has no meaning for the archive provider (GraphRepository.md §9).');
    }

    public Integer moveToArchive(List<OI_VersionRecord> records) {
        throw new OI_ServiceException('The archive provider is the destination of moveToArchive, never its caller.');
    }

    /** Big Objects store numbers as text-comparable index fields — zero-padded (DataModel.md §3.1). */
    private String formatVersionNumber(Integer versionNumber) {
        String raw = String.valueOf(versionNumber == null ? 0 : versionNumber);
        return raw.leftPad(10, '0');
    }
}
