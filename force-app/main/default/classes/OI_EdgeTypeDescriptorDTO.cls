/**
 * Purpose: The @AuraEnabled wire shape for one OI_Edge_Type_Descriptor__mdt row (API.md
 *          §2.5, GraphUI.md §21) — the Presentation Type Registry's edge-styling half.
 * Responsibilities: Carry the edge's styling AND its relationship semantics — the role each end
 *                    of the relationship plays, plus a one-line description for the legend.
 * Dependencies: OI_Edge_Type_Descriptor__mdt.
 *
 * Why the role labels belong here rather than in the Canvas: answering "why is this node on my
 * screen?" requires saying what the relationship MEANS from the neighbour's side — a trigger
 * "Executes On" the selected object, a field is a "Field Of" it. That wording differs per
 * relationship type, and hardcoding it in the LWC would put a per-type conditional in exactly
 * the layer that is required not to have one (ADR-0011). Shipping it through the registry means a
 * future relationship type explains itself with no Canvas change.
 */
public class OI_EdgeTypeDescriptorDTO {
    @AuraEnabled
    public String typeKey;
    @AuraEnabled
    public String displayLabel;
    @AuraEnabled
    public String lineStyle;
    @AuraEnabled
    public Boolean isFieldMembership;
    /** What the SOURCE end of this relationship is, e.g. "Executes On" for a trigger. */
    @AuraEnabled
    public String sourceRoleLabel;
    /** What the TARGET end is, e.g. "Field Of" for a field. */
    @AuraEnabled
    public String targetRoleLabel;
    /** One sentence explaining the relationship, shown in the legend so it teaches rather than just lists. */
    @AuraEnabled
    public String description;

    public OI_EdgeTypeDescriptorDTO(OI_Edge_Type_Descriptor__mdt descriptor) {
        this.typeKey = descriptor.Type_Key__c;
        this.displayLabel = descriptor.Display_Label__c;
        this.lineStyle = descriptor.Line_Style__c;
        this.isFieldMembership = descriptor.Is_Field_Membership__c;
        this.sourceRoleLabel = descriptor.Source_Role_Label__c;
        this.targetRoleLabel = descriptor.Target_Role_Label__c;
        this.description = descriptor.Description__c;
    }
}
