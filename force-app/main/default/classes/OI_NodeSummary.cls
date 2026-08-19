/**
 * Purpose: Light-weight node projection used inside an OI_GraphFragment (GraphEngine.md §4).
 * Responsibilities: Carry exactly key/typeKey/label/secondaryKey/state — deliberately never
 *                    the full attributes blob (GraphEngine.md §10's lazy-attribute-load rule).
 * Dependencies: None.
 * Limitations: Not the shape returned by getNodeDetail — that is a full OI_Node.
 */
public class OI_NodeSummary {
    public final String nodeKey;
    public final String typeKey;
    public final String label;
    public final String secondaryKey;
    public final String state;

    public OI_NodeSummary(String nodeKey, String typeKey, String label, String secondaryKey, String state) {
        this.nodeKey = nodeKey;
        this.typeKey = typeKey;
        this.label = label;
        this.secondaryKey = secondaryKey;
        this.state = state;
    }
}
