/**
 * Purpose: The Tech Debt rule set — code quality, automation, architecture, security, sharing,
 *          data quality and governor-limit analyzers plus the health score.
 * Responsibilities: Pure functions over in-memory component descriptions; every threshold,
 *                    title and detail string is the product's user-facing contract. No SOQL,
 *                    DML or callouts here — OI_TD_ScanEngine gathers the inputs.
 * Dependencies: None.
 * Limitations: Brace-depth loop detection and regex counting are heuristics (not an AST), by
 *              design — they flag likely problems, not proven ones.
 */
public with sharing class OI_TD_Rules {
  // ---- analyzer ordering (drives finding Sort_Order, mirrors analysis run order) ----
  public static final Integer A_CODE_QUALITY = 0;
  public static final Integer A_AUTOMATION = 1;
  public static final Integer A_ARCHITECTURE = 2;
  public static final Integer A_SECURITY = 3;
  public static final Integer A_SHARING = 4;
  public static final Integer A_DATA_QUALITY = 5;
  public static final Integer A_GOVERNOR = 6;

  public static final List<String> DEBT_CATEGORIES = new List<String>{
    'code_quality',
    'automation',
    'security',
    'architecture',
    'data_quality',
    'governor_limits'
  };
  public static final Map<String, Integer> SEVERITY_WEIGHT = new Map<String, Integer>{
    'low' => 1,
    'medium' => 2,
    'high' => 5,
    'critical' => 10
  };

  // ---- code quality ----
  private static final Pattern HARDCODED_ID_RE = Pattern.compile(
    '\'[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?\''
  );
  private static final Pattern DML_RE = Pattern.compile(
    '(?i)\\b(insert|update|delete|upsert|merge)\\s+[\\w\\[\\]]'
  );
  private static final Pattern SOQL_RE = Pattern.compile('(?i)\\[\\s*SELECT');
  private static final Pattern SOQL_COUNT_RE = Pattern.compile(
    '(?i)\\[\\s*SELECT\\b'
  );
  private static final Pattern LOOP_RE = Pattern.compile(
    '\\b(for|while)\\s*\\('
  );
  /** Apex string literals, // line comments and block comments, in one alternation so the leftmost construct wins (a // inside a string is not a comment). */
  private static final Pattern NON_CODE_RE = Pattern.compile(
    '\'[^\'\\\\\\n]*(?:\\\\.[^\'\\\\\\n]*)*\'|//[^\\n]*|/\\*[\\s\\S]*?\\*/'
  );
  /** The start of a SOQL for-loop header up to its opening bracket: for (Account a : [ */
  private static final Pattern SOQL_FOR_HEADER_RE = Pattern.compile(
    '\\bfor\\s*\\([^;{}()]*:\\s*\\['
  );
  /** Stands in for a SOQL for-loop iterable after maskSoqlForIterables; it contains no [ or SELECT, so SOQL_RE never matches it. */
  private static final String SOQL_FOR_MARKER = 'OI_TD_SOQL_FOR_ITERABLE';
  private static final Pattern COMPLEXITY_RE = Pattern.compile(
    '\\b(if|for|while|switch|case)\\s*[\\(:]'
  );
  private static final Pattern EMPTY_CATCH_RE = Pattern.compile(
    'catch\\s*\\([^)]*\\)\\s*\\{\\s*\\}'
  );
  private static final Pattern SHARING_KEYWORD_RE = Pattern.compile(
    '(?i)\\b(with|without|inherited)\\s+sharing\\b'
  );
  private static final Pattern ANY_SOQL_OR_DML_RE = Pattern.compile(
    '(?i)(\\[\\s*SELECT\\b|\\b(insert|update|delete|upsert|merge)\\s+[\\w\\[\\]])'
  );
  private static final Pattern DEBUG_RE = Pattern.compile(
    'System\\s*\\.\\s*debug\\s*\\('
  );
  private static final Pattern TODO_RE = Pattern.compile(
    '(?i)//\\s*(TODO|FIXME)\\b'
  );
  private static final Integer LARGE_CLASS_LINES = 500;
  private static final Integer HIGH_COMPLEXITY_KEYWORD_COUNT = 30;

  // ---- governor limits ----
  private static final Pattern CALLOUT_RE = Pattern.compile(
    '\\b(new\\s+HttpRequest|Http\\s*\\(\\s*\\)\\s*\\.\\s*send|WebServiceCallout\\s*\\.\\s*invoke)\\b'
  );
  private static final Pattern EMAIL_SEND_RE = Pattern.compile(
    '\\bMessaging\\s*\\.\\s*sendEmail\\b'
  );
  private static final Integer SOQL_PER_CLASS_THRESHOLD = 20;
  private static final Integer DML_PER_CLASS_THRESHOLD = 30;
  public static final Long ORG_APEX_CODE_LIMIT_CHARS = 6000000;
  private static final Decimal ORG_APEX_CODE_WARN_RATIO = 0.7;
  private static final Integer CLASS_CHAR_LIMIT = 1000000;
  private static final Decimal CLASS_CHAR_WARN_RATIO = 0.9;
  private static final Integer DEPLOYMENT_UNIT_LIMIT = 7500;
  private static final Decimal DEPLOYMENT_UNIT_WARN_RATIO = 0.5;

  // ---- classification ----
  private static final Pattern BATCH_APEX_RE = Pattern.compile(
    '(?i)\\bDatabase\\.Batchable\\b'
  );
  private static final Pattern TEST_APEX_RE = Pattern.compile('(?i)@istest\\b');
  private static final Pattern QUEUEABLE_APEX_RE = Pattern.compile(
    '(?i)\\bimplements\\s+[\\w\\s,.]*\\bQueueable\\b'
  );
  private static final Pattern FUTURE_APEX_RE = Pattern.compile(
    '(?i)@future\\b'
  );
  private static final Pattern TEST_CLASS_RE = Pattern.compile('(?i)@isTest');
  private static final Pattern ENTRY_POINT_RE = Pattern.compile(
    '(?i)\\b(implements|extends)\\s+[\\w\\s,<>.]*\\b(Batchable|Schedulable|Queueable|InboundEmailHandler)\\b'
  );

  // ---- thresholds (architecture / automation / security / sharing) ----
  private static final Integer LARGE_OBJECT_FIELD_COUNT = 200;
  private static final Integer HIGH_COUPLING_LOOKUP_COUNT = 15;
  private static final Integer GOD_COMPONENT_REFERENCER_THRESHOLD = 40;
  private static final Integer SPRAWL_THRESHOLD = 3;
  private static final Integer BROAD_FIELD_EDIT_THRESHOLD = 50;
  private static final Set<String> OPEN_INTERNAL_MODELS = new Set<String>{
    'ReadWrite',
    'Public Read/Write'
  };
  private static final Integer SHARING_RULE_SPRAWL_THRESHOLD = 10;
  private static final Integer ROLE_HIERARCHY_DEPTH_THRESHOLD = 7;

  /** One finding produced by an analyzer. */
  public class NewFinding {
    public String category;
    public String ruleKey;
    public String severity;
    public String title;
    public String detail;
    public String componentType;
    public String componentName;
    public NewFinding(
      String category,
      String ruleKey,
      String severity,
      String title,
      String detail,
      String componentType,
      String componentName
    ) {
      this.category = category;
      this.ruleKey = ruleKey;
      this.severity = severity;
      this.title = title;
      this.detail = detail;
      this.componentType = componentType;
      this.componentName = componentName;
    }
  }

  /** Per-body result: code-quality findings and governor-limit findings. */
  public class BodyResult {
    public List<NewFinding> codeQuality = new List<NewFinding>();
    public List<NewFinding> governor = new List<NewFinding>();
  }

  public class FlowInfo {
    public String apiName;
    public String label;
    public String status;
    public String triggerType;
    public String objectName;
  }

  public class TriggerInfo {
    public String name;
    public String objectName;
  }

  public class ObjectInfo {
    public String apiName;
    public Integer fieldCount;
  }

  public class DependencyInfo {
    public String componentId;
    public String refComponentId;
    public String refComponentName;
    public String refComponentType;
  }

  public class AccessHolder {
    public String name;
    public String type; // Profile | PermissionSet
    public List<String> riskyPerms = new List<String>();
    public List<String> writableObjects = new List<String>();
    public Integer editableFieldCount = 0;
  }

  public class OwdInfo {
    public String apiName;
    public String internalModel;
    public String externalModel;
  }

  public class RoleInfo {
    public String sfId;
    public String name;
    public String parentRoleId;
  }

  // =====================================================================
  // Apex body analysis (code quality + governor limits, single pass)
  // =====================================================================

  public static Integer lineCount(String body) {
    return body.countMatches('\n') + 1;
  }

  /**
   * Brace-depth loop detection for four targets in one pass. Loop depth tracking is independent
   * of the target, so this is equivalent to running findInLoop once per target.
   * Returns [soql, dml, callout, email].
   */
  public static List<Boolean> findInLoops(String body) {
    Boolean soql = false;
    Boolean dml = false;
    Boolean callout = false;
    Boolean email = false;
    Integer depth = 0;
    Integer loopDepth = null;
    for (String line : maskSoqlForIterables(body).split('\n')) {
      // A SOQL for-loop runs its query once, so its own iterable is only a query in a loop when an enclosing loop is already open.
      if (!soql && loopDepth != null && line.contains(SOQL_FOR_MARKER)) {
        soql = true;
      }
      if (
        (line.contains('for') || line.contains('while')) &&
        LOOP_RE.matcher(line).find()
      ) {
        if (loopDepth == null) {
          loopDepth = depth;
        }
      }
      if (loopDepth != null) {
        if (
          !soql &&
          line.containsIgnoreCase('select') &&
          SOQL_RE.matcher(line).find()
        ) {
          soql = true;
        }
        if (!dml && containsDmlKeyword(line) && DML_RE.matcher(line).find()) {
          dml = true;
        }
        if (
          !callout &&
          (line.contains('Http') || line.contains('WebServiceCallout')) &&
          CALLOUT_RE.matcher(line).find()
        ) {
          callout = true;
        }
        if (
          !email &&
          line.contains('sendEmail') &&
          EMAIL_SEND_RE.matcher(line).find()
        ) {
          email = true;
        }
        if (soql && dml && callout && email) {
          break;
        }
      }
      depth += line.countMatches('{') - line.countMatches('}');
      if (loopDepth != null && depth <= loopDepth) {
        loopDepth = null;
      }
    }
    return new List<Boolean>{ soql, dml, callout, email };
  }

  private static Boolean containsDmlKeyword(String line) {
    String lower = line.toLowerCase();
    return lower.contains('insert') ||
      lower.contains('update') ||
      lower.contains('delete') ||
      lower.contains('upsert') ||
      lower.contains('merge');
  }

  /**
   * Blanks string literals and comments, so rules that look for code (loops, SOQL, DML, empty catches) are not
   * triggered by text: a test fixture holding Apex source in a string, or commented-out code. Newlines inside a
   * masked block comment are kept so line-based rules see the same line structure. Falls back to the raw body if
   * the regex cannot run over it (a very large body), which keeps the previous unmasked behaviour.
   */
  public static String maskNonCode(String body) {
    if (String.isBlank(body)) {
      return body;
    }
    try {
      Matcher m = NON_CODE_RE.matcher(body);
      List<String> parts = new List<String>();
      Integer last = 0;
      while (m.find()) {
        parts.add(body.substring(last, m.start()));
        String token = m.group();
        if (token.startsWith('\'')) {
          parts.add('\'\'');
        } else if (token.startsWith('/*')) {
          parts.add('\n'.repeat(token.countMatches('\n')));
        }
        last = m.end();
      }
      parts.add(body.substring(last));
      return String.join(parts, '');
    } catch (Exception e) {
      return body;
    }
  }

  /** Replaces the bracketed iterable of each SOQL for-loop (for (X x : [SELECT ...])) with SOQL_FOR_MARKER, keeping its newlines. Expects strings and comments already masked, so bracket counting is reliable. */
  public static String maskSoqlForIterables(String code) {
    if (String.isBlank(code) || !code.containsIgnoreCase('select')) {
      return code;
    }
    try {
      Matcher m = SOQL_FOR_HEADER_RE.matcher(code);
      List<String> parts = new List<String>();
      Integer last = 0;
      while (m.find()) {
        Integer open = m.end() - 1;
        Integer close = matchingBracket(code, open);
        if (close < 0) {
          break;
        }
        parts.add(code.substring(last, open));
        parts.add(
          SOQL_FOR_MARKER +
          '\n'.repeat(code.substring(open, close + 1).countMatches('\n'))
        );
        last = close + 1;
      }
      parts.add(code.substring(last));
      return String.join(parts, '');
    } catch (Exception e) {
      return code;
    }
  }

  /** Index of the ] that closes the [ at openIndex, or -1 if it never closes. */
  private static Integer matchingBracket(String code, Integer openIndex) {
    Integer depth = 0;
    Integer i = openIndex;
    while (i < code.length()) {
      Integer nextOpen = code.indexOf('[', i);
      Integer nextClose = code.indexOf(']', i);
      if (nextClose < 0) {
        return -1;
      }
      if (nextOpen >= 0 && nextOpen < nextClose) {
        depth++;
        i = nextOpen + 1;
      } else {
        depth--;
        if (depth == 0) {
          return nextClose;
        }
        i = nextClose + 1;
      }
    }
    return -1;
  }

  /** Counts non-overlapping matches; falls back to per-line counting if the body is too large for one regex run. */
  public static Integer countMatches(Pattern p, String body) {
    try {
      Integer n = 0;
      Matcher m = p.matcher(body);
      while (m.find()) {
        n++;
      }
      return n;
    } catch (Exception e) {
      Integer n = 0;
      for (String line : body.split('\n')) {
        Matcher m = p.matcher(line);
        while (m.find()) {
          n++;
        }
      }
      return n;
    }
  }

  private static Boolean matches(Pattern p, String body) {
    try {
      return p.matcher(body).find();
    } catch (Exception e) {
      for (String line : body.split('\n')) {
        if (p.matcher(line).find()) {
          return true;
        }
      }
      return false;
    }
  }

  public static BodyResult analyzeBody(
    String componentType,
    String name,
    String body,
    Integer lines
  ) {
    BodyResult result = new BodyResult();
    List<NewFinding> f = result.codeQuality;
    // Loop and empty-catch checks read code only; the hardcoded-ID and TODO checks need the raw body's strings and comments.
    String code = maskNonCode(body);
    List<Boolean> inLoop = findInLoops(code);

    if (inLoop[0]) {
      f.add(
        new NewFinding(
          'code_quality',
          'soql_in_loop',
          'high',
          'SOQL query inside a loop in ' + name,
          'Querying inside a loop risks hitting governor limits as data volume grows.',
          componentType,
          name
        )
      );
    }
    if (inLoop[1]) {
      f.add(
        new NewFinding(
          'code_quality',
          'dml_in_loop',
          'high',
          'DML statement inside a loop in ' + name,
          'Performing DML inside a loop risks hitting governor limits; bulkify with collections instead.',
          componentType,
          name
        )
      );
    }
    Integer hardcoded = countMatches(HARDCODED_ID_RE, body);
    if (hardcoded > 0) {
      f.add(
        new NewFinding(
          'code_quality',
          'hardcoded_id',
          'medium',
          'Hardcoded Salesforce ID(s) in ' + name,
          'Found ' +
            hardcoded +
            ' literal ID(s), which break across sandboxes/orgs.',
          componentType,
          name
        )
      );
    }
    if (lines > LARGE_CLASS_LINES) {
      f.add(
        new NewFinding(
          'code_quality',
          'large_class',
          'medium',
          name + ' is a large class (' + lines + ' lines)',
          'Exceeds ' +
            LARGE_CLASS_LINES +
            ' lines, making it harder to test and maintain.',
          componentType,
          name
        )
      );
    }
    Integer complexity = countMatches(COMPLEXITY_RE, body);
    if (complexity > HIGH_COMPLEXITY_KEYWORD_COUNT) {
      f.add(
        new NewFinding(
          'code_quality',
          'high_complexity',
          'medium',
          name + ' has high branching complexity',
          complexity +
          ' branch/loop keywords found; consider splitting into smaller methods.',
          componentType,
          name
        )
      );
    }
    Integer emptyCatches = countMatches(EMPTY_CATCH_RE, code);
    if (emptyCatches > 0) {
      f.add(
        new NewFinding(
          'code_quality',
          'empty_catch_block',
          'high',
          name + ' has an empty catch block',
          'Found ' +
            emptyCatches +
            ' catch block(s) with no logging or rethrow; failures are silently swallowed instead of surfacing.',
          componentType,
          name
        )
      );
    }
    if (
      componentType == 'ApexClass' &&
      matches(ANY_SOQL_OR_DML_RE, body) &&
      !matches(SHARING_KEYWORD_RE, body)
    ) {
      f.add(
        new NewFinding(
          'code_quality',
          'missing_sharing_declaration',
          'medium',
          name + ' has no sharing declaration',
          'Reads or writes data without declaring with/without/inherited sharing, leaving its record-access posture implicit and easy to get wrong during review.',
          componentType,
          name
        )
      );
    }
    Integer debugs = countMatches(DEBUG_RE, body);
    if (debugs > 0) {
      f.add(
        new NewFinding(
          'code_quality',
          'debug_statement_left_in',
          'low',
          name + ' contains System.debug statements',
          debugs +
          ' System.debug call(s) found; these cost performance and should be removed or replaced with proper logging before production.',
          componentType,
          name
        )
      );
    }
    Integer todos = countMatches(TODO_RE, body);
    if (todos > 0) {
      f.add(
        new NewFinding(
          'code_quality',
          'todo_fixme_marker',
          'low',
          name + ' has unresolved TODO/FIXME comments',
          todos + ' marker(s) found — tracked technical debt left in the code.',
          componentType,
          name
        )
      );
    }

    // Governor limits (per body)
    List<NewFinding> g = result.governor;
    if (inLoop[2]) {
      g.add(
        new NewFinding(
          'governor_limits',
          'callout_in_loop',
          'high',
          'Callout inside a loop in ' + name,
          'A callout per loop iteration can quickly exceed the 100-callouts-per-transaction limit; bulkify with a single batched call instead.',
          componentType,
          name
        )
      );
    }
    if (inLoop[3]) {
      g.add(
        new NewFinding(
          'governor_limits',
          'email_in_loop',
          'medium',
          'Messaging.sendEmail inside a loop in ' + name,
          'Only 10 sendEmail calls are allowed per transaction; sending one per record in a loop will hit that limit on any batch of more than 10.',
          componentType,
          name
        )
      );
    }
    Integer soqlCount = countMatches(SOQL_COUNT_RE, body);
    if (soqlCount > SOQL_PER_CLASS_THRESHOLD) {
      g.add(
        new NewFinding(
          'governor_limits',
          'soql_heavy_class',
          'medium',
          name + ' issues ' + soqlCount + ' SOQL queries',
          'A transaction can issue at most 100 (sync) / 200 (async) SOQL queries total; a single class with this many statements leaves little headroom for anything else called in the same transaction.',
          componentType,
          name
        )
      );
    }
    Integer dmlCount = countMatches(DML_RE, body);
    if (dmlCount > DML_PER_CLASS_THRESHOLD) {
      g.add(
        new NewFinding(
          'governor_limits',
          'dml_heavy_class',
          'medium',
          name + ' issues ' + dmlCount + ' DML statements',
          'A transaction can issue at most 150 DML statements total; a single class with this many leaves little headroom for anything else called in the same transaction.',
          componentType,
          name
        )
      );
    }
    if (body.length() > CLASS_CHAR_LIMIT * CLASS_CHAR_WARN_RATIO) {
      g.add(
        new NewFinding(
          'governor_limits',
          'class_near_char_limit',
          'high',
          name + ' is approaching the per-class character limit',
          formatNumber(body.length()) +
            ' characters, against Salesforce\'s hard limit of ' +
            formatNumber(CLASS_CHAR_LIMIT) +
            ' per class/trigger.',
          componentType,
          name
        )
      );
    }
    return result;
  }

  public static List<NewFinding> checkTriggerNaming(
    String triggerName,
    String objectName
  ) {
    List<NewFinding> out = new List<NewFinding>();
    String obj = objectName == null ? '' : objectName;
    Pattern expected = Pattern.compile(
      '(?i)^' + Pattern.quote(obj) + '.*Trigger$'
    );
    if (expected.matcher(triggerName).find()) {
      return out;
    }
    out.add(
      new NewFinding(
        'code_quality',
        'trigger_naming_convention',
        'low',
        triggerName +
        ' doesn\'t follow the <ObjectName>Trigger naming convention',
        'Expected a name referencing "' +
          obj +
          '" and ending in "Trigger" (e.g. ' +
          obj +
          'Trigger) for discoverability.',
        'ApexTrigger',
        triggerName
      )
    );
    return out;
  }

  public static List<NewFinding> orgApexFindings(
    Long totalChars,
    Integer totalUnits
  ) {
    List<NewFinding> out = new List<NewFinding>();
    if (totalChars > ORG_APEX_CODE_LIMIT_CHARS * ORG_APEX_CODE_WARN_RATIO) {
      out.add(
        new NewFinding(
          'governor_limits',
          'org_apex_code_size',
          'medium',
          'Org\'s total Apex code size is approaching the platform limit',
          'Scanned classes + triggers total ' +
            formatNumber(totalChars) +
            ' characters, against Salesforce\'s org-wide limit of ' +
            formatNumber(ORG_APEX_CODE_LIMIT_CHARS) +
            ' (6 MB).',
          'Organization',
          'Apex Code'
        )
      );
    }
    if (totalUnits > DEPLOYMENT_UNIT_LIMIT * DEPLOYMENT_UNIT_WARN_RATIO) {
      out.add(
        new NewFinding(
          'governor_limits',
          'org_apex_unit_count',
          'low',
          'High number of Apex classes/triggers',
          totalUnits +
            ' class/trigger units scanned, against Salesforce\'s deployment limit of ' +
            DEPLOYMENT_UNIT_LIMIT +
            ' per deployment.',
          'Organization',
          'Apex Code'
        )
      );
    }
    return out;
  }

  // =====================================================================
  // Classification
  // =====================================================================

  public static String classifyApexClass(String body) {
    if (matches(TEST_APEX_RE, body))
      return 'Test Class';
    if (matches(BATCH_APEX_RE, body))
      return 'Batch Class';
    if (matches(QUEUEABLE_APEX_RE, body))
      return 'Queueable Class';
    if (matches(FUTURE_APEX_RE, body))
      return 'Future Class';
    return 'Apex Class';
  }

  public static Boolean isBatch(String body) {
    return matches(BATCH_APEX_RE, body);
  }

  public static Boolean isTestClass(String body) {
    return matches(TEST_CLASS_RE, body);
  }

  public static Boolean isEntryPoint(String body) {
    return matches(ENTRY_POINT_RE, body);
  }

  public static String classifyFlow(String triggerType, String processType) {
    if (processType == 'Workflow')
      return 'Process Builder';
    if (triggerType == 'PlatformEvent')
      return 'Platform Event-Triggered Flow';
    if (triggerType == 'Scheduled')
      return 'Scheduled-Triggered Flow';
    if (triggerType == 'RecordAfterSave' || triggerType == 'RecordBeforeSave')
      return 'Record-Triggered Flow';
    if (processType == 'Flow')
      return 'Screen Flow';
    return 'Autolaunched Flow';
  }

  // =====================================================================
  // Automation
  // =====================================================================

  public static List<NewFinding> analyzeAutomation(
    List<FlowInfo> flows,
    List<TriggerInfo> triggers
  ) {
    List<NewFinding> out = new List<NewFinding>();
    for (FlowInfo flow : flows) {
      if (flow.status != 'Active') {
        out.add(
          new NewFinding(
            'automation',
            'inactive_flow',
            'low',
            'Inactive flow: ' + flow.label,
            'Status is "' +
              flow.status +
              '". Inactive flows are safe to remove if no longer needed.',
            'Flow',
            flow.apiName
          )
        );
      }
    }

    List<String> groupKeys = new List<String>();
    Map<String, List<FlowInfo>> byObjectAndTrigger = new Map<String, List<FlowInfo>>();
    for (FlowInfo flow : flows) {
      if (String.isBlank(flow.objectName))
        continue;
      String key =
        flow.objectName +
        ':' +
        (String.isBlank(flow.triggerType) ? 'none' : flow.triggerType);
      if (!byObjectAndTrigger.containsKey(key)) {
        byObjectAndTrigger.put(key, new List<FlowInfo>());
        groupKeys.add(key);
      }
      byObjectAndTrigger.get(key).add(flow);
    }
    for (String key : groupKeys) {
      List<FlowInfo> grp = byObjectAndTrigger.get(key);
      if (grp.size() < 2)
        continue;
      String objectName = key.split(':')[0];
      List<String> labels = new List<String>();
      for (FlowInfo f : grp)
        labels.add(f.label);
      for (FlowInfo f : grp) {
        out.add(
          new NewFinding(
            'automation',
            'duplicate_flow',
            'medium',
            'Possible duplicate flow logic on ' + objectName,
            grp.size() +
              ' flows share the same object/trigger type: ' +
              String.join(labels, ', ') +
              '.',
            'Flow',
            f.apiName
          )
        );
      }
    }

    List<String> objectOrder = new List<String>();
    Map<String, Integer> counts = new Map<String, Integer>();
    for (FlowInfo flow : flows) {
      if (String.isBlank(flow.objectName))
        continue;
      increment(counts, objectOrder, flow.objectName);
    }
    for (TriggerInfo t : triggers) {
      increment(counts, objectOrder, t.objectName);
    }
    for (String objectName : objectOrder) {
      Integer count = counts.get(objectName);
      if (count > SPRAWL_THRESHOLD) {
        out.add(
          new NewFinding(
            'automation',
            'automation_sprawl',
            'medium',
            'Automation sprawl on ' + objectName,
            count +
            ' flows/triggers fire on this object, making execution order hard to reason about.',
            'SfObject',
            objectName
          )
        );
      }
    }
    return out;
  }

  private static void increment(
    Map<String, Integer> counts,
    List<String> order,
    String key
  ) {
    if (!counts.containsKey(key)) {
      counts.put(key, 0);
      order.add(key);
    }
    counts.put(key, counts.get(key) + 1);
  }

  // =====================================================================
  // Architecture
  // =====================================================================

  /**
   * outgoingByObject: object → ordered set of referenced objects (objects in describe order).
   */
  public static List<NewFinding> analyzeArchitecture(
    List<ObjectInfo> objects,
    List<TriggerInfo> triggers,
    List<FlowInfo> flows,
    List<String> outgoingOrder,
    Map<String, List<String>> outgoingByObject,
    List<DependencyInfo> dependencies
  ) {
    List<NewFinding> out = new List<NewFinding>();
    for (ObjectInfo o : objects) {
      if (o.fieldCount > LARGE_OBJECT_FIELD_COUNT) {
        out.add(
          new NewFinding(
            'architecture',
            'large_object',
            'low',
            o.apiName + ' has ' + o.fieldCount + ' fields',
            'Exceeds ' +
              LARGE_OBJECT_FIELD_COUNT +
              ' fields, which slows layout rendering and increases confusion.',
            'SfObject',
            o.apiName
          )
        );
      }
    }

    List<String> trigObjects = new List<String>();
    Map<String, List<String>> triggersByObject = new Map<String, List<String>>();
    for (TriggerInfo t : triggers) {
      if (!triggersByObject.containsKey(t.objectName)) {
        triggersByObject.put(t.objectName, new List<String>());
        trigObjects.add(t.objectName);
      }
      triggersByObject.get(t.objectName).add(t.name);
    }
    for (String objectName : trigObjects) {
      List<String> names = triggersByObject.get(objectName);
      if (names.size() > 1) {
        out.add(
          new NewFinding(
            'architecture',
            'multiple_triggers',
            'medium',
            objectName + ' has ' + names.size() + ' triggers',
            'Multiple triggers on one object (' +
              String.join(names, ', ') +
              ') make execution order implicit.',
            'SfObject',
            objectName
          )
        );
      }
    }

    Set<String> activeFlowObjects = new Set<String>();
    for (FlowInfo f : flows) {
      if (f.status == 'Active' && String.isNotBlank(f.objectName))
        activeFlowObjects.add(f.objectName);
    }
    for (String objectName : trigObjects) {
      if (activeFlowObjects.contains(objectName)) {
        out.add(
          new NewFinding(
            'architecture',
            'trigger_flow_conflict',
            'medium',
            objectName + ' has both a trigger and an active flow',
            'Both automations can fire on the same DML, risking order-dependent bugs or duplicate logic.',
            'SfObject',
            objectName
          )
        );
      }
    }

    for (String objectName : outgoingOrder) {
      List<String> refs = outgoingByObject.get(objectName);
      if (refs.size() > HIGH_COUPLING_LOOKUP_COUNT) {
        out.add(
          new NewFinding(
            'architecture',
            'high_coupling_object',
            'medium',
            objectName +
              ' has ' +
              refs.size() +
              ' outgoing lookup/master-detail relationships',
            'Exceeds ' +
              HIGH_COUPLING_LOOKUP_COUNT +
              ' relationship fields, coupling this object tightly to the rest of the data model and widening the blast radius of schema changes.',
            'SfObject',
            objectName
          )
        );
      }
    }

    Set<String> seenPairs = new Set<String>();
    for (String objectName : outgoingOrder) {
      for (String target : outgoingByObject.get(objectName)) {
        if (
          target == objectName ||
          seenPairs.contains(pairKey(target, objectName))
        )
          continue;
        List<String> back = outgoingByObject.get(target);
        if (back != null && new Set<String>(back).contains(objectName)) {
          seenPairs.add(pairKey(objectName, target));
          out.add(
            new NewFinding(
              'architecture',
              'circular_object_reference',
              'low',
              objectName + ' and ' + target + ' reference each other',
              'A circular lookup relationship between these objects complicates data loads, deletes, and sharing calculations.',
              'SfObject',
              objectName + ' / ' + target
            )
          );
        }
      }
    }

    out.addAll(godComponents(dependencies));
    return out;
  }

  private static String pairKey(String a, String b) {
    List<String> pair = new List<String>{ a, b };
    pair.sort();
    return pair[0] + '::' + pair[1];
  }

  public static List<NewFinding> godComponents(
    List<DependencyInfo> dependencies
  ) {
    List<NewFinding> out = new List<NewFinding>();
    List<String> order = new List<String>();
    Map<String, Set<String>> referencers = new Map<String, Set<String>>();
    Map<String, DependencyInfo> meta = new Map<String, DependencyInfo>();
    for (DependencyInfo d : dependencies) {
      if (!referencers.containsKey(d.refComponentId)) {
        referencers.put(d.refComponentId, new Set<String>());
        order.add(d.refComponentId);
      }
      referencers.get(d.refComponentId).add(d.componentId);
      meta.put(d.refComponentId, d);
    }
    for (String id : order) {
      DependencyInfo m = meta.get(id);
      NewFinding f = godComponent(
        m.refComponentName,
        m.refComponentType,
        referencers.get(id).size()
      );
      if (f != null) {
        out.add(f);
      }
    }
    return out;
  }

  /** The god_component finding for one referenced component, or null when under the threshold. */
  public static NewFinding godComponent(
    String refName,
    String refType,
    Integer referencerCount
  ) {
    if (referencerCount <= GOD_COMPONENT_REFERENCER_THRESHOLD) {
      return null;
    }
    return new NewFinding(
      'architecture',
      'god_component',
      'high',
      refName + ' is referenced by ' + referencerCount + ' other components',
      'Exceeds ' +
        GOD_COMPONENT_REFERENCER_THRESHOLD +
        ' distinct referencing components; a change here has a very large blast radius across the org.',
      refType,
      refName
    );
  }

  // =====================================================================
  // Security (profiles / permission sets)
  // =====================================================================

  public static Boolean isGuestLike(String name) {
    return name != null && name.containsIgnoreCase('guest');
  }

  public static List<NewFinding> analyzeSecurity(List<AccessHolder> holders) {
    List<NewFinding> out = new List<NewFinding>();
    List<AccessHolder> ordered = new List<AccessHolder>();
    for (AccessHolder h : holders)
      if (h.type == 'Profile')
        ordered.add(h);
    for (AccessHolder h : holders)
      if (h.type != 'Profile')
        ordered.add(h);
    for (AccessHolder h : ordered) {
      if (!h.riskyPerms.isEmpty()) {
        out.add(
          new NewFinding(
            'security',
            'over_permissioned',
            'high',
            h.name + ' grants broad org-wide permissions',
            'Grants: ' +
              String.join(h.riskyPerms, ', ') +
              '. Review whether this scope is actually needed.',
            h.type,
            h.name
          )
        );
      }
      if (isGuestLike(h.name) && !h.writableObjects.isEmpty()) {
        out.add(
          new NewFinding(
            'security',
            'guest_user_risk',
            'critical',
            'Guest profile "' +
              h.name +
              '" has write access to ' +
              h.writableObjects.size() +
              ' object(s)',
            'Guest users are unauthenticated; edit/delete access is a common breach vector: ' +
              String.join(h.writableObjects, ', ') +
              '.',
            h.type,
            h.name
          )
        );
      }
      if (h.editableFieldCount > BROAD_FIELD_EDIT_THRESHOLD) {
        out.add(
          new NewFinding(
            'security',
            'fls_broad_edit',
            'medium',
            h.name +
              ' grants edit access to ' +
              h.editableFieldCount +
              ' fields',
            'Broad field-level edit access increases risk of unintended data changes; consider narrowing scope.',
            h.type,
            h.name
          )
        );
      }
    }
    return out;
  }

  // =====================================================================
  // Sharing security
  // =====================================================================

  public static List<NewFinding> analyzeSharingSecurity(
    List<OwdInfo> owds,
    List<String> ruleObjectNames,
    List<RoleInfo> roles
  ) {
    List<NewFinding> out = new List<NewFinding>();
    for (OwdInfo o : owds) {
      if (OPEN_INTERNAL_MODELS.contains(o.internalModel)) {
        out.add(
          new NewFinding(
            'security',
            'owd_too_open',
            'high',
            o.apiName + ' org-wide default is ' + o.internalModel,
            'Every internal user can read and edit every record on this object by default; consider a more restrictive OWD plus explicit sharing rules.',
            'SfObject',
            o.apiName
          )
        );
      }
      if (
        String.isNotBlank(o.externalModel) &&
        OPEN_INTERNAL_MODELS.contains(o.externalModel)
      ) {
        out.add(
          new NewFinding(
            'security',
            'owd_external_too_open',
            'critical',
            o.apiName + ' external org-wide default is ' + o.externalModel,
            'Portal/community/guest users get broad access to every record on this object by default — a common data-exposure vector.',
            'SfObject',
            o.apiName
          )
        );
      }
    }

    List<String> order = new List<String>();
    Map<String, Integer> counts = new Map<String, Integer>();
    for (String objectName : ruleObjectNames)
      increment(counts, order, objectName);
    for (String objectName : order) {
      Integer n = counts.get(objectName);
      if (n > SHARING_RULE_SPRAWL_THRESHOLD) {
        out.add(
          new NewFinding(
            'security',
            'sharing_rule_sprawl',
            'medium',
            objectName + ' has ' + n + ' sharing rules',
            'Exceeds ' +
              SHARING_RULE_SPRAWL_THRESHOLD +
              ' sharing rules, making the effective access model hard to reason about and audit.',
            'SfObject',
            objectName
          )
        );
      }
    }

    Map<String, RoleInfo> byId = new Map<String, RoleInfo>();
    for (RoleInfo r : roles)
      byId.put(r.sfId, r);
    Map<String, Integer> depthCache = new Map<String, Integer>();
    RoleInfo deepest = null;
    Integer deepestDepth = -1;
    for (RoleInfo r : roles) {
      Integer depth = roleDepth(r.sfId, byId, depthCache, 0);
      if (depth > deepestDepth) {
        deepestDepth = depth;
        deepest = r;
      }
    }
    if (deepest != null && deepestDepth > ROLE_HIERARCHY_DEPTH_THRESHOLD) {
      out.add(
        new NewFinding(
          'security',
          'deep_role_hierarchy',
          'medium',
          'Role hierarchy is ' + (deepestDepth + 1) + ' levels deep',
          'Deepest branch reaches "' +
            deepest.name +
            '". Exceeds ' +
            ROLE_HIERARCHY_DEPTH_THRESHOLD +
            ' levels, which slows record roll-up visibility and complicates access reviews.',
          'UserRole',
          deepest.name
        )
      );
    }
    return out;
  }

  private static Integer roleDepth(
    String roleId,
    Map<String, RoleInfo> byId,
    Map<String, Integer> cache,
    Integer guard
  ) {
    if (cache.containsKey(roleId))
      return cache.get(roleId);
    RoleInfo role = byId.get(roleId);
    Integer depth = 0;
    if (
      role != null &&
      role.parentRoleId != null &&
      byId.containsKey(role.parentRoleId) &&
      guard < 500
    ) {
      depth = 1 + roleDepth(role.parentRoleId, byId, cache, guard + 1);
    }
    cache.put(roleId, depth);
    return depth;
  }

  // =====================================================================
  // Data quality
  // =====================================================================

  public static NewFinding unusedField(
    String objectApiName,
    String fieldApiName,
    Boolean verified
  ) {
    String obj = objectApiName == null ? 'unknown object' : objectApiName;
    return new NewFinding(
      'data_quality',
      'unused_field',
      'low',
      fieldApiName + ' appears unused',
      verified
        ? 'No metadata component references this field on ' +
          obj +
          ' (verified via Salesforce\'s dependency data).'
        : 'Not referenced in any scanned Apex class, trigger, or flow on ' +
          obj +
          '.',
      'SfField',
      (objectApiName == null ? 'unknown' : objectApiName) + '.' + fieldApiName
    );
  }

  public static List<NewFinding> duplicateFields(
    String objectApiName,
    List<String> fieldApiNames
  ) {
    List<NewFinding> out = new List<NewFinding>();
    Map<String, String> seen = new Map<String, String>();
    for (String field : fieldApiNames) {
      String key = field.removeEnd('__c').toLowerCase();
      String clash = seen.get(key);
      if (clash != null && clash != field) {
        out.add(
          new NewFinding(
            'data_quality',
            'duplicate_field',
            'low',
            'Possible duplicate fields on ' +
              objectApiName +
              ': ' +
              clash +
              ' / ' +
              field,
            'Similarly-named fields on the same object often indicate redundant data capture.',
            'SfField',
            objectApiName + '.' + field
          )
        );
      } else {
        seen.put(key, field);
      }
    }
    return out;
  }

  public static NewFinding unusedObject(String apiName, Boolean verified) {
    return new NewFinding(
      'data_quality',
      'unused_object',
      'low',
      apiName + ' appears unused',
      verified
        ? 'No metadata component references this object (verified via Salesforce\'s dependency data).'
        : 'Not referenced by name in any scanned Apex class, trigger, or flow.',
      'SfObject',
      apiName
    );
  }

  public static NewFinding unusedApexClass(String name) {
    return new NewFinding(
      'data_quality',
      'unused_apex_class',
      'low',
      name + ' appears unused',
      'No metadata component references this class (verified via Salesforce\'s dependency data).',
      'ApexClass',
      name
    );
  }

  public static NewFinding unusedLwc(String apiName) {
    return new NewFinding(
      'data_quality',
      'unused_lwc',
      'low',
      apiName + ' appears unused',
      'No metadata component references this Lightning Web Component (verified via Salesforce\'s dependency data).',
      'LightningWebComponent',
      apiName
    );
  }

  /** "Invoice__c" → "Invoice" (first occurrence only, like String.prototype.replace). */
  public static String objectNeedle(String apiName) {
    Integer idx = apiName.indexOf('__c');
    return idx < 0
      ? apiName
      : apiName.substring(0, idx) + apiName.substring(idx + 3);
  }

  // =====================================================================
  // Health score
  // =====================================================================

  public class Health {
    public Integer overall;
    public Map<String, Integer> categoryScores = new Map<String, Integer>();
    public Integer totalFindings;
  }

  /** severityByCategory: category → list of severities. */
  public static Health computeHealth(
    List<String> categories,
    List<String> severities
  ) {
    Health h = new Health();
    Map<String, Integer> deduction = new Map<String, Integer>();
    for (String c : DEBT_CATEGORIES)
      deduction.put(c, 0);
    for (Integer i = 0; i < categories.size(); i++) {
      String c = categories[i];
      if (deduction.containsKey(c)) {
        Integer w = SEVERITY_WEIGHT.get(severities[i]);
        deduction.put(c, deduction.get(c) + (w == null ? 0 : w));
      }
    }
    Integer sum = 0;
    for (String c : DEBT_CATEGORIES) {
      Integer score = Math.max(0, 100 - deduction.get(c));
      h.categoryScores.put(c, score);
      sum += score;
    }
    // Half-up, like JavaScript Math.round (Apex Math.round(Decimal) rounds half-even).
    h.overall = Decimal.valueOf(sum)
      .divide(DEBT_CATEGORIES.size(), 0, RoundingMode.HALF_UP)
      .intValue();
    h.totalFindings = categories.size();
    return h;
  }

  /** en-US thousands separators, like Number.prototype.toLocaleString(). */
  public static String formatNumber(Long n) {
    String digits = String.valueOf(Math.abs(n));
    String out = '';
    Integer count = 0;
    for (Integer i = digits.length() - 1; i >= 0; i--) {
      out = digits.substring(i, i + 1) + out;
      count++;
      if (count == 3 && i > 0) {
        out = ',' + out;
        count = 0;
      }
    }
    return (n < 0 ? '-' : '') + out;
  }
}
