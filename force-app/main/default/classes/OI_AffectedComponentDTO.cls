/**
 * Purpose: The @AuraEnabled wire shape for OI_AffectedComponent (Architecture.md §7) —
 *          Controllers never return the plain domain class directly across the LWC boundary.
 * Responsibilities: Mirror every field of OI_AffectedComponent.
 * Dependencies: OI_AffectedComponent.
 * Limitations: None.
 */
public class OI_AffectedComponentDTO {
    @AuraEnabled
    public String nodeKey;
    @AuraEnabled
    public String typeKey;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Integer hopDistance;
    @AuraEnabled
    public Boolean isInCycle;

    public OI_AffectedComponentDTO(OI_AffectedComponent component) {
        this.nodeKey = component.nodeKey;
        this.typeKey = component.typeKey;
        this.label = component.label;
        this.hopDistance = component.hopDistance;
        this.isInCycle = component.isInCycle;
    }
}
