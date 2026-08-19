/**
 * Purpose: The interactive, synchronous-SOQL storage backend for current-version graph data
 *          (GraphRepository.md §8) — OI_Graph_Node__c / OI_Graph_Edge__c.
 * Responsibilities: Implement OI_IGraphStorageProvider by delegating every read to
 *                    OI_NodeSelector/OI_EdgeSelector and every write to insert/update DML.
 *                    Owns the VersionRecord <-> sObject field-mapping knowledge exclusively —
 *                    this mapping never leaks into OI_GraphRepository (GraphRepository.md §4/§5).
 * Dependencies: OI_NodeSelector, OI_EdgeSelector, OI_VersionRecord.
 * Limitations: Write paths run without sharing — these are application-internal records
 *              with no end-user-meaningful owner-based sharing model (ADR-0006,
 *              GraphRepository.md §20). Every insert targets a new version row; a
 *              Database.update/upsert against content fields is never issued here
 *              (CodingStandards.md §4) — the only in-place update is Is_Current__c
 *              (markSuperseded) or Last_Seen_Run__c (touchLiveness).
 */
public without sharing class OI_CustomObjectStorageProvider implements OI_IGraphStorageProvider {
    private final OI_NodeSelector nodeSelector;
    private final OI_EdgeSelector edgeSelector;

    public OI_CustomObjectStorageProvider() {
        this(new OI_NodeSelector(), new OI_EdgeSelector());
    }

    public OI_CustomObjectStorageProvider(OI_NodeSelector nodeSelector, OI_EdgeSelector edgeSelector) {
        this.nodeSelector = nodeSelector;
        this.edgeSelector = edgeSelector;
    }

    public Map<String, OI_VersionRecord> readCurrent(Set<String> keys, Boolean isEdgeFlavor) {
        Map<String, OI_VersionRecord> result = new Map<String, OI_VersionRecord>();
        if (keys == null || keys.isEmpty()) {
            return result;
        }
        if (isEdgeFlavor == true) {
            for (OI_Graph_Edge__c row : edgeSelector.selectCurrentByKeys(keys)) {
                result.put(row.Edge_Key__c, toVersionRecord(row));
            }
        } else {
            for (OI_Graph_Node__c row : nodeSelector.selectCurrentByKeys(keys)) {
                result.put(row.Node_Key__c, toVersionRecord(row));
            }
        }
        return result;
    }

    public OI_KeysPage readCurrentKeysByType(String typeKey, String cursor, Integer pageSize, Boolean isEdgeFlavor) {
        Integer effectivePageSize = pageSize == null ? 200 : pageSize;
        if (isEdgeFlavor == true) {
            List<OI_Graph_Edge__c> rows = edgeSelector.selectCurrentKeysByType(typeKey, cursor, pageSize);
            List<String> keys = new List<String>();
            String nextCursor = null;
            for (OI_Graph_Edge__c row : rows) {
                keys.add(row.Edge_Key__c);
                nextCursor = row.Edge_Version_Key__c;
            }
            return new OI_KeysPage(keys, nextCursor, rows.size() == effectivePageSize);
        }
        List<OI_Graph_Node__c> rows = nodeSelector.selectCurrentKeysByType(typeKey, cursor, pageSize);
        List<String> keys = new List<String>();
        String nextCursor = null;
        for (OI_Graph_Node__c row : rows) {
            keys.add(row.Node_Key__c);
            nextCursor = row.Node_Version_Key__c;
        }
        return new OI_KeysPage(keys, nextCursor, rows.size() == effectivePageSize);
    }

    public OI_VersionRecord writeVersion(OI_VersionRecord record, Boolean isNew) {
        if (record.isEdge()) {
            insert toEdgeSObject(record);
            return record;
        }
        insert toNodeSObject(record);
        return record;
    }

    public void markSuperseded(String versionKey, Boolean isEdgeFlavor) {
        if (isEdgeFlavor == true) {
            List<OI_Graph_Edge__c> edgeRows = [SELECT Id FROM OI_Graph_Edge__c WHERE Edge_Version_Key__c = :versionKey LIMIT 1];
            if (!edgeRows.isEmpty()) {
                edgeRows[0].Is_Current__c = false;
                update edgeRows[0];
            }
            return;
        }
        List<OI_Graph_Node__c> nodeRows = [SELECT Id FROM OI_Graph_Node__c WHERE Node_Version_Key__c = :versionKey LIMIT 1];
        if (!nodeRows.isEmpty()) {
            nodeRows[0].Is_Current__c = false;
            update nodeRows[0];
        }
    }

    public void touchLiveness(Set<String> keys, Id runId, Boolean isEdgeFlavor) {
        if (keys == null || keys.isEmpty()) {
            return;
        }
        if (isEdgeFlavor == true) {
            List<OI_Graph_Edge__c> edgeRows = [
                SELECT Id
                FROM OI_Graph_Edge__c
                WHERE Edge_Key__c IN :keys AND Is_Current__c = true
            ];
            for (OI_Graph_Edge__c row : edgeRows) {
                row.Last_Seen_Run__c = runId;
            }
            if (!edgeRows.isEmpty()) {
                update edgeRows;
            }
            return;
        }
        List<OI_Graph_Node__c> nodeRows = [
            SELECT Id
            FROM OI_Graph_Node__c
            WHERE Node_Key__c IN :keys AND Is_Current__c = true
        ];
        for (OI_Graph_Node__c row : nodeRows) {
            row.Last_Seen_Run__c = runId;
        }
        if (!nodeRows.isEmpty()) {
            update nodeRows;
        }
    }

    /**
     * Archival is a scheduled-batch concern (GraphRepository.md §9), not this provider's —
     * moving rows to the Big Object provider is orchestrated by OI_GraphRepository. This
     * provider only removes rows once told they've been archived elsewhere. Not built this
     * sprint (Roadmap Phase 5).
     */
    public Integer moveToArchive(List<OI_VersionRecord> records) {
        throw new OI_ServiceException('moveToArchive is orchestrated by OI_GraphRepository/OI_GraphArchivalBatch (Roadmap Phase 5) — not built this sprint.');
    }

    private OI_VersionRecord toVersionRecord(OI_Graph_Node__c row) {
        return new OI_VersionRecord(
            row.Node_Key__c,
            row.Node_Version_Key__c,
            Integer.valueOf(row.Version_Number__c),
            row.Node_Type__c,
            row.Label__c,
            row.Secondary_Key__c,
            row.Parent_Key__c,
            OI_JsonUtil.toMap(row.Attributes_Json__c),
            row.Checksum__c,
            row.State__c,
            row.Graph_Scope__c,
            row.First_Seen_Run__c,
            row.Last_Seen_Run__c,
            row.Is_Current__c,
            null,
            null
        );
    }

    private OI_VersionRecord toVersionRecord(OI_Graph_Edge__c row) {
        return new OI_VersionRecord(
            row.Edge_Key__c,
            row.Edge_Version_Key__c,
            Integer.valueOf(row.Version_Number__c),
            row.Edge_Type__c,
            null,
            null,
            null,
            OI_JsonUtil.toMap(row.Attributes_Json__c),
            null,
            row.State__c,
            row.Graph_Scope__c,
            row.First_Seen_Run__c,
            row.Last_Seen_Run__c,
            row.Is_Current__c,
            row.Source_Node_Key__c,
            row.Target_Node_Key__c
        );
    }

    private OI_Graph_Node__c toNodeSObject(OI_VersionRecord record) {
        return new OI_Graph_Node__c(
            Node_Key__c = record.key,
            Node_Version_Key__c = record.versionKey,
            Version_Number__c = record.versionNumber,
            Node_Type__c = record.typeKey,
            Label__c = record.label,
            Secondary_Key__c = record.secondaryKey,
            Parent_Key__c = record.parentKey,
            Attributes_Json__c = OI_JsonUtil.toJson(record.attributes),
            Checksum__c = record.checksum,
            State__c = record.state,
            Graph_Scope__c = record.graphScope,
            First_Seen_Run__c = record.firstSeenRunId,
            Last_Seen_Run__c = record.lastSeenRunId,
            Is_Current__c = record.isCurrent
        );
    }

    private OI_Graph_Edge__c toEdgeSObject(OI_VersionRecord record) {
        return new OI_Graph_Edge__c(
            Edge_Key__c = record.key,
            Edge_Version_Key__c = record.versionKey,
            Version_Number__c = record.versionNumber,
            Edge_Type__c = record.typeKey,
            Source_Node_Key__c = record.sourceKey,
            Target_Node_Key__c = record.targetKey,
            Attributes_Json__c = OI_JsonUtil.toJson(record.attributes),
            State__c = record.state,
            Graph_Scope__c = record.graphScope,
            First_Seen_Run__c = record.firstSeenRunId,
            Last_Seen_Run__c = record.lastSeenRunId,
            Is_Current__c = record.isCurrent
        );
    }
}
