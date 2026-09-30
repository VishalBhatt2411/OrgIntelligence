/**
 * Purpose: The Tech Debt scanner — inventories the org, runs every analyzer and stores the
 *          findings, health score and component inventory for one OI_TD_Scan__c.
 * Responsibilities: A resumable stage machine (TARGETS → … → COMPLETE). Each batch execute
 *                    (OI_TD_ScanBatch) calls runExecute, which runs small "units" of work while
 *                    CPU / heap / callout / SOQL / row / wall-clock budgets allow, then flushes
 *                    all DML once at the end (callouts can never follow DML in a transaction).
 *                    A failing section keeps its partial data, is recorded with count 0 and an
 *                    error, and the scan moves on — mirroring the reference scanner's
 *                    per-section try/catch.
 * Dependencies: OI_TD_ToolingClient, OI_MetadataApiAdapter (both via `OI_Self_Callout`),
 *               OI_TD_Rules, OI_TD_UsageMatcher, OI_TD_DataStore, OI_TD_ScanState.
 * Limitations: Usage fallback (components with no dependency data) is a substring search over
 *              scanned Apex / trigger / flow / LWC text, like the reference; it cannot see
 *              dynamically built references. Dependency data is the first result page per
 *              100-id query, as in the reference.
 */
public with sharing class OI_TD_ScanEngine {
  public static final Integer S_TARGETS = 0;
  public static final Integer S_OBJ_IDS = 1;
  public static final Integer S_FIELD_IDS = 2;
  public static final Integer S_DESCRIBE = 3;
  public static final Integer S_CLASSES = 4;
  public static final Integer S_TRIGGERS = 5;
  public static final Integer S_FLOWS = 6;
  public static final Integer S_WF = 7;
  public static final Integer S_LWC = 8;
  public static final Integer S_EMAIL = 9;
  public static final Integer S_VFP = 10;
  public static final Integer S_VFC = 11;
  public static final Integer S_PACKAGES = 12;
  public static final Integer S_PERMISSIONS = 13;
  public static final Integer S_DEPS = 14;
  public static final Integer S_OWD = 15;
  public static final Integer S_SHARING_RULES = 16;
  public static final Integer S_ROLES = 17;
  public static final Integer S_USAGE = 18;
  public static final Integer S_FINALIZE = 19;
  public static final Integer S_ANALYZE = 20;
  public static final Integer S_COMPLETE = 21;
  public static final Integer S_DONE = 22;

  public static final String STATUS_RUNNING = 'running';
  public static final String STATUS_COMPLETED = 'completed';
  public static final String STATUS_FAILED = 'failed';

  private static final List<String> SECTION_BY_STAGE = new List<String>{
    'objects',
    'objects',
    'objects',
    'objects',
    'apex_classes',
    'triggers',
    'flows',
    'workflow_rules',
    'lwc',
    'email_templates',
    'visualforce_pages',
    'visualforce_components',
    'installed_packages',
    'permissions',
    'dependencies',
    'sharing_model',
    'sharing_rules',
    'role_hierarchy'
  };

  private static final Pattern NOISE_OBJECT_SUFFIX_RE = Pattern.compile(
    '(History|Feed|Share|ChangeEvent)$'
  );
  private static final Pattern SF_ID_RE = Pattern.compile(
    '^[a-zA-Z0-9]{15,18}$'
  );
  private static final Integer METADATA_READ_BATCH_SIZE = 10;
  private static final Integer FLOW_READ_BATCH_SIZE = 3;
  private static final Integer DEPENDENCY_QUERY_BATCH_SIZE = 100;
  private static final Integer OWD_QUERY_BATCH_SIZE = 100;
  private static final Integer BODY_CHUNK_CHARS = 400000;
  private static final Integer BODY_CHUNK_MAX = 50;
  private static final Integer USAGE_BODY_CHUNK = 25;
  private static final Integer LWC_SOURCE_CHUNK = 40;
  private static final Integer HOLDER_FIELD_CHUNK = 5;
  private static final Integer SHARD_CHARS = 100000;
  private static final Integer HAY_CHARS = 100000;
  private static final Long WALL_BUDGET_MS = 55000;
  private static final List<String> RISKY_PERMS = new List<String>{
    'AuthorApex',
    'ManageUsers',
    'ModifyAllData',
    'ViewAllData'
  };

  // Finding order groups (analyzer * 10 + group).
  private static final Integer G_CQ_CLASS = 0;
  private static final Integer G_CQ_TRIGGER = 1;
  private static final Integer G_CQ_NAMING = 2;
  private static final Integer G_GOV_BODY = 60;
  private static final Integer G_GOV_ORG = 61;
  private static final Integer G_DQ_UNUSED_FIELD = 50;
  private static final Integer G_DQ_DUPLICATE = 51;
  private static final Integer G_DQ_UNUSED_OBJECT = 52;
  private static final Integer G_DQ_UNUSED_CLASS = 53;
  private static final Integer G_DQ_UNUSED_LWC = 54;

  @TestVisible
  private static OI_TD_ToolingClient toolingOverride;
  @TestVisible
  private static OI_MetadataApiAdapter metadataOverride;
  @TestVisible
  private static Integer maxListRows = 50000;

  private OI_TD_ScanState st;
  private OI_TD_ToolingClient tooling;
  private OI_MetadataApiAdapter metadata;
  private OI_TD_UsageMatcher matcher;
  private Long startedMs;

  private OI_TD_ScanEngine(OI_TD_ScanState st) {
    this.st = st;
    this.tooling = toolingOverride != null
      ? toolingOverride
      : new OI_TD_ToolingClient();
    this.metadata = metadataOverride != null
      ? metadataOverride
      : new OI_MetadataApiAdapter();
  }

  /** Runs one execute's worth of units and flushes. Returns true once the scan is finished. */
  public static Boolean runExecute(OI_TD_ScanState st) {
    new OI_TD_ScanEngine(st).run();
    return st.stage >= S_DONE;
  }

  private void run() {
    startedMs = System.currentTimeMillis();
    st.flushRequested = false;
    Boolean first = true;
    while (
      st.stage < S_DONE &&
      !st.flushRequested &&
      (first || withinBudget())
    ) {
      first = false;
      runUnit();
    }
    flush();
  }

  private Boolean withinBudget() {
    return Limits.getCpuTime() < Limits.getLimitCpuTime() * 0.4 &&
      Limits.getHeapSize() < Limits.getLimitHeapSize() * 0.55 &&
      Limits.getCallouts() < Limits.getLimitCallouts() - 12 &&
      Limits.getQueries() < Limits.getLimitQueries() * 0.7 &&
      Limits.getQueryRows() < Limits.getLimitQueryRows() * 0.5 &&
      Limits.getDmlRows() < Limits.getLimitDmlRows() * 0.5 &&
      System.currentTimeMillis() - startedMs < WALL_BUDGET_MS;
  }

  private void runUnit() {
    Integer stage = st.stage;
    try {
      if (step(stage)) {
        advance();
      }
    } catch (Exception e) {
      if (stage <= S_ROLES) {
        failSection(message(e));
      } else {
        markFailed('Scan failed while analyzing results: ' + message(e));
      }
    }
  }

  private Boolean step(Integer stage) {
    if (stage == S_TARGETS)
      return stepTargets();
    if (stage == S_OBJ_IDS)
      return stepObjectIds();
    if (stage == S_FIELD_IDS)
      return stepFieldIds();
    if (stage == S_DESCRIBE)
      return stepDescribe();
    if (stage == S_CLASSES)
      return stepClasses();
    if (stage == S_TRIGGERS)
      return stepTriggers();
    if (stage == S_FLOWS)
      return stepFlows();
    if (stage == S_WF)
      return stepWorkflowRules();
    if (stage == S_LWC)
      return stepLwc();
    if (stage == S_EMAIL)
      return stepEmail();
    if (stage == S_VFP)
      return stepVfPages();
    if (stage == S_VFC)
      return stepVfComponents();
    if (stage == S_PACKAGES)
      return stepPackages();
    if (stage == S_PERMISSIONS)
      return stepPermissions();
    if (stage == S_DEPS)
      return stepDependencies();
    if (stage == S_OWD)
      return stepOwd();
    if (stage == S_SHARING_RULES)
      return stepSharingRules();
    if (stage == S_ROLES)
      return stepRoles();
    if (stage == S_USAGE)
      return stepUsage();
    if (stage == S_FINALIZE)
      return stepFinalize();
    if (stage == S_ANALYZE)
      return stepAnalyze();
    if (stage == S_COMPLETE)
      return stepComplete();
    return true;
  }

  // =====================================================================
  // Stage bookkeeping
  // =====================================================================

  private static String sectionOf(Integer stage) {
    return stage >= 0 &&
      stage < SECTION_BY_STAGE.size()
      ? SECTION_BY_STAGE[stage]
      : null;
  }

  private void advance() {
    closeBuffers(st.stage);
    String sec = sectionOf(st.stage);
    if (sec != null && sec != sectionOf(st.stage + 1)) {
      st.sections.add(
        new OI_TD_ScanState.SectionResult(sec, st.sectionCount, null)
      );
      st.sectionCount = 0;
    }
    moveTo(st.stage + 1);
  }

  private void moveTo(Integer stage) {
    st.stage = stage;
    st.phase = 0;
    st.cursor = 0;
    st.nextUrl = null;
    st.work = new List<String>();
    st.work2 = new List<String>();
    st.workLens = new List<Integer>();
    if (stage >= S_USAGE) {
      // Later stages read what earlier ones wrote — end the execute so it is committed first.
      st.flushRequested = true;
    }
  }

  private void failSection(String error) {
    skipSection(st, error);
    st.flushRequested = st.flushRequested || st.stage >= S_USAGE;
  }

  /** Records the current section as failed (count 0) and moves to the next one; keeps partial data. */
  public static void skipSection(OI_TD_ScanState state, String error) {
    OI_TD_ScanEngine engine = new OI_TD_ScanEngine(state);
    if (state.stage > S_ROLES) {
      engine.markFailed(error);
      return;
    }
    engine.closeBuffers(state.stage);
    String sec = sectionOf(state.stage);
    state.sections.add(new OI_TD_ScanState.SectionResult(sec, 0, error));
    state.sectionCount = 0;
    Integer next = state.stage + 1;
    while (next <= S_ROLES && sectionOf(next) == sec) {
      next++;
    }
    engine.moveTo(next);
  }

  private void markFailed(String error) {
    st.failed = true;
    st.error = error;
    st.stage = S_DONE;
  }

  private void flush() {
    if (!st.pendingData.isEmpty()) {
      insert st.pendingData;
      st.pendingData = new List<OI_TD_Scan_Data__c>();
    }
    if (!st.pendingFindings.isEmpty()) {
      insert st.pendingFindings;
      st.pendingFindings = new List<OI_TD_Finding__c>();
    }
    if (st.failed) {
      markScanFailed(st.scanId, st.error, st.sections);
    } else if (st.stage < S_DONE) {
      update new OI_TD_Scan__c(
        Id = st.scanId,
        Current_Stage__c = stageLabel(st.stage),
        Section_Results__c = JSON.serialize(st.sections)
      );
    }
  }

  /** Marks a scan failed and removes its temporary haystack data. Never leaves a scan "running". */
  public static void markScanFailed(
    Id scanId,
    String error,
    List<OI_TD_ScanState.SectionResult> sections
  ) {
    OI_TD_Scan__c scan = new OI_TD_Scan__c(
      Id = scanId,
      Status__c = STATUS_FAILED,
      Finished_At__c = System.now(),
      Error__c = String.isBlank(error) ? 'The scan failed.' : error.left(32000)
    );
    if (sections != null) {
      scan.Section_Results__c = JSON.serialize(sections);
    }
    update scan;
    delete [
      SELECT Id
      FROM OI_TD_Scan_Data__c
      WHERE Scan__c = :scanId AND Kind__c LIKE 'hay:%'
      LIMIT 5000
    ];
  }

  public static String stageLabel(Integer s) {
    if (s <= S_FIELD_IDS)
      return 'Connecting to Salesforce…';
    if (s == S_DESCRIBE)
      return 'Reading objects & fields…';
    if (s == S_CLASSES)
      return 'Scanning Apex classes…';
    if (s == S_TRIGGERS)
      return 'Scanning triggers…';
    if (s == S_FLOWS || s == S_WF)
      return 'Scanning flows…';
    if (s == S_LWC)
      return 'Scanning Lightning components…';
    if (s <= S_PERMISSIONS)
      return 'Checking profiles & permission sets…';
    return 'Analyzing technical debt…';
  }

  private void closeBuffers(Integer stage) {
    if (stage == S_DESCRIBE) {
      writeShard();
    } else if (stage == S_FLOWS) {
      writeHay('hay:flows');
    } else if (stage == S_LWC) {
      writeHay('hay:lwc');
    }
  }

  // =====================================================================
  // Objects & fields
  // =====================================================================

  private Boolean stepTargets() {
    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
      tooling.get(OI_TD_ToolingClient.describeGlobalPath())
    );
    for (Object raw : asList(parsed.get('sobjects'))) {
      Map<String, Object> o = (Map<String, Object>) raw;
      String name = str(o.get('name'));
      if (name == null || NOISE_OBJECT_SUFFIX_RE.matcher(name).find()) {
        continue;
      }
      if (isTrue(o.get('layoutable')) || isTrue(o.get('custom'))) {
        st.targets.add(name);
      }
    }
    return true;
  }

  // Best-effort, like the reference: restricted Tooling access must not block the scan.
  private Boolean stepObjectIds() {
    try {
      for (
        Map<String, Object> r : nextToolingPage(
          'SELECT Id, DeveloperName FROM CustomObject'
        )
      ) {
        String id = str(r.get('Id'));
        String name = str(r.get('DeveloperName')) + '__c';
        st.objIdByName.put(name, id);
        if (id != null) {
          st.objNameById.put(id.left(15), name);
        }
      }
    } catch (Exception e) {
      st.nextUrl = null;
    }
    return st.nextUrl == null;
  }

  private Boolean stepFieldIds() {
    try {
      for (
        Map<String, Object> r : nextToolingPage(
          'SELECT Id, DeveloperName, TableEnumOrId FROM CustomField'
        )
      ) {
        String table = resolveTable(str(r.get('TableEnumOrId')));
        st.fieldIdByKey.put(
          table + '.' + str(r.get('DeveloperName')) + '__c',
          str(r.get('Id'))
        );
      }
    } catch (Exception e) {
      st.nextUrl = null;
    }
    return st.nextUrl == null;
  }

  /** TableEnumOrId is an object name for standard objects and a CustomObject Id for custom ones. */
  private String resolveTable(String tableEnumOrId) {
    if (tableEnumOrId == null) {
      return null;
    }
    String name = tableEnumOrId.length() >= 15
      ? st.objNameById.get(tableEnumOrId.left(15))
      : null;
    return name != null ? name : tableEnumOrId;
  }

  private Boolean stepDescribe() {
    if (st.cursor >= st.targets.size()) {
      return true;
    }
    String target = st.targets[st.cursor];
    st.cursor++;
    Schema.DescribeSObjectResult d;
    try {
      d = Schema.describeSObjects(new List<String>{ target })[0];
    } catch (Exception e) {
      // Some objects are undescribable for this user — skip just that one.
      return st.cursor >= st.targets.size();
    }
    String objectName = d.getName();
    List<Map<String, Object>> fieldRows = new List<Map<String, Object>>();
    List<String> outgoing = null;
    Set<String> outgoingSet = new Set<String>();
    for (Schema.SObjectField f : d.fields.getMap().values()) {
      Schema.DescribeFieldResult fd = f.getDescribe();
      if (!fd.isAccessible()) {
        continue;
      }
      String fieldName = fd.getName();
      Map<String, Object> row = new Map<String, Object>{
        'a' => fieldName,
        't' => typeName(fd.getType())
      };
      String fieldId = st.fieldIdByKey.get(objectName + '.' + fieldName);
      if (fieldId != null) {
        row.put('i', fieldId);
        st.fieldIds.add(fieldId);
      } else {
        st.noIdFieldNames.add(fieldName);
      }
      st.allFieldNames.add(fieldName);
      fieldRows.add(row);
      for (Schema.SObjectType refType : fd.getReferenceTo()) {
        String refName = String.valueOf(refType);
        if (outgoingSet.add(refName)) {
          if (outgoing == null) {
            outgoing = new List<String>();
          }
          outgoing.add(refName);
        }
      }
    }
    if (outgoing != null) {
      st.outgoingOrder.add(objectName);
      st.outgoingByObject.put(objectName, outgoing);
    }

    String payload = JSON.serialize(fieldRows);
    if (st.shardChars > 0 && st.shardChars + payload.length() > SHARD_CHARS) {
      writeShard();
    }
    st.shard.put(objectName, fieldRows);
    st.shardChars += payload.length() + objectName.length() + 4;

    OI_TD_ScanState.ObjRec o = new OI_TD_ScanState.ObjRec();
    o.a = objectName;
    o.l = d.getLabel();
    o.c = fieldRows.size();
    o.i = st.objIdByName.get(objectName);
    o.s = st.shardSeq;
    st.objects.add(o);
    st.fieldTotal += fieldRows.size();
    st.sectionCount++;
    return st.cursor >= st.targets.size();
  }

  private void writeShard() {
    if (st.shard.isEmpty()) {
      return;
    }
    st.pendingData.addAll(
      OI_TD_DataStore.chunks(
        st.scanId,
        'fields:' + st.shardSeq,
        JSON.serialize(st.shard)
      )
    );
    st.shardSeq++;
    st.shard = new Map<String, List<Map<String, Object>>>();
    st.shardChars = 0;
  }

  /** REST describe's type names: lower-case DisplayType, except int and anyType. */
  @TestVisible
  private static String typeName(Schema.DisplayType t) {
    String n = String.valueOf(t).toLowerCase();
    if (n == 'integer')
      return 'int';
    if (n == 'anytype')
      return 'anyType';
    return n;
  }

  // =====================================================================
  // Apex classes & triggers
  // =====================================================================

  private Boolean stepClasses() {
    if (st.phase == 0) {
      for (ApexClass c : [
        SELECT Id, LengthWithoutComments
        FROM ApexClass
        ORDER BY Name
        LIMIT :maxListRows
      ]) {
        st.work.add(c.Id);
        st.workLens.add(
          c.LengthWithoutComments == null ? 0 : c.LengthWithoutComments
        );
      }
      st.phase = 1;
      return st.work.isEmpty();
    }
    List<Id> ids = nextBodyChunk();
    for (ApexClass c : [
      SELECT Id, Name, Body
      FROM ApexClass
      WHERE Id IN :ids
      ORDER BY Name
    ]) {
      if (String.isEmpty(c.Body)) {
        continue;
      }
      String body = c.Body;
      OI_TD_Rules.BodyResult r = OI_TD_Rules.analyzeBody(
        'ApexClass',
        c.Name,
        body,
        OI_TD_Rules.lineCount(body)
      );
      addFindings(r.codeQuality, G_CQ_CLASS);
      addFindings(r.governor, G_GOV_BODY);
      OI_TD_ScanState.ClassRec rec = new OI_TD_ScanState.ClassRec();
      rec.n = c.Name;
      rec.i = c.Id;
      rec.c = OI_TD_Rules.classifyApexClass(body);
      rec.b = OI_TD_Rules.isBatch(body);
      rec.x = OI_TD_Rules.isTestClass(body);
      rec.e = OI_TD_Rules.isEntryPoint(body);
      st.classes.add(rec);
      st.totalChars += body.length();
      st.totalUnits++;
      st.sectionCount++;
    }
    return st.cursor >= st.work.size();
  }

  private Boolean stepTriggers() {
    if (st.phase == 0) {
      for (ApexTrigger t : [
        SELECT Id, LengthWithoutComments
        FROM ApexTrigger
        ORDER BY Name
        LIMIT :maxListRows
      ]) {
        st.work.add(t.Id);
        st.workLens.add(
          t.LengthWithoutComments == null ? 0 : t.LengthWithoutComments
        );
      }
      st.phase = 1;
      return st.work.isEmpty();
    }
    List<Id> ids = nextBodyChunk();
    for (ApexTrigger t : [
      SELECT Id, Name, TableEnumOrId, Body
      FROM ApexTrigger
      WHERE Id IN :ids
      ORDER BY Name
    ]) {
      if (String.isEmpty(t.Body)) {
        continue;
      }
      String body = t.Body;
      String objectName = resolveTable(t.TableEnumOrId);
      OI_TD_Rules.BodyResult r = OI_TD_Rules.analyzeBody(
        'ApexTrigger',
        t.Name,
        body,
        OI_TD_Rules.lineCount(body)
      );
      addFindings(r.codeQuality, G_CQ_TRIGGER);
      addFindings(r.governor, G_GOV_BODY);
      addFindings(
        OI_TD_Rules.checkTriggerNaming(t.Name, objectName),
        G_CQ_NAMING
      );
      OI_TD_ScanState.TriggerRec rec = new OI_TD_ScanState.TriggerRec();
      rec.n = t.Name;
      rec.o = objectName;
      rec.i = t.Id;
      st.triggers.add(rec);
      st.totalChars += body.length();
      st.totalUnits++;
      st.sectionCount++;
    }
    return st.cursor >= st.work.size();
  }

  /** Next ids whose (comment-free) length fits the per-unit character budget. */
  private List<Id> nextBodyChunk() {
    List<Id> ids = new List<Id>();
    Integer chars = 0;
    while (st.cursor < st.work.size() && ids.size() < BODY_CHUNK_MAX) {
      Integer len = Math.max(st.workLens[st.cursor], 200);
      if (!ids.isEmpty() && chars + len > BODY_CHUNK_CHARS) {
        break;
      }
      ids.add(st.work[st.cursor]);
      chars += len;
      st.cursor++;
    }
    return ids;
  }

  // =====================================================================
  // Flows & workflow rules
  // =====================================================================

  private Boolean stepFlows() {
    if (st.phase == 0) {
      for (FlowDefinitionView f : [
        SELECT ApiName, NamespacePrefix, LatestVersionId
        FROM FlowDefinitionView
        LIMIT :maxListRows
      ]) {
        st.work.add(
          String.isBlank(f.NamespacePrefix)
            ? f.ApiName
            : f.NamespacePrefix + '__' + f.ApiName
        );
        st.work2.add(
          f.LatestVersionId == null ? null : String.valueOf(f.LatestVersionId)
        );
      }
      st.phase = 1;
      return st.work.isEmpty();
    }
    Integer startIdx = st.cursor;
    List<String> names = new List<String>();
    while (st.cursor < st.work.size() && names.size() < FLOW_READ_BATCH_SIZE) {
      names.add(st.work[st.cursor]);
      st.cursor++;
    }
    Map<String, Map<String, Object>> defs = readMetadataTolerant('Flow', names);
    for (Integer k = 0; k < names.size(); k++) {
      String name = names[k];
      Map<String, Object> d = defs.get(name);
      if (d == null) {
        d = new Map<String, Object>();
      }
      Map<String, Object> start = d.get('start') instanceof Map<String, Object>
        ? (Map<String, Object>) d.get('start')
        : new Map<String, Object>();
      OI_TD_ScanState.FlowRec rec = new OI_TD_ScanState.FlowRec();
      rec.a = name;
      rec.l = String.isBlank(str(d.get('label'))) ? name : str(d.get('label'));
      rec.s = String.isBlank(str(d.get('status')))
        ? 'Unknown'
        : str(d.get('status'));
      rec.tt = str(start.get('triggerType'));
      rec.o = str(start.get('object'));
      rec.p = str(d.get('processType'));
      rec.k = OI_TD_Rules.classifyFlow(rec.tt, rec.p);
      rec.i = st.work2[startIdx + k];
      st.flows.add(rec);
      addHayDoc('hay:flows', name, JSON.serialize(d));
      st.sectionCount++;
    }
    return st.cursor >= st.work.size();
  }

  private Boolean stepWorkflowRules() {
    if (st.phase == 0) {
      for (
        Map<String, Object> r : nextToolingPage(
          'SELECT Id, Name, TableEnumOrId FROM WorkflowRule'
        )
      ) {
        st.work.add(
          resolveTable(str(r.get('TableEnumOrId'))) + '.' + str(r.get('Name'))
        );
        st.work2.add(str(r.get('Id')));
      }
      if (st.nextUrl == null) {
        st.phase = 1;
        return st.work.isEmpty();
      }
      return false;
    }
    Integer startIdx = st.cursor;
    List<String> names = new List<String>();
    while (
      st.cursor < st.work.size() &&
      names.size() < METADATA_READ_BATCH_SIZE
    ) {
      names.add(st.work[st.cursor]);
      st.cursor++;
    }
    Map<String, Map<String, Object>> defs = readMetadataTolerant(
      'WorkflowRule',
      names
    );
    for (Integer k = 0; k < names.size(); k++) {
      String fullName = names[k];
      Map<String, Object> d = defs.get(fullName);
      Integer dot = fullName.indexOf('.');
      OI_TD_ScanState.WfRec rec = new OI_TD_ScanState.WfRec();
      rec.o = dot < 0 ? fullName : fullName.substring(0, dot);
      rec.n = dot < 0 ? fullName : fullName.substring(dot + 1);
      rec.ac = d != null && isTrue(d.get('active'));
      rec.tt = d == null ? null : str(d.get('triggerType'));
      rec.i = st.work2[startIdx + k];
      st.wfs.add(rec);
      st.sectionCount++;
    }
    return st.cursor >= st.work.size();
  }

  // =====================================================================
  // Lightning Web Components
  // =====================================================================

  private Boolean stepLwc() {
    if (st.phase == 0) {
      Set<String> seen = new Set<String>();
      for (OI_TD_ScanState.LwcRec l : st.lwcs) {
        seen.add(l.a);
      }
      for (
        Map<String, Object> r : nextToolingPage(
          'SELECT Id, LightningComponentBundleId, LightningComponentBundle.DeveloperName FROM LightningComponentResource ORDER BY LightningComponentBundleId'
        )
      ) {
        Map<String, Object> bundle = r.get(
            'LightningComponentBundle'
          ) instanceof Map<String, Object>
          ? (Map<String, Object>) r.get('LightningComponentBundle')
          : null;
        String name = bundle == null ? null : str(bundle.get('DeveloperName'));
        if (name == null) {
          continue;
        }
        st.work.add(str(r.get('Id')));
        st.work2.add(name);
        if (seen.add(name)) {
          OI_TD_ScanState.LwcRec rec = new OI_TD_ScanState.LwcRec();
          rec.a = name;
          rec.i = str(r.get('LightningComponentBundleId'));
          st.lwcs.add(rec);
        }
      }
      if (st.nextUrl == null) {
        st.phase = 1;
        st.sectionCount = st.lwcs.size();
        return st.work.isEmpty();
      }
      return false;
    }
    List<String> ids = new List<String>();
    Integer startIdx = st.cursor;
    while (st.cursor < st.work.size() && ids.size() < LWC_SOURCE_CHUNK) {
      ids.add(st.work[st.cursor]);
      st.cursor++;
    }
    Map<String, String> sourceById = new Map<String, String>();
    for (
      Map<String, Object> r : tooling.queryAll(
        'SELECT Id, Source FROM LightningComponentResource WHERE Id IN (' +
          quoteList(ids) +
          ')',
        5
      )
    ) {
      sourceById.put(str(r.get('Id')), str(r.get('Source')));
    }
    for (Integer k = 0; k < ids.size(); k++) {
      String source = sourceById.get(ids[k]);
      if (source != null) {
        addHayDoc('hay:lwc', st.work2[startIdx + k], source);
      }
    }
    return st.cursor >= st.work.size();
  }

  // =====================================================================
  // Email templates, Visualforce, packages
  // =====================================================================

  private Boolean stepEmail() {
    for (EmailTemplate t : [
      SELECT Id, Name, DeveloperName, TemplateType, IsActive
      FROM EmailTemplate
      ORDER BY Name
      LIMIT :maxListRows
    ]) {
      OI_TD_ScanState.EmailRec rec = new OI_TD_ScanState.EmailRec();
      rec.n = t.Name;
      rec.d = t.DeveloperName;
      rec.t = t.TemplateType;
      rec.ac = t.IsActive;
      rec.i = t.Id;
      st.emails.add(rec);
    }
    st.sectionCount = st.emails.size();
    return true;
  }

  private Boolean stepVfPages() {
    for (ApexPage p : [
      SELECT Id, Name
      FROM ApexPage
      ORDER BY Name
      LIMIT :maxListRows
    ]) {
      st.vfps.add(vfRec(p.Name, p.Id));
    }
    st.sectionCount = st.vfps.size();
    return true;
  }

  private Boolean stepVfComponents() {
    for (ApexComponent c : [
      SELECT Id, Name
      FROM ApexComponent
      ORDER BY Name
      LIMIT :maxListRows
    ]) {
      st.vfcs.add(vfRec(c.Name, c.Id));
    }
    st.sectionCount = st.vfcs.size();
    return true;
  }

  private static OI_TD_ScanState.VfRec vfRec(String name, String id) {
    OI_TD_ScanState.VfRec rec = new OI_TD_ScanState.VfRec();
    rec.n = name;
    rec.i = id;
    return rec;
  }

  private Boolean stepPackages() {
    for (
      Map<String, Object> r : tooling.queryAll(
        'SELECT Id, SubscriberPackage.Name, SubscriberPackage.NamespacePrefix, SubscriberPackageVersion.Name, ' +
        'SubscriberPackageVersion.MajorVersion, SubscriberPackageVersion.MinorVersion FROM InstalledSubscriberPackage',
        5
      )
    ) {
      Map<String, Object> pkg = r.get(
          'SubscriberPackage'
        ) instanceof Map<String, Object>
        ? (Map<String, Object>) r.get('SubscriberPackage')
        : null;
      Map<String, Object> ver = r.get(
          'SubscriberPackageVersion'
        ) instanceof Map<String, Object>
        ? (Map<String, Object>) r.get('SubscriberPackageVersion')
        : null;
      OI_TD_ScanState.PkgRec rec = new OI_TD_ScanState.PkgRec();
      rec.n = pkg == null || String.isBlank(str(pkg.get('Name')))
        ? 'Unknown package'
        : str(pkg.get('Name'));
      rec.ns = pkg == null ||
        str(pkg.get('NamespacePrefix')) == null
        ? ''
        : str(pkg.get('NamespacePrefix'));
      rec.vn = ver == null ? null : str(ver.get('Name'));
      rec.vv = ver == null
        ? null
        : str(ver.get('MajorVersion')) + '.' + str(ver.get('MinorVersion'));
      st.pkgs.add(rec);
    }
    st.sectionCount = st.pkgs.size();
    return true;
  }

  // =====================================================================
  // Profiles & permission sets
  // =====================================================================

  private Boolean stepPermissions() {
    if (st.phase == 0) {
      for (PermissionSet ps : [
        SELECT
          Id,
          Name,
          IsOwnedByProfile,
          ProfileId,
          Profile.Name,
          PermissionsAuthorApex,
          PermissionsManageUsers,
          PermissionsModifyAllData,
          PermissionsViewAllData
        FROM PermissionSet
        WHERE PermissionSetGroupId = NULL
        ORDER BY IsOwnedByProfile DESC, Name
        LIMIT :maxListRows
      ]) {
        OI_TD_Rules.AccessHolder h = new OI_TD_Rules.AccessHolder();
        Boolean isProfile = ps.IsOwnedByProfile;
        h.type = isProfile ? 'Profile' : 'PermissionSet';
        h.name = isProfile && ps.Profile != null ? ps.Profile.Name : ps.Name;
        Map<String, Boolean> granted = new Map<String, Boolean>{
          'AuthorApex' => ps.PermissionsAuthorApex,
          'ManageUsers' => ps.PermissionsManageUsers,
          'ModifyAllData' => ps.PermissionsModifyAllData,
          'ViewAllData' => ps.PermissionsViewAllData
        };
        for (String perm : RISKY_PERMS) {
          if (granted.get(perm) == true) {
            h.riskyPerms.add(perm);
          }
        }
        st.holders.add(h);
        OI_TD_ScanState.HolderRec rec = new OI_TD_ScanState.HolderRec();
        rec.n = h.name;
        rec.t = h.type;
        rec.i = isProfile ? ps.ProfileId : ps.Id;
        st.holderRecs.add(rec);
        st.work.add(ps.Id);
      }
      st.sectionCount = st.holders.size();
      st.phase = 1;
      return st.holders.isEmpty();
    }
    if (st.phase == 1) {
      Map<Id, OI_TD_Rules.AccessHolder> guests = new Map<Id, OI_TD_Rules.AccessHolder>();
      for (Integer k = 0; k < st.holders.size(); k++) {
        if (OI_TD_Rules.isGuestLike(st.holders[k].name)) {
          guests.put(st.work[k], st.holders[k]);
        }
      }
      if (!guests.isEmpty()) {
        Set<Id> guestIds = guests.keySet();
        for (ObjectPermissions op : [
          SELECT ParentId, SobjectType
          FROM ObjectPermissions
          WHERE
            ParentId IN :guestIds
            AND (PermissionsEdit = TRUE
            OR PermissionsDelete = TRUE)
          ORDER BY SobjectType
        ]) {
          guests.get(op.ParentId).writableObjects.add(op.SobjectType);
        }
      }
      st.phase = 2;
      return false;
    }
    Map<Id, Integer> indexById = new Map<Id, Integer>();
    while (
      st.cursor < st.work.size() &&
      indexById.size() < HOLDER_FIELD_CHUNK
    ) {
      indexById.put(st.work[st.cursor], st.cursor);
      st.cursor++;
    }
    Set<Id> ids = indexById.keySet();
    for (AggregateResult ar : [
      SELECT ParentId p, COUNT(Id) n
      FROM FieldPermissions
      WHERE PermissionsEdit = TRUE AND ParentId IN :ids
      GROUP BY ParentId
    ]) {
      Integer idx = indexById.get((Id) ar.get('p'));
      if (idx != null) {
        st.holders[idx].editableFieldCount = (Integer) ar.get('n');
      }
    }
    return st.cursor >= st.work.size();
  }

  // =====================================================================
  // Dependencies (MetadataComponentDependency)
  // =====================================================================

  private Boolean stepDependencies() {
    if (st.phase == 0) {
      Set<String> ids = new Set<String>();
      for (OI_TD_ScanState.ClassRec r : st.classes)
        addDepId(ids, r.i);
      for (OI_TD_ScanState.TriggerRec r : st.triggers)
        addDepId(ids, r.i);
      for (OI_TD_ScanState.FlowRec r : st.flows)
        addDepId(ids, r.i);
      for (OI_TD_ScanState.WfRec r : st.wfs)
        addDepId(ids, r.i);
      for (OI_TD_ScanState.LwcRec r : st.lwcs)
        addDepId(ids, r.i);
      for (OI_TD_ScanState.ObjRec r : st.objects)
        addDepId(ids, r.i);
      for (String id : st.fieldIds)
        addDepId(ids, id);
      for (OI_TD_ScanState.VfRec r : st.vfps)
        addDepId(ids, r.i);
      for (OI_TD_ScanState.VfRec r : st.vfcs)
        addDepId(ids, r.i);
      st.work.addAll(ids);
      st.phase = 1;
      return st.work.isEmpty();
    }
    List<String> batch = new List<String>();
    while (
      st.cursor < st.work.size() &&
      batch.size() < DEPENDENCY_QUERY_BATCH_SIZE
    ) {
      batch.add(st.work[st.cursor]);
      st.cursor++;
    }
    OI_TD_ToolingClient.QueryPage page = tooling.queryPage(
      'SELECT MetadataComponentId, MetadataComponentName, MetadataComponentType, RefMetadataComponentId, ' +
        'RefMetadataComponentName, RefMetadataComponentType FROM MetadataComponentDependency WHERE RefMetadataComponentId IN (' +
        quoteList(batch) +
        ')'
    );
    for (Map<String, Object> r : page.records) {
      String compId = normalizeId(str(r.get('MetadataComponentId')));
      String refId = normalizeId(str(r.get('RefMetadataComponentId')));
      Integer compIdx = refIdx(
        str(r.get('MetadataComponentType')),
        str(r.get('MetadataComponentName'))
      );
      Integer refIdxValue = refIdx(
        str(r.get('RefMetadataComponentType')),
        str(r.get('RefMetadataComponentName'))
      );
      if (!st.dependentsBySfId.containsKey(refId)) {
        st.dependentsBySfId.put(refId, new List<Integer>());
        st.depRefOrder.add(refId);
        st.refIdxBySfId.put(refId, refIdxValue);
      }
      addUnique(st.dependentsBySfId.get(refId), compIdx);
      if (!st.dependentIdsBySfId.containsKey(refId)) {
        st.dependentIdsBySfId.put(refId, new Set<String>());
      }
      st.dependentIdsBySfId.get(refId).add(compId);
      if (!st.referencesBySfId.containsKey(compId)) {
        st.referencesBySfId.put(compId, new List<Integer>());
      }
      addUnique(st.referencesBySfId.get(compId), refIdxValue);
      st.depRows++;
    }
    st.hasDep = st.depRows > 0;
    st.sectionCount = st.depRows;
    return st.cursor >= st.work.size();
  }

  private static void addDepId(Set<String> ids, String id) {
    if (String.isNotBlank(id) && SF_ID_RE.matcher(id).matches()) {
      ids.add(id);
    }
  }

  private static void addUnique(List<Integer> values, Integer value) {
    if (!values.contains(value)) {
      values.add(value);
    }
  }

  // =====================================================================
  // Sharing model, sharing rules, roles
  // =====================================================================

  private Boolean stepOwd() {
    List<String> names = new List<String>();
    while (
      st.cursor < st.targets.size() &&
      names.size() < OWD_QUERY_BATCH_SIZE
    ) {
      names.add(st.targets[st.cursor]);
      st.cursor++;
    }
    if (!names.isEmpty()) {
      Map<String, EntityDefinition> byName = new Map<String, EntityDefinition>();
      for (EntityDefinition ed : [
        SELECT
          QualifiedApiName,
          InternalSharingModel,
          ExternalSharingModel,
          IsCustomSetting
        FROM EntityDefinition
        WHERE QualifiedApiName IN :names
      ]) {
        byName.put(ed.QualifiedApiName, ed);
      }
      for (String name : names) {
        EntityDefinition ed = byName.get(name);
        if (
          ed == null ||
          ed.IsCustomSetting ||
          name.endsWith('__mdt') ||
          name.endsWith('__e')
        ) {
          continue;
        }
        String internalModel = ed.InternalSharingModel == null
          ? null
          : String.valueOf(ed.InternalSharingModel);
        if (String.isBlank(internalModel) || internalModel == 'None') {
          continue;
        }
        OI_TD_Rules.OwdInfo o = new OI_TD_Rules.OwdInfo();
        o.apiName = name;
        o.internalModel = internalModel;
        String externalModel = ed.ExternalSharingModel == null
          ? null
          : String.valueOf(ed.ExternalSharingModel);
        o.externalModel = externalModel == 'None' ? null : externalModel;
        st.owds.add(o);
      }
    }
    st.sectionCount = st.owds.size();
    return st.cursor >= st.targets.size();
  }

  private Boolean stepSharingRules() {
    if (st.phase == 0) {
      for (OI_TD_Rules.OwdInfo o : st.owds) {
        if (o.internalModel != 'ControlledByParent') {
          st.work.add(o.apiName);
        }
      }
      st.phase = 1;
      return st.work.isEmpty();
    }
    List<String> names = new List<String>();
    while (
      st.cursor < st.work.size() &&
      names.size() < METADATA_READ_BATCH_SIZE
    ) {
      names.add(st.work[st.cursor]);
      st.cursor++;
    }
    Map<String, Map<String, Object>> defs = readMetadataTolerant(
      'SharingRules',
      names
    );
    for (String name : names) {
      Map<String, Object> d = defs.get(name);
      if (d == null) {
        continue;
      }
      Integer n =
        sizeOf(d.get('sharingCriteriaRules')) +
        sizeOf(d.get('sharingOwnerRules')) +
        sizeOf(d.get('sharingGuestRules'));
      if (n > 0) {
        if (!st.ruleCounts.containsKey(name)) {
          st.ruleCounts.put(name, 0);
          st.ruleObjectOrder.add(name);
        }
        st.ruleCounts.put(name, st.ruleCounts.get(name) + n);
        st.sectionCount += n;
      }
    }
    return st.cursor >= st.work.size();
  }

  private Boolean stepRoles() {
    for (UserRole r : [
      SELECT Id, Name, DeveloperName, ParentRoleId
      FROM UserRole
      LIMIT :maxListRows
    ]) {
      OI_TD_Rules.RoleInfo info = new OI_TD_Rules.RoleInfo();
      info.sfId = r.Id;
      info.name = r.Name;
      info.parentRoleId = r.ParentRoleId;
      st.roles.add(info);
    }
    st.sectionCount = st.roles.size();
    return true;
  }

  // =====================================================================
  // Usage — substring search fallback for components without dependency data
  // =====================================================================

  private Boolean depPath(String sfId) {
    return st.hasDep && String.isNotBlank(sfId);
  }

  private Boolean stepUsage() {
    if (st.phase == 0) {
      buildNeedles();
      st.phase = st.needles.isEmpty() ? 5 : 1;
      return st.phase == 5;
    }
    if (matcher == null) {
      matcher = new OI_TD_UsageMatcher(st.needles);
    }
    if (st.phase == 1) {
      List<Id> ids = new List<Id>();
      while (st.cursor < st.classes.size() && ids.size() < USAGE_BODY_CHUNK) {
        ids.add(st.classes[st.cursor].i);
        st.cursor++;
      }
      Map<Id, ApexClass> byId = new Map<Id, ApexClass>(
        [SELECT Id, Name, Body FROM ApexClass WHERE Id IN :ids]
      );
      for (Id id : ids) {
        ApexClass c = byId.get(id);
        if (c != null) {
          indexDoc('ApexClass', c.Name, c.Body);
        }
      }
      nextUsagePhase(st.classes.size());
      return false;
    }
    if (st.phase == 2) {
      List<Id> ids = new List<Id>();
      while (st.cursor < st.triggers.size() && ids.size() < USAGE_BODY_CHUNK) {
        ids.add(st.triggers[st.cursor].i);
        st.cursor++;
      }
      Map<Id, ApexTrigger> byId = new Map<Id, ApexTrigger>(
        [SELECT Id, Name, Body FROM ApexTrigger WHERE Id IN :ids]
      );
      for (Id id : ids) {
        ApexTrigger t = byId.get(id);
        if (t != null) {
          indexDoc('ApexTrigger', t.Name, t.Body);
        }
      }
      nextUsagePhase(st.triggers.size());
      return false;
    }
    if (st.phase == 3) {
      if (st.cursor < st.flowPacks) {
        indexPack('Flow', 'hay:flows:' + st.cursor);
        st.cursor++;
      }
      nextUsagePhase(st.flowPacks);
      return false;
    }
    if (st.phase == 4) {
      if (st.cursor < st.lwcPacks) {
        indexPack('LightningWebComponent', 'hay:lwc:' + st.cursor);
        st.cursor++;
      }
      nextUsagePhase(st.lwcPacks);
      return st.phase == 5;
    }
    return true;
  }

  private void nextUsagePhase(Integer total) {
    if (st.cursor >= total) {
      st.phase++;
      st.cursor = 0;
    }
  }

  private void buildNeedles() {
    Set<String> n = new Set<String>();
    for (OI_TD_ScanState.ObjRec o : st.objects) {
      if (!depPath(o.i)) {
        n.add(o.a);
        if (o.a.endsWith('__c')) {
          n.add(OI_TD_Rules.objectNeedle(o.a));
        }
      }
    }
    n.addAll(st.hasDep ? st.noIdFieldNames : st.allFieldNames);
    for (OI_TD_ScanState.ClassRec r : st.classes)
      if (!depPath(r.i))
        n.add(r.n);
    for (OI_TD_ScanState.TriggerRec r : st.triggers)
      if (!depPath(r.i))
        n.add(r.n);
    for (OI_TD_ScanState.FlowRec r : st.flows)
      if (!depPath(r.i))
        n.add(r.a);
    for (OI_TD_ScanState.WfRec r : st.wfs)
      if (!depPath(r.i))
        n.add(r.n);
    for (OI_TD_ScanState.LwcRec r : st.lwcs)
      if (!depPath(r.i))
        n.add(r.a);
    for (OI_TD_ScanState.VfRec r : st.vfps)
      if (!depPath(r.i))
        n.add(r.n);
    for (OI_TD_ScanState.VfRec r : st.vfcs)
      if (!depPath(r.i))
        n.add(r.n);
    n.remove(null);
    n.remove('');
    st.needles = n;
  }

  private void indexPack(String type, String kind) {
    String payload = OI_TD_DataStore.read(st.scanId, kind);
    if (String.isBlank(payload)) {
      return;
    }
    for (Object raw : (List<Object>) JSON.deserializeUntyped(payload)) {
      List<Object> doc = (List<Object>) raw;
      indexDoc(type, (String) doc[0], (String) doc[1]);
    }
  }

  private void indexDoc(String type, String name, String text) {
    if (String.isEmpty(text)) {
      return;
    }
    Integer idx = refIdx(type, name);
    for (String needle : matcher.match(text)) {
      List<Integer> hits = st.hits.get(needle);
      if (hits == null) {
        hits = new List<Integer>();
        st.hits.put(needle, hits);
      }
      if (hits.isEmpty() || hits[hits.size() - 1] != idx) {
        hits.add(idx);
      }
    }
  }

  /** Substring hits for a needle, excluding documents that carry the same name (a component doesn't "use" itself). */
  private List<Integer> filteredHits(String needle) {
    List<Integer> out = new List<Integer>();
    List<Integer> raw = st.hits.get(needle);
    if (raw == null) {
      return out;
    }
    Set<Integer> seen = new Set<Integer>();
    for (Integer idx : raw) {
      if (st.refs[idx][1] != needle && seen.add(idx)) {
        out.add(idx);
      }
    }
    return out;
  }

  /** Fallback "is used" for data quality: any hit in a scanned class, trigger or flow. */
  private Boolean anyCodeHit(String needle) {
    List<Integer> raw = st.hits.get(needle);
    if (raw == null) {
      return false;
    }
    for (Integer idx : raw) {
      String type = st.refs[idx][0];
      if (type == 'ApexClass' || type == 'ApexTrigger' || type == 'Flow') {
        return true;
      }
    }
    return false;
  }

  private List<Integer> dependentsOf(String sfId) {
    List<Integer> v = st.dependentsBySfId.get(sfId);
    return v == null ? new List<Integer>() : v;
  }

  private List<Integer> referencesOf(String sfId) {
    List<Integer> v = st.referencesBySfId.get(sfId);
    return v == null ? new List<Integer>() : v;
  }

  private Integer refIdx(String type, String name) {
    String key = type + '\u0001' + name;
    Integer idx = st.refIndex.get(key);
    if (idx == null) {
      idx = st.refs.size();
      st.refs.add(new List<String>{ type, name });
      st.refIndex.put(key, idx);
    }
    return idx;
  }

  // =====================================================================
  // Finalize — resolve usage and write the component inventory
  // =====================================================================

  private Boolean stepFinalize() {
    if (st.phase == 0) {
      Integer used = 0;
      for (OI_TD_ScanState.ObjRec r : st.objects) {
        r.u = usageOf(r.i, r.a);
        r.r = refsOf(r.i);
        if (!r.u.isEmpty())
          used++;
      }
      st.usedCounts.put('objects', used);
      used = 0;
      for (OI_TD_ScanState.ClassRec r : st.classes) {
        r.u = usageOf(r.i, r.n);
        r.r = refsOf(r.i);
        if (!r.u.isEmpty())
          used++;
      }
      st.usedCounts.put('classes', used);
      used = 0;
      for (OI_TD_ScanState.TriggerRec r : st.triggers) {
        r.u = usageOf(r.i, r.n);
        r.r = refsOf(r.i);
        if (!r.u.isEmpty())
          used++;
      }
      st.usedCounts.put('triggers', used);
      used = 0;
      for (OI_TD_ScanState.FlowRec r : st.flows) {
        r.u = usageOf(r.i, r.a);
        r.r = refsOf(r.i);
        if (!r.u.isEmpty())
          used++;
      }
      st.usedCounts.put('flows', used);
      used = 0;
      for (OI_TD_ScanState.WfRec r : st.wfs) {
        r.u = usageOf(r.i, r.n);
        r.r = refsOf(r.i);
        if (!r.u.isEmpty())
          used++;
      }
      st.usedCounts.put('workflowRules', used);
      used = 0;
      for (OI_TD_ScanState.LwcRec r : st.lwcs) {
        r.u = usageOf(r.i, r.a);
        r.r = refsOf(r.i);
        if (!r.u.isEmpty())
          used++;
      }
      st.usedCounts.put('lwc', used);
      used = 0;
      for (OI_TD_ScanState.VfRec r : st.vfps) {
        r.u = usageOf(r.i, r.n);
        r.r = refsOf(r.i);
        if (!r.u.isEmpty())
          used++;
      }
      st.usedCounts.put('vfPages', used);
      used = 0;
      for (OI_TD_ScanState.VfRec r : st.vfcs) {
        r.u = usageOf(r.i, r.n);
        r.r = refsOf(r.i);
        if (!r.u.isEmpty())
          used++;
      }
      st.usedCounts.put('vfComponents', used);

      writeKind('objects', JSON.serialize(st.objects, true));
      writeKind('classes', JSON.serialize(st.classes, true));
      writeKind('triggers', JSON.serialize(st.triggers, true));
      writeKind('flows', JSON.serialize(st.flows, true));
      writeKind('wf', JSON.serialize(st.wfs, true));
      writeKind('lwc', JSON.serialize(st.lwcs, true));
      writeKind('vfp', JSON.serialize(st.vfps, true));
      writeKind('vfc', JSON.serialize(st.vfcs, true));
      writeKind('email', JSON.serialize(st.emails, true));
      writeKind('pkgs', JSON.serialize(st.pkgs, true));
      writeKind('holders', JSON.serialize(st.holderRecs, true));
      st.phase = 1;
      return false;
    }
    if (st.phase == 1) {
      if (st.cursor < st.shardSeq) {
        finalizeShard(st.cursor);
        st.cursor++;
      }
      if (st.cursor >= st.shardSeq) {
        st.phase = 2;
      }
      return false;
    }
    st.usedCounts.put('fields', st.fieldsUsed);
    writeKind('refs', JSON.serialize(st.refs));
    return true;
  }

  private List<Integer> usageOf(String sfId, String name) {
    return depPath(sfId) ? dependentsOf(sfId) : filteredHits(name);
  }

  private List<Integer> refsOf(String sfId) {
    return depPath(sfId) ? referencesOf(sfId) : new List<Integer>();
  }

  private void writeKind(String kind, String payload) {
    st.pendingData.addAll(OI_TD_DataStore.chunks(st.scanId, kind, payload));
  }

  private void finalizeShard(Integer seq) {
    String payload = OI_TD_DataStore.read(st.scanId, 'fields:' + seq);
    if (String.isBlank(payload)) {
      return;
    }
    Map<String, Object> shard = (Map<String, Object>) JSON.deserializeUntyped(
      payload
    );
    Map<String, Object> needleHits = new Map<String, Object>();
    Map<String, Object> depUsage = new Map<String, Object>();
    Map<String, List<Integer>> computed = new Map<String, List<Integer>>();
    for (String objectName : shard.keySet()) {
      List<String> names = new List<String>();
      for (Object raw : (List<Object>) shard.get(objectName)) {
        Map<String, Object> f = (Map<String, Object>) raw;
        String api = (String) f.get('a');
        String sfId = (String) f.get('i');
        Boolean dp = depPath(sfId);
        List<Integer> u;
        if (dp) {
          u = dependentsOf(sfId);
          List<Integer> r = referencesOf(sfId);
          if (!u.isEmpty() || !r.isEmpty()) {
            depUsage.put(objectName + '.' + api, new List<Object>{ u, r });
          }
        } else {
          u = computed.get(api);
          if (u == null) {
            u = filteredHits(api);
            computed.put(api, u);
            if (!u.isEmpty()) {
              needleHits.put(api, u);
            }
          }
        }
        if (!u.isEmpty()) {
          st.fieldsUsed++;
        }
        if (api.endsWith('__c')) {
          Boolean isUsed = dp
            ? st.dependentsBySfId.containsKey(sfId)
            : anyCodeHit(api);
          if (!isUsed) {
            addFinding(
              OI_TD_Rules.unusedField(objectName, api, dp),
              G_DQ_UNUSED_FIELD
            );
          }
        }
        names.add(api);
      }
      addFindings(
        OI_TD_Rules.duplicateFields(objectName, names),
        G_DQ_DUPLICATE
      );
    }
    writeKind(
      'fu:' + seq,
      JSON.serialize(
        new Map<String, Object>{ 'n' => needleHits, 'd' => depUsage }
      )
    );
  }

  // =====================================================================
  // Analyze — the cross-component analyzers
  // =====================================================================

  private Boolean stepAnalyze() {
    List<OI_TD_Rules.FlowInfo> flowInfos = new List<OI_TD_Rules.FlowInfo>();
    for (OI_TD_ScanState.FlowRec r : st.flows) {
      OI_TD_Rules.FlowInfo f = new OI_TD_Rules.FlowInfo();
      f.apiName = r.a;
      f.label = r.l;
      f.status = r.s;
      f.triggerType = r.tt;
      f.objectName = r.o;
      flowInfos.add(f);
    }
    List<OI_TD_Rules.TriggerInfo> triggerInfos = new List<OI_TD_Rules.TriggerInfo>();
    for (OI_TD_ScanState.TriggerRec r : st.triggers) {
      OI_TD_Rules.TriggerInfo t = new OI_TD_Rules.TriggerInfo();
      t.name = r.n;
      t.objectName = r.o;
      triggerInfos.add(t);
    }
    List<OI_TD_Rules.ObjectInfo> objectInfos = new List<OI_TD_Rules.ObjectInfo>();
    for (OI_TD_ScanState.ObjRec r : st.objects) {
      OI_TD_Rules.ObjectInfo o = new OI_TD_Rules.ObjectInfo();
      o.apiName = r.a;
      o.fieldCount = r.c;
      objectInfos.add(o);
    }

    addFindings(
      OI_TD_Rules.analyzeAutomation(flowInfos, triggerInfos),
      OI_TD_Rules.A_AUTOMATION * 10
    );

    List<OI_TD_Rules.NewFinding> arch = OI_TD_Rules.analyzeArchitecture(
      objectInfos,
      triggerInfos,
      flowInfos,
      st.outgoingOrder,
      st.outgoingByObject,
      new List<OI_TD_Rules.DependencyInfo>()
    );
    for (String refId : st.depRefOrder) {
      List<String> ref = st.refs[st.refIdxBySfId.get(refId)];
      OI_TD_Rules.NewFinding god = OI_TD_Rules.godComponent(
        ref[1],
        ref[0],
        st.dependentIdsBySfId.get(refId).size()
      );
      if (god != null) {
        arch.add(god);
      }
    }
    addFindings(arch, OI_TD_Rules.A_ARCHITECTURE * 10);

    addFindings(
      OI_TD_Rules.analyzeSecurity(st.holders),
      OI_TD_Rules.A_SECURITY * 10
    );

    List<String> ruleObjectNames = new List<String>();
    for (String name : st.ruleObjectOrder) {
      for (Integer k = 0; k < st.ruleCounts.get(name); k++) {
        ruleObjectNames.add(name);
      }
    }
    addFindings(
      OI_TD_Rules.analyzeSharingSecurity(st.owds, ruleObjectNames, st.roles),
      OI_TD_Rules.A_SHARING * 10
    );

    for (OI_TD_ScanState.ObjRec r : st.objects) {
      if (!r.a.endsWith('__c'))
        continue;
      Boolean dp = depPath(r.i);
      Boolean isUsed = dp
        ? st.dependentsBySfId.containsKey(r.i)
        : anyCodeHit(OI_TD_Rules.objectNeedle(r.a));
      if (!isUsed) {
        addFinding(OI_TD_Rules.unusedObject(r.a, dp), G_DQ_UNUSED_OBJECT);
      }
    }
    if (st.hasDep) {
      for (OI_TD_ScanState.ClassRec r : st.classes) {
        if (String.isBlank(r.i) || r.x || r.e)
          continue;
        if (!st.dependentsBySfId.containsKey(r.i)) {
          addFinding(OI_TD_Rules.unusedApexClass(r.n), G_DQ_UNUSED_CLASS);
        }
      }
      for (OI_TD_ScanState.LwcRec r : st.lwcs) {
        if (String.isBlank(r.i))
          continue;
        if (!st.dependentsBySfId.containsKey(r.i)) {
          addFinding(OI_TD_Rules.unusedLwc(r.a), G_DQ_UNUSED_LWC);
        }
      }
    }

    addFindings(
      OI_TD_Rules.orgApexFindings(st.totalChars, st.totalUnits),
      G_GOV_ORG
    );
    return true;
  }

  // =====================================================================
  // Complete — health score, summary, cleanup
  // =====================================================================

  private Boolean stepComplete() {
    List<String> categories = new List<String>();
    List<String> severities = new List<String>();
    Id scanId = st.scanId;
    for (AggregateResult ar : [
      SELECT Category__c c, Severity__c s, COUNT(Id) n
      FROM OI_TD_Finding__c
      WHERE Scan__c = :scanId
      GROUP BY Category__c, Severity__c
    ]) {
      Integer n = (Integer) ar.get('n');
      for (Integer k = 0; k < n; k++) {
        categories.add((String) ar.get('c'));
        severities.add((String) ar.get('s'));
      }
    }
    OI_TD_Rules.Health health = OI_TD_Rules.computeHealth(
      categories,
      severities
    );

    Map<String, Object> counts = new Map<String, Object>{
      'objects' => st.objects.size(),
      'fields' => st.fieldTotal,
      'classes' => st.classes.size(),
      'triggers' => st.triggers.size(),
      'flows' => st.flows.size(),
      'lwc' => st.lwcs.size(),
      'vfPages' => st.vfps.size(),
      'vfComponents' => st.vfcs.size(),
      'workflowRules' => st.wfs.size(),
      'emailTemplates' => st.emails.size(),
      'packages' => st.pkgs.size()
    };
    Map<String, Object> summary = new Map<String, Object>{
      'counts' => counts,
      'used' => st.usedCounts,
      'hasDependencyData' => st.hasDep
    };

    update new OI_TD_Scan__c(
      Id = scanId,
      Status__c = STATUS_COMPLETED,
      Finished_At__c = System.now(),
      Current_Stage__c = null,
      Overall_Score__c = health.overall,
      Category_Scores__c = JSON.serialize(health.categoryScores),
      Total_Findings__c = health.totalFindings,
      Summary__c = JSON.serialize(summary),
      Section_Results__c = JSON.serialize(st.sections)
    );
    delete [
      SELECT Id
      FROM OI_TD_Scan_Data__c
      WHERE Scan__c = :scanId AND Kind__c LIKE 'hay:%'
      LIMIT 5000
    ];
    st.stage = S_DONE;
    return false;
  }

  // =====================================================================
  // Findings
  // =====================================================================

  private void addFindings(
    List<OI_TD_Rules.NewFinding> findings,
    Integer groupKey
  ) {
    for (OI_TD_Rules.NewFinding f : findings) {
      addFinding(f, groupKey);
    }
  }

  private void addFinding(OI_TD_Rules.NewFinding f, Integer groupKey) {
    Integer counter = st.counters.containsKey(groupKey)
      ? st.counters.get(groupKey)
      : 0;
    st.counters.put(groupKey, counter + 1);
    Integer analyzer = groupKey / 10;
    Integer grp = Math.mod(groupKey, 10);
    st.pendingFindings.add(
      new OI_TD_Finding__c(
        Scan__c = st.scanId,
        Category__c = f.category,
        Rule_Key__c = f.ruleKey,
        Severity__c = f.severity,
        Title__c = f.title == null ? null : f.title.abbreviate(255),
        Detail__c = f.detail == null ? null : f.detail.left(32768),
        Component_Type__c = f.componentType,
        Component_Name__c = f.componentName == null
          ? null
          : f.componentName.left(255),
        Status__c = 'open',
        Sort_Order__c = analyzer * 10000000L + grp * 1000000L + counter
      )
    );
  }

  // =====================================================================
  // Haystack packs
  // =====================================================================

  private void addHayDoc(String kind, String name, String text) {
    if (String.isEmpty(text)) {
      return;
    }
    Integer pos = 0;
    while (pos < text.length()) {
      Integer room = HAY_CHARS - st.hayChars;
      if (room < 2000) {
        writeHay(kind);
        room = HAY_CHARS;
      }
      Integer endPos = Math.min(text.length(), pos + room);
      if (endPos < text.length()) {
        endPos = splitPoint(text, pos, endPos);
      }
      String part = text.substring(pos, endPos);
      st.hayBuffer.add(new List<String>{ name, part });
      st.hayChars += part.length() + name.length() + 8;
      pos = endPos;
    }
  }

  /** Split just after a non-word character so no identifier is cut in two. */
  private static Integer splitPoint(
    String text,
    Integer startPos,
    Integer endPos
  ) {
    Integer floor = Math.max(startPos + 1, endPos - 500);
    for (Integer k = endPos; k > floor; k--) {
      Integer ch = text.charAt(k - 1);
      Boolean word =
        (ch >= 48 &&
        ch <= 57) ||
        (ch >= 65 &&
        ch <= 90) ||
        (ch >= 97 &&
        ch <= 122) ||
        ch == 95;
      if (!word) {
        return k;
      }
    }
    return endPos;
  }

  private void writeHay(String kind) {
    if (st.hayBuffer.isEmpty()) {
      return;
    }
    Integer seq;
    if (kind == 'hay:flows') {
      seq = st.flowPacks++;
    } else {
      seq = st.lwcPacks++;
    }
    st.pendingData.addAll(
      OI_TD_DataStore.chunks(
        st.scanId,
        kind + ':' + seq,
        JSON.serialize(st.hayBuffer)
      )
    );
    st.hayBuffer = new List<List<String>>();
    st.hayChars = 0;
  }

  // =====================================================================
  // Callout helpers
  // =====================================================================

  private List<Map<String, Object>> nextToolingPage(String soql) {
    OI_TD_ToolingClient.QueryPage page = st.nextUrl == null
      ? tooling.queryPage(soql)
      : tooling.nextPage(st.nextUrl);
    st.nextUrl = page.nextRecordsUrl;
    return page.records;
  }

  /** readMetadata keyed by fullName; if a batch fails, retries one by one so one bad component can't sink the rest. */
  private Map<String, Map<String, Object>> readMetadataTolerant(
    String type,
    List<String> names
  ) {
    try {
      return matchRecords(
        names,
        extractRecords(metadata.readMetadata(type, names))
      );
    } catch (Exception batchError) {
      if (names.size() == 1) {
        return new Map<String, Map<String, Object>>();
      }
      Map<String, Map<String, Object>> out = new Map<String, Map<String, Object>>();
      for (String name : names) {
        try {
          out.putAll(
            matchRecords(
              new List<String>{ name },
              extractRecords(
                metadata.readMetadata(type, new List<String>{ name })
              )
            )
          );
        } catch (Exception singleError) {
          // This component can't be read (e.g. managed/protected) — it's recorded without details.
          out.put(name, null);
        }
      }
      return out;
    }
  }

  @TestVisible
  private static List<Map<String, Object>> extractRecords(
    List<Map<String, Object>> results
  ) {
    List<Map<String, Object>> out = new List<Map<String, Object>>();
    for (Map<String, Object> res : results) {
      if (res == null) {
        continue;
      }
      Object recs = res.get('records');
      if (recs instanceof List<Object>) {
        for (Object o : (List<Object>) recs) {
          out.add(
            o instanceof Map<String, Object> ? (Map<String, Object>) o : null
          );
        }
      } else if (recs instanceof Map<String, Object>) {
        out.add((Map<String, Object>) recs);
      } else {
        out.add(null);
      }
    }
    return out;
  }

  @TestVisible
  private static Map<String, Map<String, Object>> matchRecords(
    List<String> names,
    List<Map<String, Object>> records
  ) {
    Map<String, Map<String, Object>> byFullName = new Map<String, Map<String, Object>>();
    for (Map<String, Object> r : records) {
      if (r != null && r.get('fullName') != null) {
        byFullName.put(String.valueOf(r.get('fullName')).toLowerCase(), r);
      }
    }
    Map<String, Map<String, Object>> out = new Map<String, Map<String, Object>>();
    for (Integer k = 0; k < names.size(); k++) {
      Map<String, Object> r = byFullName.get(names[k].toLowerCase());
      if (r == null && byFullName.isEmpty() && k < records.size()) {
        r = records[k];
      }
      out.put(names[k], r);
    }
    return out;
  }

  // =====================================================================
  // Small helpers
  // =====================================================================

  private static String quoteList(List<String> values) {
    List<String> quoted = new List<String>();
    for (String v : values) {
      quoted.add('\'' + String.escapeSingleQuotes(v) + '\'');
    }
    return String.join(quoted, ',');
  }

  private static String normalizeId(String value) {
    if (value == null || value.length() != 15) {
      return value;
    }
    try {
      return String.valueOf(Id.valueOf(value));
    } catch (Exception e) {
      return value;
    }
  }

  private static List<Object> asList(Object value) {
    if (value instanceof List<Object>) {
      return (List<Object>) value;
    }
    return value == null ? new List<Object>() : new List<Object>{ value };
  }

  private static Integer sizeOf(Object value) {
    if (value instanceof List<Object>) {
      return ((List<Object>) value).size();
    }
    return value == null ? 0 : 1;
  }

  private static String str(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  private static Boolean isTrue(Object value) {
    return value == true ||
      (value instanceof String && ((String) value).equalsIgnoreCase('true'));
  }

  private static String message(Exception e) {
    String m = e.getMessage();
    return String.isBlank(m) ? e.getTypeName() : m.left(1000);
  }
}
