/**
 * Purpose: The only component, anywhere in the platform, that issues a storage operation
 *          against node/edge data (GraphRepository.md §1) — Scanner → Graph Builder →
 *          Graph Repository → Storage.
 * Responsibilities: Implement the five-operation contract (GraphRepository.md §2) by
 *                    dispatching to Storage Providers, never by branching on backend type
 *                    inline. Owns the commitVersion atomicity fix (§6) and the optimistic
 *                    concurrency translation (§15) — the two correctness-critical behaviors
 *                    this layer exists to provide.
 * Dependencies: OI_IGraphStorageProvider (Custom Object + Big Object providers, injected).
 * Limitations: This sprint ships getCurrentVersions, getCurrentKeysByType, commitVersion,
 *              and touchLiveness at full strength — archiveSupersededVersions is a
 *              documented seam only (Roadmap Phase 5, GraphRepository.md §9); nothing in
 *              this sprint calls it. No business logic beyond what §2 specifies —
 *              OI_GraphBuilder (not built this sprint per Sprint 7 scope) owns the
 *              three-way version decision this Repository's contract supports.
 */
public without sharing class OI_GraphRepository {
    private final OI_IGraphStorageProvider customObjectProvider;
    private final OI_IGraphStorageProvider bigObjectProvider;

    public OI_GraphRepository() {
        this(new OI_CustomObjectStorageProvider(), new OI_BigObjectStorageProvider());
    }

    public OI_GraphRepository(OI_IGraphStorageProvider customObjectProvider, OI_IGraphStorageProvider bigObjectProvider) {
        this.customObjectProvider = customObjectProvider;
        this.bigObjectProvider = bigObjectProvider;
    }

    /**
     * Bulk lookup of the current version for each key in the set (GraphRepository.md §2).
     * Keys with no current version are simply absent from the result.
     */
    public Map<String, OI_VersionRecord> getCurrentVersions(Set<String> keys, Boolean isEdgeFlavor) {
        return customObjectProvider.readCurrent(keys, isEdgeFlavor);
    }

    /**
     * Paginated enumeration of every currently-Active key for a typeKey — the operation
     * retire-detection needs (GraphRepository.md §2, §9).
     */
    public OI_KeysPage getCurrentKeysByType(String typeKey, String cursor, Integer pageSize, Boolean isEdgeFlavor) {
        return customObjectProvider.readCurrentKeysByType(typeKey, cursor, pageSize, isEdgeFlavor);
    }

    /**
     * Atomically inserts newVersionRecord and, if supersededVersionKey is present, flips
     * that row's Is_Current__c to false — both within one Savepoint-guarded transaction
     * (GraphRepository.md §6, ADR-0016). A DUPLICATE_VALUE conflict on the insert is
     * translated to OI_ConcurrencyException (§15) rather than propagated as a raw
     * DmlException.
     */
    public OI_VersionRecord commitVersion(OI_VersionRecord newVersionRecord, String supersededVersionKey) {
        Savepoint sp = Database.setSavepoint();
        try {
            OI_VersionRecord committed = customObjectProvider.writeVersion(newVersionRecord, supersededVersionKey == null);
            if (String.isNotBlank(supersededVersionKey)) {
                customObjectProvider.markSuperseded(supersededVersionKey, newVersionRecord.isEdge());
            }
            return committed;
        } catch (DmlException e) {
            Database.rollback(sp);
            if (isDuplicateValueConflict(e)) {
                throw new OI_ConcurrencyException('Concurrent write detected for versionKey ' + newVersionRecord.versionKey + ' — retry with a fresh read of the current version.');
            }
            throw e;
        }
    }

    /**
     * Updates Last_Seen_Run__c in place, in bulk, on the current row for every key in the
     * set — the one operation, alongside the supersede-flip inside commitVersion, that
     * changes a value on an existing row (GraphRepository.md §2). Bulk-shaped since Sprint
     * 8: OI_GraphBuilder's liveness-touch path (GraphEngine.md §7, decision path 2) is the
     * common case for most observations in a scan, so a single-key overload here would be
     * exactly the query/DML-in-a-loop pattern CLAUDE.md's bulkification rule forbids.
     */
    public void touchLiveness(Set<String> keys, Id runId, Boolean isEdgeFlavor) {
        customObjectProvider.touchLiveness(keys, runId, isEdgeFlavor);
    }

    /**
     * Moves non-current version rows past the retention window to the Big Object provider
     * (GraphRepository.md §2, §9). Not exercised this sprint — the scheduled archival job
     * (OI_GraphArchivalBatch) that calls this is Roadmap Phase 5 work.
     */
    public Integer archiveSupersededVersions(Datetime cutoff) {
        throw new OI_ServiceException('archiveSupersededVersions is called by the scheduled OI_GraphArchivalBatch job (Roadmap Phase 5) — not built this sprint.');
    }

    /**
     * getNumDml()/getDmlType() are safe and meaningful on any DmlException the platform
     * itself populated from a real failed DML statement — which is exactly what
     * commitVersion's catch block always receives, since customObjectProvider.writeVersion
     * only ever fails via a genuine insert. (A manually-constructed DmlException — never
     * produced by this class — is not a case this method needs to guard against; calling
     * these accessors on one is undefined platform behavior with no way to guard against
     * it at all, confirmed during Sprint 7 validation — see the deliverables report.)
     */
    private Boolean isDuplicateValueConflict(DmlException e) {
        for (Integer i = 0; i < e.getNumDml(); i++) {
            if (e.getDmlType(i) == StatusCode.DUPLICATE_VALUE) {
                return true;
            }
        }
        return false;
    }
}
