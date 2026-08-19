/**
 * Purpose: The @AuraEnabled wire shape for one field row in an object's bulk field browser
 *          (oiNodeDetailPanel's "Fields" section) — deliberately lighter than
 *          OI_NodeDetailDTO's full attribute bag, but heavier than the bulk fragment's
 *          OI_NodeSummaryDTO, which carries no attributes at all (GraphEngine.md §10). This
 *          DTO exists because neither of those two shapes fits: a field browser needs
 *          Custom/Standard + data type + reference target for every field of one object in a
 *          single round trip, which would mean either bloating the generic, domain-agnostic
 *          bulk fragment DTO with Salesforce-specific columns (wrong layer, GraphEngine.md
 *          §1) or issuing one getNodeDetail call per field (an N+1 round trip an object with
 *          dozens of fields cannot afford).
 * Responsibilities: Project the handful of OI_FieldScanner-populated attribute keys a field
 *                    browser actually displays out of the schemaless attributes bag, with
 *                    safe, type-checked casts — never a raw pass-through of the bag itself.
 * Dependencies: OI_VersionRecord.
 * Limitations: Constructed only from a field-flavored node's OI_VersionRecord (a
 *              SalesforceMetadata.CustomField node); the caller is responsible for that
 *              distinction, exactly as OI_NodeDetailDTO's own header already documents for
 *              its own construction contract.
 */
public class OI_FieldSummaryDTO {
    @AuraEnabled
    public String nodeKey;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String apiName;
    @AuraEnabled
    public String dataType;
    @AuraEnabled
    public Boolean isCustom;
    @AuraEnabled
    public Boolean isRequired;
    @AuraEnabled
    public List<String> referenceTo;

    public OI_FieldSummaryDTO(OI_VersionRecord version) {
        this.nodeKey = version.key;
        this.label = version.label;
        this.apiName = version.secondaryKey;
        Map<String, Object> attributes = version.attributes;
        this.dataType = attributes.get('type') == null ? null : String.valueOf(attributes.get('type'));
        this.isCustom = attributes.get('custom') instanceof Boolean ? (Boolean) attributes.get('custom') : null;
        Object nillable = attributes.get('nillable');
        this.isRequired = nillable instanceof Boolean ? !((Boolean) nillable) : null;
        this.referenceTo = toStringList(attributes.get('referenceTo'));
    }

    /** JSON.deserializeUntyped hands back a raw List<Object> for a JSON array — never assumed to already be List<String>. */
    private static List<String> toStringList(Object rawValue) {
        if (!(rawValue instanceof List<Object>)) {
            return null;
        }
        List<String> result = new List<String>();
        for (Object item : (List<Object>) rawValue) {
            if (item != null) {
                result.add(String.valueOf(item));
            }
        }
        return result;
    }
}
