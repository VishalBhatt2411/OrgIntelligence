/**
 * Purpose: Security-trimmed, live overview facts for the center record in Record Analyze mode.
 * Responsibilities: Carry only values that the running user can access and that were selected
 *                   by OI_RecordHierarchyService in USER_MODE.
 * Dependencies: None.
 * Limitations: Null means unavailable or inaccessible; callers must omit it rather than infer a
 *              value. Record data is never persisted in the metadata graph.
 */
public class OI_RecordOverviewDTO {
  @AuraEnabled
  public String ownerName;
  @AuraEnabled
  public Datetime createdDate;
  @AuraEnabled
  public Datetime lastModifiedDate;

  public OI_RecordOverviewDTO(
    String ownerName,
    Datetime createdDate,
    Datetime lastModifiedDate
  ) {
    this.ownerName = ownerName;
    this.createdDate = createdDate;
    this.lastModifiedDate = lastModifiedDate;
  }
}
