/**
 * Purpose: The @AuraEnabled boundary for platform configuration reads (API.md §2.5) —
 *          this sprint backs only oiGraphExplorer's Presentation Type Registry fetch
 *          (GraphUI.md §20/§34).
 * Responsibilities: Read-only projection of the Domain Type Registry
 *                    (OI_Node_Type_Descriptor__mdt/OI_Edge_Type_Descriptor__mdt) into
 *                    @AuraEnabled DTOs. Custom Metadata reads directly here (not via a
 *                    Selector) — consistent with this platform's existing pattern for
 *                    Custom Metadata Type reads (OI_ScanOrchestratorQueueable's own
 *                    OI_Metadata_Type_Config__mdt queries), since CodingStandards.md §4's
 *                    Selector-only rule targets Custom Object DML/SOQL discipline, not
 *                    read-only, DML-incapable Custom Metadata.
 * Dependencies: OI_Node_Type_Descriptor__mdt, OI_Edge_Type_Descriptor__mdt,
 *               OI_NodeTypeDescriptorDTO, OI_EdgeTypeDescriptorDTO,
 *               OI_PresentationRegistryDTO.
 * Limitations: getSettings/getLogEntries (API.md §2.5) are not implemented — they back
 *              oiSettingsPanel/oiAdminConsole, both Backlog-tagged P1 and out of Sprint
 *              10's MVP scope. getPresentationRegistry requires no Custom Permission
 *              (GraphUI.md §30) — baseline authenticated access only, deliberately, since
 *              it carries no sensitive data.
 */
public with sharing class OI_SettingsController {
    @AuraEnabled(cacheable=true)
    public static OI_PresentationRegistryDTO getPresentationRegistry() {
        List<OI_NodeTypeDescriptorDTO> nodeTypes = new List<OI_NodeTypeDescriptorDTO>();
        for (OI_Node_Type_Descriptor__mdt descriptor : [SELECT Type_Key__c, Display_Label__c, Icon_Name__c, Color_Token__c, Show_Field_List__c FROM OI_Node_Type_Descriptor__mdt]) {
            nodeTypes.add(new OI_NodeTypeDescriptorDTO(descriptor));
        }
        List<OI_EdgeTypeDescriptorDTO> edgeTypes = new List<OI_EdgeTypeDescriptorDTO>();
        for (OI_Edge_Type_Descriptor__mdt descriptor : [SELECT Type_Key__c, Display_Label__c, Line_Style__c, Is_Field_Membership__c FROM OI_Edge_Type_Descriptor__mdt]) {
            edgeTypes.add(new OI_EdgeTypeDescriptorDTO(descriptor));
        }
        return new OI_PresentationRegistryDTO(nodeTypes, edgeTypes);
    }
}
