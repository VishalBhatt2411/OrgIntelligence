/**
 * Purpose: One row of an Impact Analysis's flat "affected components" list (Architecture.md
 *          §7) — the default, always-available rendering GraphUI.md §7 mandates ("tables are
 *          secondary but always-available").
 * Responsibilities: Carry exactly what the flat list needs: identity, type, label, how many
 *                    hops from the root this component sits at, and whether it participates
 *                    in a cycle (OI_DependencyEngineService's DFS annotation).
 * Dependencies: None.
 * Limitations: None.
 */
public class OI_AffectedComponent {
    public final String nodeKey;
    public final String typeKey;
    public final String label;
    public final Integer hopDistance;
    public final Boolean isInCycle;

    public OI_AffectedComponent(String nodeKey, String typeKey, String label, Integer hopDistance, Boolean isInCycle) {
        this.nodeKey = nodeKey;
        this.typeKey = typeKey;
        this.label = label;
        this.hopDistance = hopDistance;
        this.isInCycle = isInCycle == null ? false : isInCycle;
    }
}
