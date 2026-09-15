/**
 * Purpose: Org Health's Data Health Tier-3 (async, persisted) computation (ADR-0026 Phase 5)
 *          — the only place this feature ever queries real record data, and always bounded:
 *          one object per execute() chunk, each capped at its own
 *          OI_Data_Health_Object_Scope__mdt.Max_Records_To_Sample__c. Never invoked from a
 *          page load — only OI_OrgHealthController.recomputeDataHealth() enqueues it, gated by
 *          OI_Run_Org_Health_Compute (ADR-0026 §0.8/§0.9).
 * Responsibilities: start() reads the small, admin-configured, enabled object scope list;
 *                    execute() samples up to the configured ceiling per object (bounded
 *                    dynamic SOQL, built only from Schema-describe-confirmed object/field
 *                    names — never raw interpolation of unchecked input) and computes three
 *                    real per-record facts (stale, incomplete, duplicate); finish() hands the
 *                    collected OI_DataHealthService.ObjectSignal list to OI_DataHealthService
 *                    for scoring/shaping, persists the result via OI_OrgHealthSnapshotRepository,
 *                    then projects the same signals into the unified finding model (ADR-0027)
 *                    and syncs them via OI_OrgHealthFindingService — Data Health has no separate
 *                    live "sync findings" action, so computing and persisting findings both
 *                    happen here, once per bounded async run. All formula/scoring logic lives in
 *                    OI_DataHealthService, not here — this class only collects.
 * Dependencies: OI_Data_Health_Object_Scope__mdt, OI_DataHealthService,
 *               OI_OrgHealthSnapshotRepository, OI_OrgHealthFindingService.
 * Limitations: An object named in scope but missing/inaccessible in this org (a package
 *              feature not enabled, a renamed custom object), or one that throws while being
 *              sampled, is skipped and named in the resulting coverageNote rather than failing
 *              the whole run — "design for missing metadata gracefully" (CLAUDE.md). The caller
 *              (OI_OrgHealthController.recomputeDataHealth()) passes a batch size comfortably
 *              above the admin-configured scope list's expected size, so the whole run
 *              typically completes in one execute() chunk.
 */
public class OI_DataHealthComputeBatchable implements Database.Batchable<OI_Data_Health_Object_Scope__mdt>, Database.Stateful {
  @TestVisible
  private static final Integer DEFAULT_SAMPLE_CEILING = 200;
  @TestVisible
  private static final Integer STALE_DAYS_THRESHOLD = 180;

  private final String computeRunId;
  private final Id triggeredById;
  @TestVisible
  private final List<OI_DataHealthService.ObjectSignal> signals = new List<OI_DataHealthService.ObjectSignal>();
  @TestVisible
  private final List<String> skippedObjects = new List<String>();
  private Boolean anyObjectTruncated = false;

  public OI_DataHealthComputeBatchable() {
    this(UserInfo.getUserId());
  }

  public OI_DataHealthComputeBatchable(Id triggeredById) {
    this.triggeredById = triggeredById;
    this.computeRunId = generateComputeRunId();
  }

  public Iterable<OI_Data_Health_Object_Scope__mdt> start(
    Database.BatchableContext context
  ) {
    return [
      SELECT Object_Api_Name__c, Max_Records_To_Sample__c
      FROM OI_Data_Health_Object_Scope__mdt
      WHERE Enabled__c = TRUE
    ];
  }

  public void execute(
    Database.BatchableContext context,
    List<OI_Data_Health_Object_Scope__mdt> scope
  ) {
    for (OI_Data_Health_Object_Scope__mdt scopeRow : scope) {
      try {
        processObject(
          scopeRow.Object_Api_Name__c,
          scopeRow.Max_Records_To_Sample__c
        );
      } catch (Exception e) {
        skippedObjects.add(
          scopeRow.Object_Api_Name__c + ' (error: ' + e.getMessage() + ')'
        );
      }
    }
  }

  public void finish(Database.BatchableContext context) {
    OI_DataHealthService service = new OI_DataHealthService();
    OI_DataHealthDTO dto = service.buildSnapshotFromSignals(
      signals,
      skippedObjects,
      anyObjectTruncated
    );
    Integer rowCountExamined = 0;
    for (OI_DataHealthService.ObjectSignal signal : signals) {
      rowCountExamined += signal.sampledCount;
    }
    service.persistSnapshot(
      dto,
      computeRunId,
      rowCountExamined,
      anyObjectTruncated,
      triggeredById
    );

    List<OI_OrgHealthFindingCandidate> candidates = service.getFindingCandidates(
      signals
    );
    new OI_OrgHealthFindingService()
      .sync('DataHealth', candidates, computeRunId);
  }

