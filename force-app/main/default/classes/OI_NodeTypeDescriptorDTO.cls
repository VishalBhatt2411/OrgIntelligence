/**
 * Purpose: The @AuraEnabled wire shape for one OI_Node_Type_Descriptor__mdt row (API.md
 *          §2.5, GraphUI.md §20) — the Presentation Type Registry's node-styling half.
 * Responsibilities: Carry typeKey/displayLabel/iconName/colorToken/showFieldList only.
 * Dependencies: OI_Node_Type_Descriptor__mdt.
 * Limitations: None.
 */
public class OI_NodeTypeDescriptorDTO {
    @AuraEnabled
    public String typeKey;
    @AuraEnabled
    public String displayLabel;
    @AuraEnabled
    public String iconName;
    @AuraEnabled
    public String colorToken;
    @AuraEnabled
    public Boolean showFieldList;

    public OI_NodeTypeDescriptorDTO(OI_Node_Type_Descriptor__mdt descriptor) {
        this.typeKey = descriptor.Type_Key__c;
        this.displayLabel = descriptor.Display_Label__c;
        this.iconName = descriptor.Icon_Name__c;
        this.colorToken = descriptor.Color_Token__c;
        this.showFieldList = descriptor.Show_Field_List__c;
    }
}
