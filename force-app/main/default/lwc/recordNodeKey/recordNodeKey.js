/**
 * Purpose: Client-side recognition of a Record Analysis node key (ADR-0021) — the single
 *          place every LWC that needs to tell a live record node apart from a scanned
 *          metadata node does so, rather than each duplicating the same string parsing.
 * Responsibilities: Parse 'Record::<objectApiName>::<recordId>' (the exact format
 *                    OI_RecordSchemaUtil.recordNodeKey produces server-side) back into its
 *                    parts, or return null for any other nodeKey shape.
 * Dependencies: None.
 */
const RECORD_NODE_KEY_PREFIX = 'Record::';

export function parseRecordNodeKey(nodeKey) {
    if (!nodeKey || !nodeKey.startsWith(RECORD_NODE_KEY_PREFIX)) {
        return null;
    }
    const rest = nodeKey.substring(RECORD_NODE_KEY_PREFIX.length);
    const separatorIndex = rest.indexOf('::');
    if (separatorIndex === -1) {
        return null;
    }
    return { objectApiName: rest.substring(0, separatorIndex), recordId: rest.substring(separatorIndex + 2) };
}
