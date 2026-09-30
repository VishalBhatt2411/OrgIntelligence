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
 * Dependencies: OI_VersionRecord, Schema.DescribeFieldResult.
 * Limitations: Constructed from either a field-flavored node's OI_VersionRecord (a
 *              SalesforceMetadata.CustomField node) or, since ADR-0031 stopped persisting
 *              plain data fields, a live DescribeFieldResult. nodeKey is null for a field
 *              with no graph node; isInGraph says so explicitly and rowKey is always set, so
 *              the UI never keys a list on a null value.
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
  /** Stable, never-null list key: the fully-qualified API name when known, else the node key. */
  @AuraEnabled
  public String rowKey;
  /** True when this field has a graph node (it can be selected on the canvas). */
  @AuraEnabled
  public Boolean isInGraph;

  public OI_FieldSummaryDTO(OI_VersionRecord version) {
    this.nodeKey = version.key;
    this.isInGraph = version.key != null;
    this.rowKey = version.secondaryKey != null
      ? version.secondaryKey
      : version.key;
    this.label = version.label;
    this.apiName = version.secondaryKey;
    Map<String, Object> attributes = version.attributes;
    this.dataType = attributes.get('type') == null
      ? null
      : String.valueOf(attributes.get('type'));
    this.isCustom = attributes.get('custom') instanceof Boolean
      ? (Boolean) attributes.get('custom')
      : null;
    Object nillable = attributes.get('nillable');
    this.isRequired = nillable instanceof Boolean
      ? !((Boolean) nillable)
      : null;
    this.referenceTo = toStringList(attributes.get('referenceTo'));
  }

  /** Live-Describe row; nodeKey is the persisted field node's key, or null when the field is not in the graph. */
  public OI_FieldSummaryDTO(
    Schema.DescribeFieldResult fieldDescribe,
    String qualifiedApiName,
    String nodeKey
  ) {
    this.nodeKey = nodeKey;
    this.isInGraph = nodeKey != null;
    this.rowKey = qualifiedApiName;
    this.label = fieldDescribe.getLabel();
    this.apiName = qualifiedApiName;
    this.dataType = String.valueOf(fieldDescribe.getType());
    this.isCustom = fieldDescribe.isCustom();
    this.isRequired = !fieldDescribe.isNillable();
    List<Schema.SObjectType> targets = fieldDescribe.getReferenceTo();
    if (!targets.isEmpty()) {
      this.referenceTo = new List<String>();
      for (Schema.SObjectType target : targets) {
        this.referenceTo.add(target.getDescribe().getName());
      }
    }
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
