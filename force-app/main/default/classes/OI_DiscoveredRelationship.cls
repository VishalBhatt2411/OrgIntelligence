/**
 * Purpose: One Salesforce metadata relationship as discovered by a Scanner, expressed in
 *          Salesforce vocabulary (MetadataScanner.md §5).
 * Responsibilities: Reference two OI_DiscoveredComponent.componentKey values by relationshipKind.
 * Dependencies: None.
 * Limitations: A dangling reference (endpoint not yet discovered this run) is expected and
 *              resolved downstream, never blocked here (GraphEngine.md §6's eventual-consistency
 *              stance, mirrored at the Discovery Model level).
 */
public class OI_DiscoveredRelationship {
    public final String relationshipKey;
    public final String relationshipKind;
    public final String fromComponentKey;
    public final String toComponentKey;
    public final Map<String, Object> rawAttributes;

    public OI_DiscoveredRelationship(
        String relationshipKey,
        String relationshipKind,
        String fromComponentKey,
        String toComponentKey,
        Map<String, Object> rawAttributes
    ) {
        this.relationshipKey = relationshipKey;
        this.relationshipKind = relationshipKind;
        this.fromComponentKey = fromComponentKey;
        this.toComponentKey = toComponentKey;
        this.rawAttributes = rawAttributes == null ? new Map<String, Object>() : rawAttributes;
    }
}
