/**
 * Purpose: In-memory fake implementing OI_IGraphStorageProvider, so OI_GraphRepository
 *          can be unit-tested without real Custom Object/Big Object DML
 *          (GraphRepository.md §23).
 * Responsibilities: Mimic the real provider's read/write semantics, including real
 *                    keyset pagination in readCurrentKeysByType (Sprint 9 — needed to
 *                    exercise OI_MutationGenerator's retire-detection pagination logic
 *                    (findMissingKeys, Sprint 9.1) at scale without real DML/governor-limit
 *                    exposure).
 * Dependencies: OI_VersionRecord.
 * Limitations: Test-only — annotated @isTest. Deliberately never throws DmlException —
 *              calling getNumDml()/getDmlType() (as OI_GraphRepository.commitVersion
 *              does) on a manually-constructed DmlException raises an uncatchable
 *              platform-level UnexpectedException (confirmed empirically). The real
 *              DUPLICATE_VALUE conflict path is tested against the real
 *              OI_CustomObjectStorageProvider instead (GraphRepository.md §23),
 *              where a genuine failed DML statement makes those calls safe.
 */
@isTest
public class OI_FakeGraphStorageProvider implements OI_IGraphStorageProvider {
    public Map<String, OI_VersionRecord> versionsByKey = new Map<String, OI_VersionRecord>();
    public Map<String, OI_VersionRecord> versionsByVersionKey = new Map<String, OI_VersionRecord>();

    public Map<String, OI_VersionRecord> readCurrent(Set<String> keys, Boolean isEdgeFlavor) {
        Map<String, OI_VersionRecord> result = new Map<String, OI_VersionRecord>();
        for (String key : keys) {
            if (versionsByKey.containsKey(key) && versionsByKey.get(key).isCurrent == true) {
                result.put(key, versionsByKey.get(key));
            }
        }
        return result;
    }

    /** Real keyset pagination (sorted key order) — mirrors OI_NodeSelector/OI_EdgeSelector's cursor/pageSize/hasMore contract closely enough for chunking tests. */
    public OI_KeysPage readCurrentKeysByType(String typeKey, String cursor, Integer pageSize, Boolean isEdgeFlavor) {
        List<String> matchingKeys = new List<String>();
        for (OI_VersionRecord record : versionsByKey.values()) {
            if (record.typeKey == typeKey && record.isCurrent == true && record.state == 'Active') {
                matchingKeys.add(record.key);
            }
        }
        matchingKeys.sort();

        Integer startIndex = 0;
        if (String.isNotBlank(cursor)) {
            for (Integer i = 0; i < matchingKeys.size(); i++) {
                if (matchingKeys[i] == cursor) {
                    startIndex = i + 1;
                    break;
                }
            }
        }
        Integer effectivePageSize = pageSize == null ? 200 : pageSize;
        Integer endIndex = Math.min(startIndex + effectivePageSize, matchingKeys.size());
        List<String> page = new List<String>();
        for (Integer i = startIndex; i < endIndex; i++) {
            page.add(matchingKeys[i]);
        }
        String nextCursor = page.isEmpty() ? cursor : page[page.size() - 1];
        return new OI_KeysPage(page, nextCursor, endIndex < matchingKeys.size());
    }

    public OI_VersionRecord writeVersion(OI_VersionRecord record, Boolean isNew) {
        versionsByKey.put(record.key, record);
        versionsByVersionKey.put(record.versionKey, record);
        return record;
    }

    public void markSuperseded(String versionKey, Boolean isEdgeFlavor) {
        if (!versionsByVersionKey.containsKey(versionKey)) {
            return;
        }
        OI_VersionRecord existing = versionsByVersionKey.get(versionKey);
        OI_VersionRecord superseded = new OI_VersionRecord(
            existing.key,
            existing.versionKey,
            existing.versionNumber,
            existing.typeKey,
            existing.label,
            existing.secondaryKey,
            existing.parentKey,
            existing.attributes,
            existing.checksum,
            existing.state,
            existing.graphScope,
            existing.firstSeenRunId,
            existing.lastSeenRunId,
            false,
            existing.sourceKey,
            existing.targetKey
        );
        versionsByVersionKey.put(versionKey, superseded);
        if (versionsByKey.containsKey(existing.key) && versionsByKey.get(existing.key).versionKey == versionKey) {
            versionsByKey.put(existing.key, superseded);
        }
    }

    public void touchLiveness(Set<String> keys, Id runId, Boolean isEdgeFlavor) {
        for (String key : keys) {
            if (!versionsByKey.containsKey(key)) {
                continue;
            }
            OI_VersionRecord existing = versionsByKey.get(key);
            OI_VersionRecord touched = new OI_VersionRecord(
                existing.key,
                existing.versionKey,
                existing.versionNumber,
                existing.typeKey,
                existing.label,
                existing.secondaryKey,
                existing.parentKey,
                existing.attributes,
                existing.checksum,
                existing.state,
                existing.graphScope,
                existing.firstSeenRunId,
                runId,
                existing.isCurrent,
                existing.sourceKey,
                existing.targetKey
            );
            versionsByKey.put(key, touched);
            versionsByVersionKey.put(existing.versionKey, touched);
        }
    }

    public Integer moveToArchive(List<OI_VersionRecord> records) {
        return records == null ? 0 : records.size();
    }
}
