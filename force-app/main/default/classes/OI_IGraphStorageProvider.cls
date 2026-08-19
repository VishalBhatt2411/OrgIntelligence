/**
 * Purpose: The interface every durable graph storage backend implements
 *          (GraphRepository.md §3).
 * Responsibilities: Define the six operations OI_GraphRepository dispatches to, one
 *                    implementation per backend (Custom Object, Big Object, future backends).
 * Dependencies: OI_VersionRecord.
 * Limitations: Not implemented by the Platform Cache provider — that backend has no notion
 *              of "current version" or archival and implements the smaller
 *              OI_IKeyValueCacheProvider instead (GraphRepository.md §3, §10).
 */
public interface OI_IGraphStorageProvider {
    /**
     * isEdgeFlavor tells the provider which object to query — a keyset alone cannot say
     * whether it names nodes or edges, and GraphRepository.md §1's "never mixed in one
     * call" rule means the caller always knows this already. This is a documented,
     * additive precision on top of GraphRepository.md §2's contract sketch, not a deviation
     * from it.
     */
    Map<String, OI_VersionRecord> readCurrent(Set<String> keys, Boolean isEdgeFlavor);

    OI_KeysPage readCurrentKeysByType(String typeKey, String cursor, Integer pageSize, Boolean isEdgeFlavor);

    OI_VersionRecord writeVersion(OI_VersionRecord record, Boolean isNew);

    void markSuperseded(String versionKey, Boolean isEdgeFlavor);

    void touchLiveness(Set<String> keys, Id runId, Boolean isEdgeFlavor);

    Integer moveToArchive(List<OI_VersionRecord> records);
}