  @TestVisible
  private void processObject(String objectApiName, Decimal maxRecordsToSample) {
    if (String.isBlank(objectApiName)) {
      return;
    }
    Integer ceiling = maxRecordsToSample == null ||
      maxRecordsToSample <= 0
      ? DEFAULT_SAMPLE_CEILING
      : maxRecordsToSample.intValue();

    Schema.SObjectType sObjectType = Schema.getGlobalDescribe()
      .get(objectApiName);
    if (sObjectType == null) {
      skippedObjects.add(objectApiName + ' (not found in this org)');
      return;
    }
    Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
    if (!describeResult.isAccessible() || !describeResult.isQueryable()) {
      skippedObjects.add(objectApiName + ' (not accessible)');
      return;
    }

    Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
    List<String> requiredFieldNames = new List<String>();
    for (Schema.SObjectField field : fieldMap.values()) {
      Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
      if (
        !fieldDescribe.isNillable() &&
        fieldDescribe.isCreateable() &&
        fieldDescribe.isUpdateable() &&
        fieldDescribe.getType() != Schema.DisplayType.ID
      ) {
        requiredFieldNames.add(fieldDescribe.getName());
      }
    }
    String duplicateFieldName = fieldMap.containsKey('email')
      ? 'Email'
      : (fieldMap.containsKey('phone') ? 'Phone' : null);

    Set<String> selectFields = new Set<String>{ 'Id', 'LastModifiedDate' };
    selectFields.addAll(requiredFieldNames);
    if (duplicateFieldName != null) {
      selectFields.add(duplicateFieldName);
    }

    Integer totalRecordCount = Database.countQuery(
      'SELECT COUNT() FROM ' + objectApiName
    );
    String query =
      'SELECT ' +
      String.join(new List<String>(selectFields), ', ') +
      ' FROM ' +
      objectApiName +
      ' ORDER BY LastModifiedDate DESC LIMIT ' +
      ceiling;
    List<SObject> records = Database.query(query);

    Datetime staleThresholdDate = Datetime.now().addDays(-STALE_DAYS_THRESHOLD);
    Integer staleCount = 0;
    Integer incompleteCount = 0;
    Map<String, Integer> duplicateGroupCounts = new Map<String, Integer>();

    for (SObject record : records) {
      Datetime lastModified = (Datetime) record.get('LastModifiedDate');
      if (lastModified != null && lastModified < staleThresholdDate) {
        staleCount++;
      }
      Boolean isIncomplete = false;
      for (String requiredField : requiredFieldNames) {
        if (record.get(requiredField) == null) {
          isIncomplete = true;
          break;
        }
      }
      if (isIncomplete) {
        incompleteCount++;
      }
      if (duplicateFieldName != null) {
        Object rawValue = record.get(duplicateFieldName);
        if (rawValue != null) {
          String normalized = String.valueOf(rawValue).trim().toLowerCase();
          if (String.isNotBlank(normalized)) {
            Integer count = duplicateGroupCounts.containsKey(normalized)
              ? duplicateGroupCounts.get(normalized)
              : 0;
            duplicateGroupCounts.put(normalized, count + 1);
          }
        }
      }
    }

    Integer duplicateCount = 0;
    for (Integer groupSize : duplicateGroupCounts.values()) {
      if (groupSize > 1) {
        duplicateCount += groupSize;
      }
    }

    Boolean isTruncated =
      records.size() >= ceiling &&
      totalRecordCount > records.size();
    if (isTruncated) {
      anyObjectTruncated = true;
    }
    signals.add(
      new OI_DataHealthService.ObjectSignal(
        objectApiName,
        totalRecordCount,
        records.size(),
        staleCount,
        incompleteCount,
        duplicateCount,
        isTruncated
      )
    );
  }

  private String generateComputeRunId() {
    String hex = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
    return hex.substring(0, 8) +
      '-' +
      hex.substring(8, 12) +
      '-' +
      hex.substring(12, 16) +
      '-' +
      hex.substring(16, 20) +
      '-' +
      hex.substring(20, 32);
  }
}
