/**
 * Purpose: The envelope one Scan Task returns — the sole return type of
 *          OI_IMetadataScanner.scan() (MetadataScanner.md §5).
 * Responsibilities: Carry every component/relationship discovered for one componentKind in
 *                    one task, plus the full-snapshot flag that gates retire-detection.
 * Dependencies: OI_DiscoveredComponent, OI_DiscoveredRelationship.
 * Limitations: isFullSnapshot must only be true if every chunk of this type's fetch
 *              succeeded (MetadataScanner.md §21) — enforced by the caller, not this class.
 */
public class OI_DiscoveryBatch {
    public final Id scanTaskId;
    public final String componentKind;
    public final List<OI_DiscoveredComponent> components;
    public final List<OI_DiscoveredRelationship> relationships;
    public final Boolean isFullSnapshot;
    public final Integer apiCallsConsumed;
    /**
     * This Scanner's own declaration of how complete its relationship extraction was — see
     * OI_ScanCoverage for why an intelligence product must never present a possibly-incomplete
     * graph as complete. Never null: the legacy constructor defaults it to COMPLETE, which is
     * the correct reading for the structural scanners (Object/Field) that have no degradable
     * extraction step.
     */
    public final OI_ScanCoverage coverage;

    /** Legacy constructor — coverage defaults to COMPLETE. Retained so the chunked-ingest paths, which rebuild a batch purely to carry a slice of already-discovered data, do not need to restate a coverage they never computed. */
    public OI_DiscoveryBatch(
        Id scanTaskId,
        String componentKind,
        List<OI_DiscoveredComponent> components,
        List<OI_DiscoveredRelationship> relationships,
        Boolean isFullSnapshot,
        Integer apiCallsConsumed
    ) {
        this(scanTaskId, componentKind, components, relationships, isFullSnapshot, apiCallsConsumed, null);
    }

    public OI_DiscoveryBatch(
        Id scanTaskId,
        String componentKind,
        List<OI_DiscoveredComponent> components,
        List<OI_DiscoveredRelationship> relationships,
        Boolean isFullSnapshot,
        Integer apiCallsConsumed,
        OI_ScanCoverage coverage
    ) {
        this.scanTaskId = scanTaskId;
        this.componentKind = componentKind;
        this.components = components == null ? new List<OI_DiscoveredComponent>() : components;
        this.relationships = relationships == null ? new List<OI_DiscoveredRelationship>() : relationships;
        this.isFullSnapshot = isFullSnapshot == null ? false : isFullSnapshot;
        this.apiCallsConsumed = apiCallsConsumed == null ? 0 : apiCallsConsumed;
        this.coverage = coverage == null ? OI_ScanCoverage.complete(this.relationships.size()) : coverage;
    }
}
