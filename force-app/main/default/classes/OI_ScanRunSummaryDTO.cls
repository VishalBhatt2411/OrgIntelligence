/**
 * Purpose: The wire shape OI_ScanController returns for a Scan Run (API.md §2.4) — never
 *          the raw OI_Scan_Run__c sObject crosses the Controller boundary.
 * Responsibilities: Carry exactly what oiScanStatusPanel needs to render status/progress
 *                    and history — nothing more.
 * Dependencies: None.
 * Limitations: Constructed only from an OI_Scan_Run__c row; no independent validation.
 */
public class OI_ScanRunSummaryDTO {
    @AuraEnabled
    public Id scanRunId;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String scanType;
    @AuraEnabled
    public Datetime startedAt;
    @AuraEnabled
    public Datetime completedAt;
    @AuraEnabled
    public Integer nodeCount;
    @AuraEnabled
    public Integer edgeCount;
    @AuraEnabled
    public Integer errorCount;
    @AuraEnabled
    public String metadataTypesIncluded;

    public OI_ScanRunSummaryDTO(OI_Scan_Run__c run) {
        this.scanRunId = run.Id;
        this.status = run.Status__c;
        this.scanType = run.Scan_Type__c;
        this.startedAt = run.Started_At__c;
        this.completedAt = run.Completed_At__c;
        this.nodeCount = run.Node_Count__c == null ? 0 : Integer.valueOf(run.Node_Count__c);
        this.edgeCount = run.Edge_Count__c == null ? 0 : Integer.valueOf(run.Edge_Count__c);
        this.errorCount = run.Error_Count__c == null ? 0 : Integer.valueOf(run.Error_Count__c);
        this.metadataTypesIncluded = run.Metadata_Types_Included__c;
    }
}
