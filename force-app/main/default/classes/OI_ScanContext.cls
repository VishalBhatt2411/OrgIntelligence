/**
 * Purpose: Input to OI_IMetadataScanner.scan() (MetadataScanner.md §6).
 * Responsibilities: Carry everything a Scanner needs to run one task — batch size,
 *                    incremental watermark, correlation, preferred API — nothing about the graph.
 * Dependencies: None.
 * Limitations: watermark is null for a full scan. scopedApiNames is an opt-in narrowing for
 *              scanners that support it (currently only OI_FieldScanner) — it exists purely
 *              to let a caller (e.g. a targeted test) avoid the heap cost of a full org-wide
 *              Describe when it only needs a handful of known objects; every real
 *              orchestrator path leaves it null and gets the unfiltered, full-org scan.
 */
public class OI_ScanContext {
    public final Id scanTaskId;
    public final Integer batchSize;
    public final Datetime watermark;
    public final String preferredApi;
    public final Set<String> scopedApiNames;

    public OI_ScanContext(Id scanTaskId, Integer batchSize, Datetime watermark, String preferredApi) {
        this(scanTaskId, batchSize, watermark, preferredApi, null);
    }

    public OI_ScanContext(Id scanTaskId, Integer batchSize, Datetime watermark, String preferredApi, Set<String> scopedApiNames) {
        this.scanTaskId = scanTaskId;
        this.batchSize = batchSize;
        this.watermark = watermark;
        this.preferredApi = preferredApi;
        this.scopedApiNames = scopedApiNames;
    }
}
