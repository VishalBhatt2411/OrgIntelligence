/**
 * Purpose: Single shared SHA-256 hex-digest helper used everywhere a deterministic,
 *          stable identity or checksum must be derived from content (MetadataScanner.md
 *          §5 rawChecksum; GraphEngine.md §2/§3 nodeKey/edgeKey/versionKey).
 * Responsibilities: One pure function — string in, hex digest out. No Salesforce-metadata
 *                    or Graph-Engine vocabulary of any kind, so any layer may depend on it
 *                    without a boundary violation (the same neutrality OI_JsonUtil already has).
 * Dependencies: None.
 * Limitations: Callers own canonicalization (key ordering, separators) — this class only hashes.
 */
public inherited sharing class OI_HashUtil {
    public static String hash(String input) {
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(input == null ? '' : input));
        return EncodingUtil.convertToHex(digest);
    }
}
