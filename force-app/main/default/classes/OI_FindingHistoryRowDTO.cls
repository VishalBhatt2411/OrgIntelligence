/**
 * Purpose: One raw OI_Org_Health_Finding__History row, decoupled from that platform-generated
 *          SObject type itself.
 * Responsibilities: Carry a history row's field/old value/new value/timestamp/author from
 *                    OI_OrgHealthFindingHistorySelector to OI_OrgHealthFindingService.
 * Dependencies: None.
 * Limitations: oldValue/newValue are typed Object because Field History Tracking stores them
 *              untyped (the tracked field's own type varies per row); callers must
 *              String.valueOf() before display, exactly as the raw SObject's fields required.
 *              Deliberately a plain Apex class rather than the OI_Org_Health_Finding__History
 *              SObject itself — that type's Field/OldValue/NewValue/CreatedDate fields are not
 *              constructible via a standard SObject constructor or JSON.deserialize (both were
 *              tried and rejected: "Field is not writeable" at compile time, then a
 *              System.UnexpectedException Salesforce System Error at runtime), which made it
 *              impossible to build fake rows for a DI-based test fake. This DTO is what
 *              OI_OrgHealthFindingHistorySelector.selectByFindingId actually returns instead.
 */
public class OI_FindingHistoryRowDTO {
  public String fieldApiName;
  public Object oldValue;
  public Object newValue;
  public Datetime changedDate;
  public String changedByName;

  public OI_FindingHistoryRowDTO(
    String fieldApiName,
    Object oldValue,
    Object newValue,
    Datetime changedDate,
    String changedByName
  ) {
    this.fieldApiName = fieldApiName;
    this.oldValue = oldValue;
    this.newValue = newValue;
    this.changedDate = changedDate;
    this.changedByName = changedByName;
  }
}
