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
 * Limitations: Archival (ADR-0031) is split into archiveSupersededVersions and
 *              purgeArchivedVersions because Big Object insertImmediate and sObject DML
 *              must run in separate transactions; OI_GraphArchivalBatch sequences the two.
 *              No business logic beyond what §2 specifies —
 *              OI_GraphBuilder (not built this sprint per Sprint 7 scope) owns the
 *              three-way version decision this Repository's contract supports.
 */
public without sharing class OI_GraphRepository {
  private final OI_IGraphStorageProvider customObjectProvider;
  private final OI_IGraphStorageProvider bigObjectProvider;

  public OI_GraphRepository() {
    this(
      new OI_CustomObjectStorageProvider(),
      new OI_BigObjectStorageProvider()
    );
  }

  public OI_GraphRepository(
    OI_IGraphStorageProvider customObjectProvider,
    OI_IGraphStorageProvider bigObjectProvider
  ) {
    this.customObjectProvider = customObjectProvider;
    this.bigObjectProvider = bigObjectProvider;
  }

  /**
   * Bulk lookup of the current version for each key in the set (GraphRepository.md §2).
   * Keys with no current version are simply absent from the result.
   */
  public Map<String, OI_VersionRecord> getCurrentVersions(
    Set<String> keys,
    Boolean isEdgeFlavor
  ) {
    return customObjectProvider.readCurrent(keys, isEdgeFlavor);
  }

  /**
   * Paginated enumeration of every currently-Active key for a typeKey — the operation
   * retire-detection needs (GraphRepository.md §2, §9).
   */
  public OI_KeysPage getCurrentKeysByType(
    String typeKey,
    String cursor,
    Integer pageSize,
    Boolean isEdgeFlavor
  ) {
    return customObjectProvider.readCurrentKeysByType(
      typeKey,
      cursor,
      pageSize,
      isEdgeFlavor
    );
  }

  /**
   * Atomically inserts newVersionRecord and, if supersededVersionKey is present, flips
   * that row's Is_Current__c to false — both within one Savepoint-guarded transaction
   * (GraphRepository.md §6, ADR-0016). A DUPLICATE_VALUE conflict on the insert is
   * translated to OI_ConcurrencyException (§15) rather than propagated as a raw
   * DmlException.
   */
  public OI_VersionRecord commitVersion(
    OI_VersionRecord newVersionRecord,
    String supersededVersionKey
  ) {
    Savepoint sp = Database.setSavepoint();
    try {
      OI_VersionRecord committed = customObjectProvider.writeVersion(
        newVersionRecord,
        supersededVersionKey == null
      );
      if (String.isNotBlank(supersededVersionKey)) {
        customObjectProvider.markSuperseded(
          supersededVersionKey,
          newVersionRecord.isEdge()
        );
      }
      return committed;
    } catch (DmlException e) {
      Database.rollback(sp);
      if (isDuplicateValueConflict(e)) {
        throw new OI_ConcurrencyException(
          'Concurrent write detected for versionKey ' +
            newVersionRecord.versionKey +
            ' — retry with a fresh read of the current version.'
        );
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
   * The archival scope for one flavor (GraphRepository.md §9, ADR-0031): non-current rows
   * last modified at or before the cutoff. Reads the selectors directly, like the count
   * methods below — a Batch Apex query locator is inherently a Custom Object concern.
   */
  public Database.QueryLocator locateSupersededVersions(
    Datetime cutoff,
    Boolean isEdgeFlavor
  ) {
    return isEdgeFlavor == true
      ? new OI_EdgeSelector().queryLocatorSupersededBefore(cutoff)
      : new OI_NodeSelector().queryLocatorSupersededBefore(cutoff);
  }

  /**
   * Copies the given superseded versions to the Big Object archive (GraphRepository.md §2,
   * §9). Writes only — the live rows are removed later by purgeArchivedVersions in a
   * separate transaction. Idempotent: the archive's index is the version key, so re-archiving
   * a version overwrites it rather than duplicating it. Returns the number archived.
   */
  public Integer archiveSupersededVersions(
    Set<String> versionKeys,
    Boolean isEdgeFlavor
  ) {
    List<OI_VersionRecord> records = customObjectProvider.readSupersededByVersionKeys(
      versionKeys,
      isEdgeFlavor
    );
    for (OI_VersionRecord record : records) {
      bigObjectProvider.writeVersion(record, true);
    }
    return records.size();
  }

  /** Removes already-archived superseded versions from the Custom Object provider. Returns the number removed. */
  public Integer purgeArchivedVersions(
    Set<String> versionKeys,
    Boolean isEdgeFlavor
  ) {
    return customObjectProvider.moveToArchive(
      customObjectProvider.readSupersededByVersionKeys(
        versionKeys,
        isEdgeFlavor
      )
    );
  }

  /**
   * Aggregate current node counts by type — Org Health's Org Overview KPI strip (ADR-0026).
   * Reads directly via OI_NodeSelector rather than the customObjectProvider interface: this
   * is a pure current-state aggregate with no version/archive semantics, so the
   * archive-aware Provider abstraction has nothing to add — the same reasoning
   * getCurrentVersions/getCurrentKeysByType above don't need either. Originally lived on
   * OI_GraphEngine directly; moved here so the Engine stays a pure pass-through facade
   * (ADR-0013) and every node/edge storage read funnels through this one Repository class
   * (GraphRepository.md §1), never through OI_GraphEngine instantiating a Selector itself.
   */
  public Map<String, Integer> countCurrentNodesByType(Set<String> typeKeys) {
    return new OI_NodeSelector().countCurrentByType(typeKeys);
  }

  /** Total current edge count, unfiltered — Org Health's Org Overview "Relationships" KPI (ADR-0026). See countCurrentNodesByType's doc comment for why this reads directly via OI_EdgeSelector. */
  public Integer countCurrentEdgesTotal() {
    return new OI_EdgeSelector().countCurrentTotal();
  }

  /** Current edge count restricted to the given edge type keys — Org Health's Org Overview "Dependencies" KPI (ADR-0026). */
  public Integer countCurrentEdgesByType(Set<String> edgeTypeKeys) {
    return new OI_EdgeSelector().countCurrentByTypes(edgeTypeKeys);
  }

  /** Bounded current nodes of a type, key + label only — Metadata Health's live object enumeration (ADR-0026 Phase 2). */
  public List<OI_Graph_Node__c> selectCurrentNodesByTypeBounded(
    String typeKey,
    Integer ceiling
  ) {
    return new OI_NodeSelector().selectCurrentByTypeBounded(typeKey, ceiling);
  }

  /** Aggregate edge counts by Source_Node_Key__c for a bounded key/type set — Metadata Health's per-object field count (ADR-0026 Phase 2). */
  public Map<String, Integer> countCurrentEdgesBySourceKeysGroupedByKey(
    Set<String> sourceNodeKeys,
    Set<String> edgeTypeKeys
  ) {
    return new OI_EdgeSelector()
      .countCurrentBySourceKeysGroupedByKey(sourceNodeKeys, edgeTypeKeys);
  }

  /** Aggregate edge counts by Target_Node_Key__c for a bounded key/type set — Metadata Health's per-object incoming degree (ADR-0026 Phase 2). */
  public Map<String, Integer> countCurrentEdgesByTargetKeysGroupedByKey(
    Set<String> targetNodeKeys,
    Set<String> edgeTypeKeys
  ) {
    return new OI_EdgeSelector()
      .countCurrentByTargetKeysGroupedByKey(targetNodeKeys, edgeTypeKeys);
  }

  /** Aggregate edge counts by Target_Node_Key__c, filtered by SOURCE key set — Automation Health's per-object automation count (ADR-0026 Phase 3). */
  public Map<String, Integer> countCurrentEdgesBySourceKeysGroupedByTargetKey(
    Set<String> sourceNodeKeys,
    Set<String> edgeTypeKeys
  ) {
    return new OI_EdgeSelector()
      .countCurrentBySourceKeysGroupedByTargetKey(sourceNodeKeys, edgeTypeKeys);
  }

  /** Current edges with both endpoints inside a bounded key set — Automation/Code Health's cycle-detection read (ADR-0026 Phase 3). */
  public List<OI_Graph_Edge__c> selectCurrentEdgesBetweenKeys(
    Set<String> nodeKeys,
    Set<String> edgeTypeKeys
  ) {
    return new OI_EdgeSelector()
      .selectCurrentBetweenKeys(nodeKeys, edgeTypeKeys);
  }

  /** Bulk API-name (Secondary_Key__c) lookup by key set — classification and other identity-sensitive reads that must never read the friendly Label__c instead (ADR-0027 correction). */
  public Map<String, String> selectCurrentSecondaryKeysByKeys(
    Set<String> nodeKeys
  ) {
    return new OI_NodeSelector().selectSecondaryKeysByKeys(nodeKeys);
  }

  /** Bulk Field-node lookup by owning-object parent-key set — Metadata Health's per-object custom field count (ADR-0027 correction). */
  public List<OI_Graph_Node__c> selectCurrentFieldNodesByParentKeys(
    Set<String> parentKeys,
    String fieldNodeTypeKey,
    Integer rowCeiling
  ) {
    return new OI_NodeSelector()
      .selectCurrentFieldNodesByParentKeys(
        parentKeys,
        fieldNodeTypeKey,
        rowCeiling
      );
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
