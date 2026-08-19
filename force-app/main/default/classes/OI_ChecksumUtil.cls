/**
 * Purpose: The single, shared canonicalization + hashing routine every Scanner uses to
 *          compute OI_DiscoveredComponent.rawChecksum (MetadataScanner.md §5 — "Hash over
 *          componentKind + fullyQualifiedName + rawAttributes").
 * Responsibilities: Sort attribute keys before hashing so the same content always produces
 *                    the same checksum regardless of Map iteration order (Apex Maps make no
 *                    ordering guarantee) — the correctness property MetadataScanner.md §21
 *                    ("the same component scanned twice must generate the same identity")
 *                    actually depends on. Centralized once so three Scanners can't silently
 *                    diverge on the formula.
 * Dependencies: OI_HashUtil.
 * Limitations: Values are canonicalized via String.valueOf() — sufficient for the primitive/
 *              primitive-array attribute values every Scanner in this sprint produces
 *              (GraphEngine.md §2's schemaless-bag convention); a future attribute value
 *              that is itself a nested Map/List would canonicalize via its own toString,
 *              which is not guaranteed stable — not a concern for this sprint's 3 Scanners.
 */
public inherited sharing class OI_ChecksumUtil {
    public static String computeChecksum(String componentKind, String fullyQualifiedName, Map<String, Object> rawAttributes) {
        List<String> keys = new List<String>(rawAttributes.keySet());
        keys.sort();
        List<String> parts = new List<String>();
        for (String key : keys) {
            Object value = rawAttributes.get(key);
            parts.add(key + '=' + (value == null ? '' : String.valueOf(value)));
        }
        String canonical = componentKind + '|' + fullyQualifiedName + '|' + String.join(parts, ';');
        return OI_HashUtil.hash(canonical);
    }
}
