/**
 * Purpose: The @AuraEnabled wire shape for one OI_Edge_Type_Descriptor__mdt row (API.md
 *          §2.5, GraphUI.md §21) — the Presentation Type Registry's edge-styling half.
 * Responsibilities: Carry typeKey/displayLabel/lineStyle/isFieldMembership only.
 * Dependencies: OI_Edge_Type_Descriptor__mdt.
 * Limitations: None.
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

    public OI_EdgeTypeDescriptorDTO(OI_Edge_Type_Descriptor__mdt descriptor) {
        this.typeKey = descriptor.Type_Key__c;
        this.displayLabel = descriptor.Display_Label__c;
        this.lineStyle = descriptor.Line_Style__c;
        this.isFieldMembership = descriptor.Is_Field_Membership__c;
    }
}
