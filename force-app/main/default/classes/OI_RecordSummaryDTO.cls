/**
 * Purpose: The @AuraEnabled wire shape for one record search result (Record Analysis,
 *          ADR-0021) — backs the object-scoped record picker.
 * Responsibilities: Carry exactly recordId/label/objectApiName — never the full record.
 * Dependencies: None.
 * Limitations: None.
 */
public class OI_RecordSummaryDTO {
    @AuraEnabled
    public String recordId;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String objectApiName;

    public OI_RecordSummaryDTO(String recordId, String label, String objectApiName) {
        this.recordId = recordId;
        this.label = label;
        this.objectApiName = objectApiName;
    }
}
