/**
 * Purpose: The @AuraEnabled wire shape OI_SettingsController.getPresentationRegistry
 *          returns (API.md §2.5) — one fetch, both registries (GraphUI.md §21).
 * Responsibilities: Carry the node-type and edge-type descriptor lists together.
 * Dependencies: OI_NodeTypeDescriptorDTO, OI_EdgeTypeDescriptorDTO.
 * Limitations: None.
 */
public class OI_PresentationRegistryDTO {
    @AuraEnabled
    public List<OI_NodeTypeDescriptorDTO> nodeTypes;
    @AuraEnabled
    public List<OI_EdgeTypeDescriptorDTO> edgeTypes;

    public OI_PresentationRegistryDTO(List<OI_NodeTypeDescriptorDTO> nodeTypes, List<OI_EdgeTypeDescriptorDTO> edgeTypes) {
        this.nodeTypes = nodeTypes;
        this.edgeTypes = edgeTypes;
    }
}
