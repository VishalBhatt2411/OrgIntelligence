/**
 * Purpose: Light-weight edge projection used inside an OI_GraphFragment (GraphEngine.md §4).
 * Responsibilities: Carry exactly key/typeKey/sourceNodeKey/targetNodeKey.
 * Dependencies: None.
 * Limitations: None.
 */
public class OI_EdgeSummary {
    public final String edgeKey;
    public final String typeKey;
    public final String sourceNodeKey;
    public final String targetNodeKey;

    public OI_EdgeSummary(String edgeKey, String typeKey, String sourceNodeKey, String targetNodeKey) {
        this.edgeKey = edgeKey;
        this.typeKey = typeKey;
        this.sourceNodeKey = sourceNodeKey;
        this.targetNodeKey = targetNodeKey;
    }
}
