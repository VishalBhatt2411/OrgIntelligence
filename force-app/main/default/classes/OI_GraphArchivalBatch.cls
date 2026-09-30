/**
 * Purpose: Keeps graph data storage bounded (ADR-0002, ADR-0031) by moving superseded
 *          (non-current) node and edge versions older than Graph_Version_Retention_Days__c
 *          from OI_Graph_Node__c / OI_Graph_Edge__c to the Big Object archive.
 * Responsibilities: Run four chained phases — archive nodes, purge nodes, archive edges,
 *                    purge edges. Each archive phase only writes to the archive; the matching
 *                    purge phase deletes the live rows in later, separate transactions,
 *                    because Big Object insertImmediate and sObject DML cannot share one.
 * Dependencies: OI_GraphRepository (all storage access), OI_SettingsService, OI_LoggerService.
 * Inputs: A retention cutoff, fixed for the whole chain so every phase sees the same scope.
 * Outputs: Archive rows written, live rows deleted, one log line per phase.
 * Limitations: If any chunk of an archive phase fails, the chain stops before its purge
 *              phase, so a version is never deleted without being archived first. Rows
 *              archived in a phase that then failed are harmless: the archive is indexed by
 *              version key, so the next run overwrites rather than duplicates them. Deleted
 *              live rows sit in the Recycle Bin, which still counts toward data storage until
 *              it is emptied. Only one chain runs at a time; launch() skips when one is active.
 *              Scope 100 keeps one insertImmediate per row under the 150 DML-statement limit.
 */
public without sharing class OI_GraphArchivalBatch implements Database.Batchable<SObject>, Database.Stateful {
  public enum Phase {
    ARCHIVE_NODES,
    PURGE_NODES,
    ARCHIVE_EDGES,
    PURGE_EDGES
  }

  public static final Integer BATCH_SIZE = 100;
  private static final Integer DEFAULT_RETENTION_DAYS = 1;
  private static final String LOG_SOURCE = 'OI_GraphArchivalBatch';
  private static final Set<String> ACTIVE_JOB_STATUSES = new Set<String>{
    'Holding',
    'Queued',
    'Preparing',
    'Processing'
  };

  /** Test seam: a test runs one phase per Test.stopTest, so it checks the chain via nextPhase instead. */
  @TestVisible
  private static Boolean chainNextPhase = !Test.isRunningTest();

  private final Datetime cutoff;
  private final Phase currentPhase;
  private final OI_GraphRepository repository;
  private Integer processedCount = 0;

  public OI_GraphArchivalBatch() {
    this(resolveCutoff(), Phase.ARCHIVE_NODES, new OI_GraphRepository());
  }

  @TestVisible
  private OI_GraphArchivalBatch(
    Datetime cutoff,
    Phase startPhase,
    OI_GraphRepository repository
  ) {
    this.cutoff = cutoff;
    this.currentPhase = startPhase;
    this.repository = repository;
  }

  /** Starts the chain unless one is already running. Returns the job Id, or null when skipped. */
  public static Id launch() {
    Integer activeJobs = [
      SELECT COUNT()
      FROM AsyncApexJob
      WHERE
        ApexClass.Name = :LOG_SOURCE
        AND JobType = 'BatchApex'
        AND Status IN :ACTIVE_JOB_STATUSES
    ];
    if (activeJobs > 0) {
      return null;
    }
    return Database.executeBatch(new OI_GraphArchivalBatch(), BATCH_SIZE);
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    return repository.locateSupersededVersions(
      cutoff,
      isEdgePhase(currentPhase)
    );
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    String versionKeyField = isEdgePhase(currentPhase)
      ? 'Edge_Version_Key__c'
      : 'Node_Version_Key__c';
    Set<String> versionKeys = new Set<String>();
    for (SObject row : scope) {
      versionKeys.add((String) row.get(versionKeyField));
    }
    // No logging here: a log insert would be sObject DML in the archive phase's
    // insertImmediate transaction. finish() reports the phase instead.
    if (isArchivePhase(currentPhase)) {
      processedCount += repository.archiveSupersededVersions(
        versionKeys,
        isEdgePhase(currentPhase)
      );
    } else {
      processedCount += repository.purgeArchivedVersions(
        versionKeys,
        isEdgePhase(currentPhase)
      );
    }
  }

  public void finish(Database.BatchableContext context) {
    Integer failedChunks = countFailedChunks(context.getJobId());
    OI_LoggerService logger = new OI_LoggerService();
    String summary =
      currentPhase.name() +
      ': ' +
      processedCount +
      ' version rows, cutoff ' +
      cutoff.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    if (failedChunks > 0) {
      logger.warn(
        summary +
          ', ' +
          failedChunks +
          ' failed chunk(s). Archival chain stopped; the next scan retries it.',
        LOG_SOURCE,
        context.getJobId()
      );
      return;
    }
    logger.info(summary + '.', LOG_SOURCE, context.getJobId());
    Phase next = nextPhase(currentPhase);
    if (next != null && chainNextPhase) {
      Database.executeBatch(
        new OI_GraphArchivalBatch(cutoff, next, repository),
        BATCH_SIZE
      );
    }
  }

  /** ARCHIVE_NODES → PURGE_NODES → ARCHIVE_EDGES → PURGE_EDGES → done. */
  @TestVisible
  private static Phase nextPhase(Phase current) {
    List<Phase> order = Phase.values();
    Integer nextIndex = current.ordinal() + 1;
    return nextIndex < order.size() ? order[nextIndex] : null;
  }

  @TestVisible
  private static Datetime resolveCutoff() {
    Integer retentionDays = DEFAULT_RETENTION_DAYS;
    try {
      Decimal configured = new OI_SettingsService()
        .getSettings()
        .Graph_Version_Retention_Days__c;
      if (configured != null && configured >= 0) {
        retentionDays = configured.intValue();
      }
    } catch (OI_ServiceException e) {
      new OI_LoggerService()
        .warn(
          'Settings unavailable; using the default graph version retention. ' +
          e.getMessage(),
          LOG_SOURCE,
          null
        );
    }
    return Datetime.now().addDays(-retentionDays);
  }

  private static Boolean isEdgePhase(Phase value) {
    return value == Phase.ARCHIVE_EDGES || value == Phase.PURGE_EDGES;
  }

  private static Boolean isArchivePhase(Phase value) {
    return value == Phase.ARCHIVE_NODES || value == Phase.ARCHIVE_EDGES;
  }

  private static Integer countFailedChunks(Id jobId) {
    List<AsyncApexJob> jobs = [
      SELECT NumberOfErrors
      FROM AsyncApexJob
      WHERE Id = :jobId
    ];
    return jobs.isEmpty() || jobs[0].NumberOfErrors == null
      ? 0
      : jobs[0].NumberOfErrors;
  }
}
