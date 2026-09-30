/**
 * Purpose: The @AuraEnabled boundary for the Tech Debt tab (oiTdApp and its pages) — the native
 *          equivalent of the reference app's /scans, /findings and /connections REST routes.
 * Responsibilities: Permission check -> read/write OI_TD_* data (or delegate to OI_TD_ScanService /
 *                    OI_TD_AiService) -> map to a DTO -> return, translating failures into sanitized
 *                    AuraHandledExceptions exactly like OI_OrgHealthController.translate.
 *                    Component inventories are returned as the stored compact JSON (short keys,
 *                    usage as indices into the scan's "refs" table) and expanded client-side by
 *                    oiTdUtils — keeps Apex heap/CPU flat even for very large orgs.
 * Dependencies: OI_SecurityService, OI_TD_ScanService, OI_TD_AiService, OI_TD_DataStore,
 *               OI_TD_ToolingClient, OI_TD_Rules.
 * Limitations: Reads gated by OI_View_Org_Health; Run Scan by OI_Run_Scan; finding workflow and
 *              AI explanations by OI_Manage_Finding_Workflow; the schedule by OI_Manage_Settings.
 */
public with sharing class OI_TD_Controller {
  private static final String PERM_VIEW = 'OI_View_Org_Health';
  private static final String PERM_RUN = 'OI_Run_Scan';
  private static final String PERM_MANAGE = 'OI_Manage_Finding_Workflow';
  private static final String PERM_SETTINGS = 'OI_Manage_Settings';
  public static final List<String> FINDING_STATUSES = new List<String>{
    'open',
    'acknowledged',
    'resolved',
    'wont_fix'
  };
  private static final Map<String, Integer> SEVERITY_ORDER = new Map<String, Integer>{
    'critical' => 0,
    'high' => 1,
    'medium' => 2,
    'low' => 3
  };
  private static final List<String> COMPONENT_KINDS = new List<String>{
    'objects',
    'classes',
    'triggers',
    'flows',
    'wf',
    'lwc',
    'vfp',
    'vfc',
    'email',
    'pkgs',
    'refs'
  };

  @TestVisible
  private static OI_TD_ToolingClient toolingOverride;

  // =====================================================================
  // DTOs
  // =====================================================================

  public class AppContext {
    @AuraEnabled
    public Boolean canRunScan;
    @AuraEnabled
    public Boolean canManageFindings;
    @AuraEnabled
    public Boolean canManageSettings;
  }

  public class ScanDTO {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Datetime startedAt;
    @AuraEnabled
    public Datetime finishedAt;
    @AuraEnabled
    public String currentStage;
    @AuraEnabled
    public String error;
    @AuraEnabled
    public Integer overall;
    @AuraEnabled
    public Integer totalFindings;
    @AuraEnabled
    public String triggeredBy;
    /** Sections the scan could not read (a completed scan can still be partial); empty when every section succeeded. */
    @AuraEnabled
    public List<SectionIssue> failedSections;
  }

  public class SectionIssue {
    @AuraEnabled
    public String category;
    @AuraEnabled
    public String error;
  }

  public class HealthDTO {
    @AuraEnabled
    public Integer overall;
    @AuraEnabled
    public Map<String, Integer> categoryScores;
    @AuraEnabled
    public Integer totalFindings;
  }

  public class FindingDTO {
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public Id scanId { get; set; }
    @AuraEnabled
    public String category { get; set; }
    @AuraEnabled
    public String ruleKey { get; set; }
    @AuraEnabled
    public String severity { get; set; }
    @AuraEnabled
    public String title { get; set; }
    @AuraEnabled
    public String detail { get; set; }
    @AuraEnabled
    public String componentType { get; set; }
    @AuraEnabled
    public String componentName { get; set; }
    @AuraEnabled
    public String status { get; set; }
    @AuraEnabled
    public String assignedTo { get; set; }
    @AuraEnabled
    public String aiExplanation { get; set; }
    @AuraEnabled
    public String aiRecommendation { get; set; }
  }

  public class DiffDTO {
    @AuraEnabled
    public Id previousScanId;
    @AuraEnabled
    public List<FindingDTO> newFindings = new List<FindingDTO>();
    @AuraEnabled
    public List<FindingDTO> resolvedFindings = new List<FindingDTO>();
  }

  public class HistoryPoint {
    @AuraEnabled
    public Id scanId;
    @AuraEnabled
    public Datetime startedAt;
    @AuraEnabled
    public Integer overall;
  }

  public class AccessGrant {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public String level;
    public AccessGrant(String name, String type, String level) {
      this.name = name;
      this.type = type;
      this.level = level;
    }
  }

  public class CategoryScore {
    @AuraEnabled
    public String category { get; set; }
    @AuraEnabled
    public Integer score { get; set; }
  }

  public class ReportDTO {
    @AuraEnabled
    public String org { get; set; }
    @AuraEnabled
    public String scanDate { get; set; }
    @AuraEnabled
    public Integer overall { get; set; }
    @AuraEnabled
    public Integer totalFindings { get; set; }
    @AuraEnabled
    public List<CategoryScore> categoryScores { get; set; }
    @AuraEnabled
    public List<FindingDTO> findings { get; set; }

    public ReportDTO() {
      categoryScores = new List<CategoryScore>();
      findings = new List<FindingDTO>();
    }
  }

  // =====================================================================
  // App shell
  // =====================================================================

  @AuraEnabled
  public static AppContext getAppContext() {
    try {
      OI_SecurityService.assertPermission(PERM_VIEW);
      AppContext ctx = new AppContext();
      ctx.canRunScan = OI_SecurityService.hasPermission(PERM_RUN);
      ctx.canManageFindings = OI_SecurityService.hasPermission(PERM_MANAGE);
      ctx.canManageSettings = OI_SecurityService.hasPermission(PERM_SETTINGS);
      return ctx;
    } catch (Exception e) {
      throw translate(e);
    }
  }

  @AuraEnabled
  public static OI_TD_ScanService.ScheduleInfo getSchedule() {
    try {
      OI_SecurityService.assertPermission(PERM_VIEW);
      return OI_TD_ScanService.getSchedule();
    } catch (Exception e) {
      throw translate(e);
    }
  }

  @AuraEnabled
  public static OI_TD_ScanService.ScheduleInfo updateSchedule(
    String frequency
  ) {
    try {
      OI_SecurityService.assertPermission(PERM_SETTINGS);
      return OI_TD_ScanService.updateSchedule(frequency);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  // =====================================================================
  // Scans
  // =====================================================================

  /** All scans, newest first (the reference's GET /scans). Not cacheable — polled while scanning. */
  @AuraEnabled
  public static List<ScanDTO> getScans() {
    try {
      OI_SecurityService.assertPermission(PERM_VIEW);
      OI_TD_ScanService.healStaleScans();
      List<ScanDTO> out = new List<ScanDTO>();
      for (OI_TD_Scan__c s : [
        SELECT
          Id,
          Status__c,
          Started_At__c,
          Finished_At__c,
          Current_Stage__c,
          Error__c,
          Overall_Score__c,
          Total_Findings__c,
          Triggered_By__c,
          Section_Results__c
        FROM OI_TD_Scan__c
        ORDER BY Started_At__c DESC
        LIMIT 500
      ]) {
        ScanDTO d = new ScanDTO();
        d.id = s.Id;
        d.status = s.Status__c;
        d.startedAt = s.Started_At__c;
        d.finishedAt = s.Finished_At__c;
        d.currentStage = s.Current_Stage__c;
        d.error = s.Error__c == null ? null : s.Error__c.left(1000);
        d.overall = s.Overall_Score__c == null
          ? null
          : s.Overall_Score__c.intValue();
        d.totalFindings = s.Total_Findings__c == null
          ? null
          : s.Total_Findings__c.intValue();
        d.triggeredBy = s.Triggered_By__c;
        d.failedSections = failedSections(s.Section_Results__c);
        out.add(d);
      }
      return out;
    } catch (Exception e) {
      throw translate(e);
    }
  }

  @AuraEnabled
  public static Id startScan() {
    try {
      OI_SecurityService.assertPermission(PERM_RUN);
      return OI_TD_ScanService.startScan(OI_TD_ScanService.TRIGGER_MANUAL);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static HealthDTO getHealth(Id scanId) {
    try {
      OI_SecurityService.assertPermission(PERM_VIEW);
      return health(requireScan(scanId));
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** Completed scans oldest first with their overall score (GET /connections/:id/health-history). */
  @AuraEnabled
  public static List<HistoryPoint> getHealthHistory() {
    try {
      OI_SecurityService.assertPermission(PERM_VIEW);
      List<HistoryPoint> out = new List<HistoryPoint>();
      for (OI_TD_Scan__c s : [
        SELECT
          Id,
          Started_At__c,
          Overall_Score__c,
          Category_Scores__c,
          Total_Findings__c
        FROM OI_TD_Scan__c
        WHERE Status__c = :OI_TD_ScanEngine.STATUS_COMPLETED
        ORDER BY Started_At__c ASC
        LIMIT 500
      ]) {
        HistoryPoint p = new HistoryPoint();
        p.scanId = s.Id;
        p.startedAt = s.Started_At__c;
        p.overall = health(s).overall;
        out.add(p);
      }
      return out;
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** New vs resolved findings compared with the previous completed scan (GET /scans/:id/diff). */
  @AuraEnabled
  public static DiffDTO getDiff(Id scanId) {
    try {
      OI_SecurityService.assertPermission(PERM_VIEW);
      OI_TD_Scan__c scan = requireScan(scanId);
      DiffDTO diff = new DiffDTO();
      List<OI_TD_Scan__c> previous = [
        SELECT Id
        FROM OI_TD_Scan__c
        WHERE
          Status__c = :OI_TD_ScanEngine.STATUS_COMPLETED
          AND Started_At__c < :scan.Started_At__c
        ORDER BY Started_At__c DESC
        LIMIT 1
      ];
      if (previous.isEmpty()) {
        return diff;
      }
      diff.previousScanId = previous[0].Id;
      List<FindingDTO> current = findingsOf(scanId);
      List<FindingDTO> prior = findingsOf(previous[0].Id);
      Set<String> priorKeys = new Set<String>();
      for (FindingDTO f : prior)
        priorKeys.add(findingKey(f));
      Set<String> currentKeys = new Set<String>();
      for (FindingDTO f : current)
        currentKeys.add(findingKey(f));
      for (FindingDTO f : current) {
        if (!priorKeys.contains(findingKey(f)))
          diff.newFindings.add(f);
      }
      for (FindingDTO f : prior) {
        if (!currentKeys.contains(findingKey(f)))
          diff.resolvedFindings.add(f);
      }
      return diff;
    } catch (Exception e) {
      throw translate(e);
    }
  }

  // =====================================================================
  // Findings
  // =====================================================================

  @AuraEnabled
  public static List<FindingDTO> getFindings(Id scanId) {
    try {
      OI_SecurityService.assertPermission(PERM_VIEW);
      requireScan(scanId);
      return findingsOf(scanId);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  @AuraEnabled
  public static FindingDTO updateFindingStatus(Id findingId, String status) {
    try {
      OI_SecurityService.assertPermission(PERM_MANAGE);
      if (String.isBlank(status) || !FINDING_STATUSES.contains(status)) {
        throw new OI_ValidationException(
          'status must be one of: ' + String.join(FINDING_STATUSES, ', ')
        );
      }
      OI_TD_Finding__c f = requireFinding(findingId);
      f.Status__c = status;
      update new OI_TD_Finding__c(Id = f.Id, Status__c = f.Status__c);
      return toDto(f);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  @AuraEnabled
  public static FindingDTO assignFinding(Id findingId, String assignedTo) {
    try {
      OI_SecurityService.assertPermission(PERM_MANAGE);
      OI_TD_Finding__c f = requireFinding(findingId);
      String trimmed = assignedTo == null ? null : assignedTo.trim();
      f.Assigned_To__c = String.isBlank(trimmed) ? null : trimmed.left(255);
      update new OI_TD_Finding__c(Id = f.Id, Assigned_To__c = f.Assigned_To__c);
      return toDto(f);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  @AuraEnabled
  public static FindingDTO explainFinding(Id findingId) {
    try {
      OI_SecurityService.assertPermission(PERM_MANAGE);
      OI_TD_Finding__c f = requireFinding(findingId);
      OI_TD_AiService.FindingExplanation ai = OI_TD_AiService.explainFinding(f);
      f.AI_Explanation__c = ai.explanation == null
        ? null
        : ai.explanation.left(32768);
      f.AI_Recommendation__c = ai.recommendation == null
        ? null
        : ai.recommendation.left(32768);
      update new OI_TD_Finding__c(
        Id = f.Id,
        AI_Explanation__c = f.AI_Explanation__c,
        AI_Recommendation__c = f.AI_Recommendation__c
      );
      return toDto(f);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  // =====================================================================
  // Components
  // =====================================================================

  /**
   * The scan's component inventory as one JSON document:
   * {summary, refs, objects, classes, triggers, flows, wf, lwc, vfp, vfc, email, pkgs}.
   * Fields are fetched per object with getObjectFields.
   */
  @AuraEnabled(cacheable=true)
  public static String getComponents(Id scanId) {
    try {
      OI_SecurityService.assertPermission(PERM_VIEW);
      OI_TD_Scan__c scan = requireScan(scanId);
      Map<String, String> byKind = new Map<String, String>();
      for (String k : COMPONENT_KINDS)
        byKind.put(k, null);
      Map<String, List<String>> parts = new Map<String, List<String>>();
      for (OI_TD_Scan_Data__c row : [
        SELECT Kind__c, Data__c
        FROM OI_TD_Scan_Data__c
        WHERE Scan__c = :scanId AND Kind__c IN :COMPONENT_KINDS
        ORDER BY Kind__c, Seq__c
      ]) {
        if (!parts.containsKey(row.Kind__c))
          parts.put(row.Kind__c, new List<String>());
        parts.get(row.Kind__c).add(row.Data__c == null ? '' : row.Data__c);
      }
      List<String> out = new List<String>();
      out.add('"available":' + (!parts.isEmpty()));
      out.add(
        '"summary":' +
        (String.isBlank(scan.Summary__c) ? '{}' : scan.Summary__c)
      );
      for (String k : COMPONENT_KINDS) {
        String payload = parts.containsKey(k)
          ? String.join(parts.get(k), '')
          : '';
        out.add('"' + k + '":' + (String.isBlank(payload) ? '[]' : payload));
      }
      return '{' + String.join(out, ',') + '}';
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** One object's fields with usage indices: [{a, t, u, r}] (u/r index the scan's refs). */
  @AuraEnabled(cacheable=true)
  public static String getObjectFields(
    Id scanId,
    Integer shardSeq,
    String objectName
  ) {
    try {
      OI_SecurityService.assertPermission(PERM_VIEW);
      OI_TD_Scan__c scan = requireScan(scanId);
      if (shardSeq == null || String.isBlank(objectName)) {
        throw new OI_ValidationException('An object is required.');
      }
      Boolean hasDep = hasDependencyData(scan);
      String shardJson = OI_TD_DataStore.read(scanId, 'fields:' + shardSeq);
      List<Object> rows = new List<Object>();
      if (String.isNotBlank(shardJson)) {
        Object raw = ((Map<String, Object>) JSON.deserializeUntyped(shardJson))
          .get(objectName);
        if (raw != null)
          rows = (List<Object>) raw;
      }
      Map<String, Object> byName = new Map<String, Object>();
      Map<String, Object> byDep = new Map<String, Object>();
      String usageJson = OI_TD_DataStore.read(scanId, 'fu:' + shardSeq);
      if (String.isNotBlank(usageJson)) {
        Map<String, Object> usage = (Map<String, Object>) JSON.deserializeUntyped(
          usageJson
        );
        if (usage.get('n') != null)
          byName = (Map<String, Object>) usage.get('n');
        if (usage.get('d') != null)
          byDep = (Map<String, Object>) usage.get('d');
      }
      List<Object> empty = new List<Object>();
      List<Object> out = new List<Object>();
      for (Object r : rows) {
        Map<String, Object> f = (Map<String, Object>) r;
        String api = (String) f.get('a');
        Object u = empty;
        Object refs = empty;
        if (hasDep && f.get('i') != null) {
          List<Object> pair = (List<Object>) byDep.get(objectName + '.' + api);
          if (pair != null) {
            u = pair[0];
            refs = pair[1];
          }
        } else if (byName.containsKey(api)) {
          u = byName.get(api);
        }
        out.add(
          new Map<String, Object>{
            'a' => api,
            't' => f.get('t'),
            'u' => u,
            'r' => refs
          }
        );
      }
      return JSON.serialize(out);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** Live profile / permission-set access to an object, or to one field when fieldName is set. */
  @AuraEnabled
  public static List<AccessGrant> getComponentAccess(
    String objectName,
    String fieldName
  ) {
    try {
      OI_SecurityService.assertPermission(PERM_VIEW);
      if (String.isBlank(objectName)) {
        throw new OI_ValidationException('An object is required.');
      }
      List<AccessGrant> profiles = new List<AccessGrant>();
      List<AccessGrant> permSets = new List<AccessGrant>();
      if (String.isBlank(fieldName)) {
        for (ObjectPermissions op : [
          SELECT
            Parent.IsOwnedByProfile,
            Parent.Profile.Name,
            Parent.Name,
            PermissionsRead,
            PermissionsEdit,
            PermissionsModifyAllRecords
          FROM ObjectPermissions
          WHERE SobjectType = :objectName AND Parent.PermissionSetGroupId = NULL
          ORDER BY Parent.Name
          LIMIT 2000
        ]) {
          String level = op.PermissionsModifyAllRecords
            ? 'Full Access'
            : op.PermissionsEdit
                ? 'Edit'
                : op.PermissionsRead ? 'Read Only' : null;
          if (level != null)
            addGrant(op.Parent, level, profiles, permSets);
        }
      } else {
        String key = objectName + '.' + fieldName;
        for (FieldPermissions fp : [
          SELECT
            Parent.IsOwnedByProfile,
            Parent.Profile.Name,
            Parent.Name,
            PermissionsRead,
            PermissionsEdit
          FROM FieldPermissions
          WHERE
            SobjectType = :objectName
            AND Field = :key
            AND Parent.PermissionSetGroupId = NULL
          ORDER BY Parent.Name
          LIMIT 2000
        ]) {
          if (fp.PermissionsEdit || fp.PermissionsRead) {
            addGrant(
              fp.Parent,
              fp.PermissionsEdit ? 'Edit' : 'Read Only',
              profiles,
              permSets
            );
          }
        }
      }
      profiles.addAll(permSets);
      return profiles;
    } catch (Exception e) {
      throw translate(e);
    }
  }

  private static void addGrant(
    PermissionSet parent,
    String level,
    List<AccessGrant> profiles,
    List<AccessGrant> permSets
  ) {
    if (parent.IsOwnedByProfile) {
      profiles.add(
        new AccessGrant(
          parent.Profile == null ? parent.Name : parent.Profile.Name,
          'Profile',
          level
        )
      );
    } else {
      permSets.add(new AccessGrant(parent.Name, 'PermissionSet', level));
    }
  }

  /** "Explain with AI" for a component (POST /scans/:id/explain-component) — reads live source. */
  @AuraEnabled
  public static String explainComponent(Id scanId, String type, String name) {
    try {
      OI_SecurityService.assertPermission(PERM_MANAGE);
      if (String.isBlank(type) || String.isBlank(name)) {
        throw new OI_ValidationException('type and name are required');
      }
      requireScan(scanId);
      String description = describeComponent(scanId, type, name);
      if (description == null) {
        throw new OI_ServiceException(
          'Component not found: ' + type + ' "' + name + '"'
        );
      }
      return OI_TD_AiService.explainComponent(type, name, description);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  @TestVisible
  private static String describeComponent(Id scanId, String type, String name) {
    String clipped;
    if (type == 'ApexClass') {
      List<ApexClass> rows = [
        SELECT Body
        FROM ApexClass
        WHERE Name = :name
        ORDER BY NamespacePrefix NULLS FIRST
        LIMIT 1
      ];
      return rows.isEmpty()
        ? null
        : 'Apex class source:\n' + OI_TD_AiService.clip(rows[0].Body);
    }
    if (type == 'ApexTrigger') {
      List<ApexTrigger> rows = [
        SELECT Body, TableEnumOrId
        FROM ApexTrigger
        WHERE Name = :name
        ORDER BY NamespacePrefix NULLS FIRST
        LIMIT 1
      ];
      if (rows.isEmpty())
        return null;
      Map<String, Object> rec = findRec(scanId, 'triggers', 'n', name);
      String objectName = rec != null &&
        rec.get('o') != null
        ? (String) rec.get('o')
        : rows[0].TableEnumOrId;
      return 'Apex trigger on object "' +
        objectName +
        '", source:\n' +
        OI_TD_AiService.clip(rows[0].Body);
    }
    if (type == 'Flow') {
      Map<String, Object> rec = findRec(scanId, 'flows', 'a', name);
      if (rec == null)
        return null;
      return 'Flow "' +
        rec.get('l') +
        '", status ' +
        rec.get('s') +
        ', trigger type ' +
        orDefault(rec.get('tt'), 'none') +
        ', object ' +
        orDefault(rec.get('o'), 'n/a') +
        '.';
    }
    if (type == 'LightningWebComponent') {
      if (findRec(scanId, 'lwc', 'a', name) == null)
        return null;
      return 'Lightning Web Component source:\n' +
        OI_TD_AiService.clip(lwcSource(name));
    }
    if (type == 'SfObject') {
      Map<String, Object> rec = findRec(scanId, 'objects', 'a', name);
      if (rec == null)
        return null;
      return 'Custom object "' +
        rec.get('l') +
        '" with ' +
        rec.get('c') +
        ' fields.';
    }
    if (type == 'SfField') {
      List<String> parts = name.split('\\.');
      if (parts.size() < 2)
        return null;
      Map<String, Object> field = findField(scanId, parts[0], parts[1]);
      if (field == null)
        return null;
      return 'Field "' +
        parts[1] +
        '" (type ' +
        field.get('t') +
        ') on object "' +
        parts[0] +
        '".';
    }
    if (type == 'WorkflowRule') {
      List<String> parts = name.split('\\.');
      for (Object raw : OI_TD_DataStore.readList(scanId, 'wf')) {
        Map<String, Object> w = (Map<String, Object>) raw;
        Boolean match = parts.size() >= 2
          ? (w.get('o') == parts[0] && w.get('n') == parts[1])
          : w.get('n') == name;
        if (match) {
          return 'Workflow rule "' +
            w.get('n') +
            '" on object "' +
            w.get('o') +
            '", ' +
            (w.get('ac') == true ? 'active' : 'inactive') +
            ', trigger type ' +
            orDefault(w.get('tt'), 'unknown') +
            '.';
        }
      }
      return null;
    }
    if (type == 'ApexPage') {
      List<ApexPage> rows = [
        SELECT Markup
        FROM ApexPage
        WHERE Name = :name
        ORDER BY NamespacePrefix NULLS FIRST
        LIMIT 1
      ];
      return rows.isEmpty()
        ? null
        : 'Visualforce page source:\n' + OI_TD_AiService.clip(rows[0].Markup);
    }
    if (type == 'ApexComponent') {
      List<ApexComponent> rows = [
        SELECT Markup
        FROM ApexComponent
        WHERE Name = :name
        ORDER BY NamespacePrefix NULLS FIRST
        LIMIT 1
      ];
      return rows.isEmpty()
        ? null
        : 'Visualforce component source:\n' +
          OI_TD_AiService.clip(rows[0].Markup);
    }
    if (type == 'EmailTemplate') {
      Map<String, Object> rec = findRec(scanId, 'email', 'n', name);
      if (rec == null)
        return null;
      return 'Email template "' +
        rec.get('n') +
        '" (developer name ' +
        rec.get('d') +
        '), type ' +
        rec.get('t') +
        ', ' +
        (rec.get('ac') == true ? 'active' : 'inactive') +
        '.';
    }
    return null;
  }

  private static String lwcSource(String bundleName) {
    OI_TD_ToolingClient tooling = toolingOverride != null
      ? toolingOverride
      : new OI_TD_ToolingClient();
    List<String> sources = new List<String>();
    for (
      Map<String, Object> r : tooling.queryAll(
        'SELECT FilePath, Source FROM LightningComponentResource WHERE LightningComponentBundle.DeveloperName = \'' +
          String.escapeSingleQuotes(bundleName) +
          '\' ORDER BY FilePath',
        2
      )
    ) {
      if (r.get('Source') != null)
        sources.add(String.valueOf(r.get('Source')));
      if (
        String.join(sources, '\n').length() > OI_TD_AiService.SOURCE_CHAR_LIMIT
      )
        break;
    }
    return String.join(sources, '\n');
  }

  /** Salesforce Setup deep link for a component, or null when it can't be resolved. */
  @AuraEnabled
  public static String getSetupLink(Id scanId, String type, String name) {
    try {
      OI_SecurityService.assertPermission(PERM_VIEW);
      if (String.isBlank(type) || String.isBlank(name)) {
        throw new OI_ValidationException('type and name are required');
      }
      requireScan(scanId);
      return buildSetupUrl(scanId, type, name);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  @TestVisible
  private static String buildSetupUrl(Id scanId, String type, String name) {
    String base = orgDomain();
    if (type == 'SfObject') {
      return base + '/lightning/setup/ObjectManager/' + name + '/Details/view';
    }
    if (type == 'SfField') {
      List<String> parts = name.split('\\.');
      if (
        parts.size() < 2 ||
        String.isBlank(parts[0]) ||
        String.isBlank(parts[1])
      )
        return null;
      return base +
        '/lightning/setup/ObjectManager/' +
        parts[0] +
        '/FieldsAndRelationships/' +
        parts[1] +
        '/view';
    }
    String id = componentId(scanId, type, name);
    if (id == null)
      return null;
    if (type == 'ApexClass')
      return base + '/lightning/setup/ApexClasses/page?address=%2F' + id;
    if (type == 'ApexTrigger')
      return base + '/lightning/setup/ApexTriggers/page?address=%2F' + id;
    if (type == 'Flow')
      return base +
        '/builder_platform_interaction/flowBuilder.app?flowId=' +
        id;
    if (type == 'LightningWebComponent')
      return base +
        '/lightning/setup/LightningComponentBundles/page?address=%2F' +
        id;
    if (type == 'Profile')
      return base + '/lightning/setup/EnhancedProfiles/page?address=%2F' + id;
    if (type == 'PermissionSet')
      return base + '/lightning/setup/PermSets/page?address=%2F' + id;
    if (type == 'WorkflowRule')
      return base + '/lightning/setup/WorkflowRules/page?address=%2F' + id;
    if (type == 'ApexPage')
      return base + '/lightning/setup/ApexPages/page?address=%2F' + id;
    if (type == 'ApexComponent')
      return base + '/lightning/setup/ApexComponent/page?address=%2F' + id;
    return null;
  }

  private static String componentId(Id scanId, String type, String name) {
    if (type == 'ApexClass') {
      List<ApexClass> rows = [
        SELECT Id
        FROM ApexClass
        WHERE Name = :name
        ORDER BY NamespacePrefix NULLS FIRST
        LIMIT 1
      ];
      return rows.isEmpty() ? null : rows[0].Id;
    }
    if (type == 'ApexTrigger') {
      List<ApexTrigger> rows = [
        SELECT Id
        FROM ApexTrigger
        WHERE Name = :name
        ORDER BY NamespacePrefix NULLS FIRST
        LIMIT 1
      ];
      return rows.isEmpty() ? null : rows[0].Id;
    }
    if (type == 'ApexPage') {
      List<ApexPage> rows = [
        SELECT Id
        FROM ApexPage
        WHERE Name = :name
        ORDER BY NamespacePrefix NULLS FIRST
        LIMIT 1
      ];
      return rows.isEmpty() ? null : rows[0].Id;
    }
    if (type == 'ApexComponent') {
      List<ApexComponent> rows = [
        SELECT Id
        FROM ApexComponent
        WHERE Name = :name
        ORDER BY NamespacePrefix NULLS FIRST
        LIMIT 1
      ];
      return rows.isEmpty() ? null : rows[0].Id;
    }
    if (type == 'Flow') {
      List<FlowDefinitionView> rows = [
        SELECT ActiveVersionId, LatestVersionId
        FROM FlowDefinitionView
        WHERE ApiName = :name
        LIMIT 1
      ];
      if (!rows.isEmpty()) {
        return rows[0].ActiveVersionId != null
          ? rows[0].ActiveVersionId
          : rows[0].LatestVersionId;
      }
      return stringOf(findRec(scanId, 'flows', 'a', name), 'i');
    }
    if (type == 'LightningWebComponent') {
      return stringOf(findRec(scanId, 'lwc', 'a', name), 'i');
    }
    if (type == 'Profile') {
      List<Profile> rows = [SELECT Id FROM Profile WHERE Name = :name LIMIT 1];
      return rows.isEmpty()
        ? stringOf(findHolder(scanId, 'Profile', name), 'i')
        : rows[0].Id;
    }
    if (type == 'PermissionSet') {
      List<PermissionSet> rows = [
        SELECT Id
        FROM PermissionSet
        WHERE (Name = :name OR Label = :name) AND IsOwnedByProfile = FALSE
        LIMIT 1
      ];
      return rows.isEmpty()
        ? stringOf(findHolder(scanId, 'PermissionSet', name), 'i')
        : rows[0].Id;
    }
    if (type == 'WorkflowRule') {
      List<String> parts = name.split('\\.');
      for (Object raw : OI_TD_DataStore.readList(scanId, 'wf')) {
        Map<String, Object> w = (Map<String, Object>) raw;
        Boolean match = parts.size() >= 2
          ? (w.get('o') == parts[0] && w.get('n') == parts[1])
          : w.get('n') == name;
        if (match)
          return (String) w.get('i');
      }
      return null;
    }
    return null;
  }

  // =====================================================================
  // Report export
  // =====================================================================

  /**
   * The PDF export as base64, rendered from the OI_TD_Report Visualforce page, so the tab can save
   * it as tech-debt-report.pdf (the reference app's download) instead of opening a new tab.
   * getContentAsPDF is not supported in tests, so tests get a placeholder body.
   */
  @AuraEnabled
  public static String getReportPdf(Id scanId) {
    try {
      OI_SecurityService.assertPermission(PERM_VIEW);
      requireScan(scanId);
      PageReference page = Page.OI_TD_Report;
      page.getParameters().put('scanId', scanId);
      Blob pdf = Test.isRunningTest()
        ? Blob.valueOf('%PDF-test')
        : page.getContentAsPDF();
      return EncodingUtil.base64Encode(pdf);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** Data for the Excel export (the PDF is rendered by the OI_TD_Report Visualforce page). */
  @AuraEnabled
  public static ReportDTO getReportData(Id scanId) {
    try {
      OI_SecurityService.assertPermission(PERM_VIEW);
      return buildReport(scanId);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  public static ReportDTO buildReport(Id scanId) {
    OI_TD_Scan__c scan = requireScan(scanId);
    HealthDTO h = health(scan);
    ReportDTO r = new ReportDTO();
    r.org = orgDomain();
    r.scanDate = scan.Started_At__c == null ? '' : scan.Started_At__c.format();
    r.overall = h.overall;
    r.totalFindings = h.totalFindings;
    for (String c : OI_TD_Rules.DEBT_CATEGORIES) {
      CategoryScore cs = new CategoryScore();
      cs.category = c.replace('_', ' ');
      cs.score = h.categoryScores.get(c);
      r.categoryScores.add(cs);
    }
    List<List<FindingDTO>> buckets = new List<List<FindingDTO>>();
    for (Integer i = 0; i <= 4; i++)
      buckets.add(new List<FindingDTO>());
    for (OI_TD_Finding__c f : [
      SELECT
        Id,
        Scan__c,
        Category__c,
        Rule_Key__c,
        Severity__c,
        Title__c,
        Detail__c,
        Component_Type__c,
        Component_Name__c,
        Status__c,
        Assigned_To__c,
        AI_Explanation__c,
        AI_Recommendation__c
      FROM OI_TD_Finding__c
      WHERE Scan__c = :scanId
      ORDER BY Category__c, Sort_Order__c
      LIMIT 20000
    ]) {
      Integer rank = SEVERITY_ORDER.get(f.Severity__c);
      buckets[rank == null ? 4 : rank].add(toDto(f));
    }
    for (List<FindingDTO> b : buckets)
      r.findings.addAll(b);
    return r;
  }

  // =====================================================================
  // Helpers
  // =====================================================================

  private static OI_TD_Scan__c requireScan(Id scanId) {
    if (scanId == null) {
      throw new OI_ValidationException('A scan is required.');
    }
    List<OI_TD_Scan__c> rows = [
      SELECT
        Id,
        Status__c,
        Started_At__c,
        Overall_Score__c,
        Category_Scores__c,
        Total_Findings__c,
        Summary__c
      FROM OI_TD_Scan__c
      WHERE Id = :scanId
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new OI_ServiceException('Scan not found');
    }
    return rows[0];
  }

  private static OI_TD_Finding__c requireFinding(Id findingId) {
    if (findingId == null) {
      throw new OI_ValidationException('A finding is required.');
    }
    List<OI_TD_Finding__c> rows = [
      SELECT
        Id,
        Scan__c,
        Category__c,
        Rule_Key__c,
        Severity__c,
        Title__c,
        Detail__c,
        Component_Type__c,
        Component_Name__c,
        Status__c,
        Assigned_To__c,
        AI_Explanation__c,
        AI_Recommendation__c
      FROM OI_TD_Finding__c
      WHERE Id = :findingId
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new OI_ServiceException('Not found');
    }
    return rows[0];
  }

  private static List<FindingDTO> findingsOf(Id scanId) {
    List<FindingDTO> out = new List<FindingDTO>();
    for (OI_TD_Finding__c f : [
      SELECT
        Id,
        Scan__c,
        Category__c,
        Rule_Key__c,
        Severity__c,
        Title__c,
        Detail__c,
        Component_Type__c,
        Component_Name__c,
        Status__c,
        Assigned_To__c,
        AI_Explanation__c,
        AI_Recommendation__c
      FROM OI_TD_Finding__c
      WHERE Scan__c = :scanId
      ORDER BY Sort_Order__c
      LIMIT 20000
    ]) {
      out.add(toDto(f));
    }
    return out;
  }

  /** Reads the sections that recorded an error from Section_Results__c (OI_TD_ScanState.SectionResult JSON); unreadable JSON yields none rather than failing the scan list. */
  @TestVisible
  private static List<SectionIssue> failedSections(String sectionResultsJson) {
    List<SectionIssue> out = new List<SectionIssue>();
    if (String.isBlank(sectionResultsJson)) {
      return out;
    }
    try {
      for (
        Object raw : (List<Object>) JSON.deserializeUntyped(sectionResultsJson)
      ) {
        Map<String, Object> section = (Map<String, Object>) raw;
        String error = (String) section.get('error');
        if (String.isNotBlank(error)) {
          SectionIssue issue = new SectionIssue();
          issue.category = (String) section.get('category');
          issue.error = error.left(500);
          out.add(issue);
        }
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'OI_TD_Controller: unreadable Section_Results__c — ' + e.getMessage()
      );
    }
    return out;
  }

  private static FindingDTO toDto(OI_TD_Finding__c f) {
    FindingDTO d = new FindingDTO();
    d.id = f.Id;
    d.scanId = f.Scan__c;
    d.category = f.Category__c;
    d.ruleKey = f.Rule_Key__c;
    d.severity = f.Severity__c;
    d.title = f.Title__c;
    d.detail = f.Detail__c;
    d.componentType = f.Component_Type__c;
    d.componentName = f.Component_Name__c;
    d.status = String.isBlank(f.Status__c) ? 'open' : f.Status__c;
    d.assignedTo = f.Assigned_To__c;
    d.aiExplanation = f.AI_Explanation__c;
    d.aiRecommendation = f.AI_Recommendation__c;
    return d;
  }

  private static String findingKey(FindingDTO f) {
    return f.category +
      '::' +
      f.ruleKey +
      '::' +
      f.componentType +
      '::' +
      f.componentName;
  }

  /** Stored score when present; otherwise computed from the scan's findings (as the reference does). */
  private static HealthDTO health(OI_TD_Scan__c scan) {
    HealthDTO h = new HealthDTO();
    if (
      scan.Overall_Score__c != null &&
      String.isNotBlank(scan.Category_Scores__c)
    ) {
      h.overall = scan.Overall_Score__c.intValue();
      h.totalFindings = scan.Total_Findings__c == null
        ? 0
        : scan.Total_Findings__c.intValue();
      h.categoryScores = new Map<String, Integer>();
      Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
        scan.Category_Scores__c
      );
      for (String c : OI_TD_Rules.DEBT_CATEGORIES) {
        h.categoryScores.put(
          c,
          raw.get(c) == null ? 100 : Integer.valueOf(raw.get(c))
        );
      }
      return h;
    }
    List<String> categories = new List<String>();
    List<String> severities = new List<String>();
    Id scanId = scan.Id;
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
    OI_TD_Rules.Health computed = OI_TD_Rules.computeHealth(
      categories,
      severities
    );
    h.overall = computed.overall;
    h.categoryScores = computed.categoryScores;
    h.totalFindings = computed.totalFindings;
    return h;
  }

  private static Boolean hasDependencyData(OI_TD_Scan__c scan) {
    if (String.isBlank(scan.Summary__c))
      return false;
    Map<String, Object> summary = (Map<String, Object>) JSON.deserializeUntyped(
      scan.Summary__c
    );
    return summary.get('hasDependencyData') == true;
  }

  private static Map<String, Object> findRec(
    Id scanId,
    String kind,
    String key,
    String value
  ) {
    for (Object raw : OI_TD_DataStore.readList(scanId, kind)) {
      Map<String, Object> rec = (Map<String, Object>) raw;
      if (rec.get(key) == value)
        return rec;
    }
    return null;
  }

  private static Map<String, Object> findHolder(
    Id scanId,
    String type,
    String name
  ) {
    for (Object raw : OI_TD_DataStore.readList(scanId, 'holders')) {
      Map<String, Object> rec = (Map<String, Object>) raw;
      if (rec.get('t') == type && rec.get('n') == name)
        return rec;
    }
    return null;
  }

  private static Map<String, Object> findField(
    Id scanId,
    String objectName,
    String fieldName
  ) {
    Map<String, Object> obj = findRec(scanId, 'objects', 'a', objectName);
    if (obj == null || obj.get('s') == null)
      return null;
    String shardJson = OI_TD_DataStore.read(scanId, 'fields:' + obj.get('s'));
    if (String.isBlank(shardJson))
      return null;
    Object rows = ((Map<String, Object>) JSON.deserializeUntyped(shardJson))
      .get(objectName);
    if (rows == null)
      return null;
    for (Object raw : (List<Object>) rows) {
      Map<String, Object> f = (Map<String, Object>) raw;
      if (f.get('a') == fieldName)
        return f;
    }
    return null;
  }

  private static String stringOf(Map<String, Object> rec, String key) {
    return rec == null ||
      rec.get(key) == null
      ? null
      : String.valueOf(rec.get(key));
  }

  private static String orDefault(Object value, String fallback) {
    return value == null || String.isBlank(String.valueOf(value))
      ? fallback
      : String.valueOf(value);
  }

  private static String orgDomain() {
    return URL.getOrgDomainUrl().toExternalForm();
  }

  /** Sanitized Controller-boundary translation — mirrors OI_OrgHealthController.translate. */
  private static AuraHandledException translate(Exception e) {
    String message;
    if (e instanceof OI_SecurityException) {
      message = 'You don\'t have permission to perform this Tech Debt action.';
    } else if (
      e instanceof OI_ValidationException ||
      e instanceof OI_ServiceException ||
      e instanceof OI_IntegrationException
    ) {
      message = e.getMessage();
    } else if (OI_StorageLimitUtil.isStorageLimitFailure(e)) {
      message = OI_StorageLimitUtil.STORAGE_FULL_MESSAGE;
    } else {
      message = 'Something went wrong in Tech Debt. Please try again.';
    }
    AuraHandledException handled = new AuraHandledException(message);
    handled.setMessage(message);
    return handled;
  }
}
