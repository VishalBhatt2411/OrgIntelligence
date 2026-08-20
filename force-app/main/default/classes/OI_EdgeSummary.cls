/**
 * Purpose: Light-weight edge projection used inside an OI_GraphFragment (GraphEngine.md §4).
 * Responsibilities: Carry key/typeKey/sourceNodeKey/targetNodeKey, plus the originating field's
 *                    API name for a relationship edge, when the scanner recorded one.
 * Dependencies: None.
 * Limitations: viaFieldApiName is populated only where a scanner actually stored a
 *              `relationshipName` attribute (today: LOOKUP_TO/MASTER_DETAIL_TO from
 *              OI_FieldScanner) — null everywhere else, never guessed.
 */
public class OI_EdgeSummary {
    public final String edgeKey;
    public final String typeKey;
    public final String sourceNodeKey;
    public final String targetNodeKey;
    /** The relationship field this edge travels through (e.g. "AccountId"), or null when the edge kind has no such concept. */
    public final String viaFieldApiName;

    public OI_EdgeSummary(String edgeKey, String typeKey, String sourceNodeKey, String targetNodeKey) {
        this(edgeKey, typeKey, sourceNodeKey, targetNodeKey, null);
    }

    public OI_EdgeSummary(String edgeKey, String typeKey, String sourceNodeKey, String targetNodeKey, String viaFieldApiName) {
        this.edgeKey = edgeKey;
        this.typeKey = typeKey;
        this.sourceNodeKey = sourceNodeKey;
        this.targetNodeKey = targetNodeKey;
        this.viaFieldApiName = viaFieldApiName;
    }
}
