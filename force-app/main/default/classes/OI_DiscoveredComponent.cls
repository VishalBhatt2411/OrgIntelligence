/**
 * Purpose: One Salesforce metadata component as discovered by a Scanner, expressed entirely
 *          in Salesforce vocabulary (MetadataScanner.md §5).
 * Responsibilities: Carry componentKey/componentKind/attributes for one discovered component.
 *                    Deliberately knows nothing about Graph typeKey/nodeKey vocabulary —
 *                    that translation is OI_MutationGenerator's job alone.
 * Dependencies: None.
 * Limitations: rawAttributes deliberately excludes secret-bearing values (MetadataScanner.md §19).
 */
public class OI_DiscoveredComponent {
    public final String componentKey;
    public final String componentKind;
    public final String fullyQualifiedName;
    public final String namespace;
    public final String sourceApi;
    public final Map<String, Object> rawAttributes;
    public final String rawChecksum;
    public final Datetime sourceModstamp;
    public final String parentComponentKey;

    public OI_DiscoveredComponent(
        String componentKey,
        String componentKind,
        String fullyQualifiedName,
        String namespace,
        String sourceApi,
        Map<String, Object> rawAttributes,
        String rawChecksum,
        Datetime sourceModstamp,
        String parentComponentKey
    ) {
        this.componentKey = componentKey;
        this.componentKind = componentKind;
        this.fullyQualifiedName = fullyQualifiedName;
        this.namespace = namespace;
        this.sourceApi = sourceApi;
        this.rawAttributes = rawAttributes == null ? new Map<String, Object>() : rawAttributes;
        this.rawChecksum = rawChecksum;
        this.sourceModstamp = sourceModstamp;
        this.parentComponentKey = parentComponentKey;
    }
}
