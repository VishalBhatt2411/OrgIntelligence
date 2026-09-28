/**
 * Purpose: Unit tests for OI_TD_Rules — the pure analyzers ported from the reference app's rule engine.
 */
@isTest
private class OI_TD_RulesTest {
  private static Set<String> ruleKeys(List<OI_TD_Rules.NewFinding> findings) {
    Set<String> keys = new Set<String>();
    for (OI_TD_Rules.NewFinding f : findings)
      keys.add(f.ruleKey);
    return keys;
  }

  @isTest
  static void analyzeBodyFlagsCodeQualityAndGovernorIssues() {
    String body =
      'public class Bad {\n' +
      '  // TODO fix this\n' +
      '  void run(List<Account> accts) {\n' +
      '    for (Account a : accts) {\n' +
      '      List<Contact> c = [SELECT Id FROM Contact WHERE AccountId = \'001000000000001\'];\n' +
      '      update a;\n' +
      '      HttpRequest r = new HttpRequest();\n' +
      '      Messaging.sendEmail(new List<Messaging.SingleEmailMessage>());\n' +
      '    }\n' +
      '    try { insert accts; } catch (Exception e) {}\n' +
      '    System.debug(\'x\');\n' +
      '  }\n' +
      '}';
    OI_TD_Rules.BodyResult r = OI_TD_Rules.analyzeBody(
      'ApexClass',
      'Bad',
      body,
      600
    );
    Set<String> cq = ruleKeys(r.codeQuality);
    System.assert(cq.contains('soql_in_loop'), cq);
    System.assert(cq.contains('dml_in_loop'), cq);
    System.assert(cq.contains('hardcoded_id'), cq);
    System.assert(cq.contains('large_class'), cq);
    System.assert(cq.contains('empty_catch_block'), cq);
    System.assert(cq.contains('missing_sharing_declaration'), cq);
    System.assert(cq.contains('debug_statement_left_in'), cq);
    System.assert(cq.contains('todo_fixme_marker'), cq);
    Set<String> gov = ruleKeys(r.governor);
    System.assert(gov.contains('callout_in_loop'), gov);
    System.assert(gov.contains('email_in_loop'), gov);
  }

  @isTest
  static void analyzeBodyCleanClassHasNoFindings() {
    String body = 'public with sharing class Good {\n  public Integer add(Integer a, Integer b) { return a + b; }\n}';
    OI_TD_Rules.BodyResult r = OI_TD_Rules.analyzeBody(
      'ApexClass',
      'Good',
      body,
      OI_TD_Rules.lineCount(body)
    );
    System.assertEquals(0, r.codeQuality.size());
    System.assertEquals(0, r.governor.size());
    System.assertEquals(3, OI_TD_Rules.lineCount(body));
  }

  @isTest
  static void analyzeBodyHeavyClassAndComplexity() {
    String body = 'public with sharing class Heavy {\n';
    for (Integer i = 0; i < 35; i++) {
      body +=
        '  void m' +
        i +
        '() { if (true) { List<Account> a = [SELECT Id FROM Account]; insert a; } }\n';
    }
    body += '}';
    Set<String> keys = new Set<String>();
    OI_TD_Rules.BodyResult r = OI_TD_Rules.analyzeBody(
      'ApexClass',
      'Heavy',
      body,
      40
    );
    keys.addAll(ruleKeys(r.codeQuality));
    keys.addAll(ruleKeys(r.governor));
    System.assert(keys.contains('high_complexity'), keys);
    System.assert(keys.contains('soql_heavy_class'), keys);
    System.assert(keys.contains('dml_heavy_class'), keys);
  }

  @isTest
  static void triggerNamingAndOrgApex() {
    System.assertEquals(
      0,
      OI_TD_Rules.checkTriggerNaming('AccountTrigger', 'Account').size()
    );
    System.assertEquals(
      1,
      OI_TD_Rules.checkTriggerNaming('DoStuff', 'Account').size()
    );
    System.assertEquals(
      1,
      OI_TD_Rules.checkTriggerNaming('DoStuff', null).size()
    );
    System.assertEquals(2, OI_TD_Rules.orgApexFindings(5000000L, 4000).size());
    System.assertEquals(0, OI_TD_Rules.orgApexFindings(10L, 1).size());
  }

  @isTest
  static void classification() {
    System.assertEquals(
      'Test Class',
      OI_TD_Rules.classifyApexClass('@isTest private class X {}')
    );
    System.assertEquals(
      'Batch Class',
      OI_TD_Rules.classifyApexClass(
        'class X implements Database.Batchable<SObject> {}'
      )
    );
    System.assertEquals(
      'Queueable Class',
      OI_TD_Rules.classifyApexClass('class X implements Queueable {}')
    );
    System.assertEquals(
      'Future Class',
      OI_TD_Rules.classifyApexClass('class X { @future static void f() {} }')
    );
    System.assertEquals(
      'Apex Class',
      OI_TD_Rules.classifyApexClass('class X {}')
    );
    System.assert(
      OI_TD_Rules.isBatch('implements Database.Batchable<Integer>')
    );
    System.assert(OI_TD_Rules.isTestClass('@IsTest class T {}'));
    System.assert(
      OI_TD_Rules.isEntryPoint('global class S implements Schedulable {}')
    );
    System.assert(!OI_TD_Rules.isEntryPoint('public class P {}'));

    System.assertEquals(
      'Process Builder',
      OI_TD_Rules.classifyFlow(null, 'Workflow')
    );
    System.assertEquals(
      'Platform Event-Triggered Flow',
      OI_TD_Rules.classifyFlow('PlatformEvent', 'AutoLaunchedFlow')
    );
    System.assertEquals(
      'Scheduled-Triggered Flow',
      OI_TD_Rules.classifyFlow('Scheduled', 'AutoLaunchedFlow')
    );
    System.assertEquals(
      'Record-Triggered Flow',
      OI_TD_Rules.classifyFlow('RecordAfterSave', 'AutoLaunchedFlow')
    );
    System.assertEquals('Screen Flow', OI_TD_Rules.classifyFlow(null, 'Flow'));
    System.assertEquals(
      'Autolaunched Flow',
      OI_TD_Rules.classifyFlow(null, 'AutoLaunchedFlow')
    );
  }

  private static OI_TD_Rules.FlowInfo flow(
    String api,
    String status,
    String trig,
    String obj
  ) {
    OI_TD_Rules.FlowInfo f = new OI_TD_Rules.FlowInfo();
    f.apiName = api;
    f.label = api;
    f.status = status;
    f.triggerType = trig;
    f.objectName = obj;
    return f;
  }

  private static OI_TD_Rules.TriggerInfo trig(String name, String obj) {
    OI_TD_Rules.TriggerInfo t = new OI_TD_Rules.TriggerInfo();
    t.name = name;
    t.objectName = obj;
    return t;
  }

  @isTest
  static void automationAndArchitecture() {
    List<OI_TD_Rules.FlowInfo> flows = new List<OI_TD_Rules.FlowInfo>{
      flow('F1', 'Active', 'RecordAfterSave', 'Account'),
      flow('F2', 'Active', 'RecordAfterSave', 'Account'),
      flow('F3', 'Draft', null, null)
    };
    List<OI_TD_Rules.TriggerInfo> triggers = new List<OI_TD_Rules.TriggerInfo>{
      trig('AccountTrigger', 'Account'),
      trig('AccountTrigger2', 'Account')
    };
    Set<String> auto = ruleKeys(OI_TD_Rules.analyzeAutomation(flows, triggers));
    System.assert(auto.contains('inactive_flow'), auto);
    System.assert(auto.contains('duplicate_flow'), auto);
    System.assert(auto.contains('automation_sprawl'), auto);

    OI_TD_Rules.ObjectInfo big = new OI_TD_Rules.ObjectInfo();
    big.apiName = 'Big__c';
    big.fieldCount = 250;
    List<String> many = new List<String>();
    for (Integer i = 0; i < 16; i++)
      many.add('T' + i + '__c');
    many.add('Big__c');
    Map<String, List<String>> outgoing = new Map<String, List<String>>{
      'Account' => many,
      'Big__c' => new List<String>{ 'Account' }
    };
    List<OI_TD_Rules.DependencyInfo> deps = new List<OI_TD_Rules.DependencyInfo>();
    for (Integer i = 0; i < 45; i++) {
      OI_TD_Rules.DependencyInfo d = new OI_TD_Rules.DependencyInfo();
      d.componentId = 'c' + i;
      d.refComponentId = 'ref1';
      d.refComponentName = 'Util';
      d.refComponentType = 'ApexClass';
      deps.add(d);
    }
    Set<String> arch = ruleKeys(
      OI_TD_Rules.analyzeArchitecture(
        new List<OI_TD_Rules.ObjectInfo>{ big },
        triggers,
        flows,
        new List<String>{ 'Account', 'Big__c' },
        outgoing,
        deps
      )
    );
    System.assert(arch.contains('large_object'), arch);
    System.assert(arch.contains('multiple_triggers'), arch);
    System.assert(arch.contains('trigger_flow_conflict'), arch);
    System.assert(arch.contains('high_coupling_object'), arch);
    System.assert(arch.contains('circular_object_reference'), arch);
    System.assert(arch.contains('god_component'), arch);
    System.assertEquals(null, OI_TD_Rules.godComponent('X', 'ApexClass', 3));
  }

  @isTest
  static void securityAndSharing() {
    OI_TD_Rules.AccessHolder guest = new OI_TD_Rules.AccessHolder();
    guest.name = 'Site Guest User';
    guest.type = 'Profile';
    guest.riskyPerms.add('ModifyAllData');
    guest.writableObjects.add('Account');
    guest.editableFieldCount = 60;
    OI_TD_Rules.AccessHolder ps = new OI_TD_Rules.AccessHolder();
    ps.name = 'Ok PS';
    ps.type = 'PermissionSet';
    Set<String> sec = ruleKeys(
      OI_TD_Rules.analyzeSecurity(
        new List<OI_TD_Rules.AccessHolder>{ ps, guest }
      )
    );
    System.assert(sec.contains('over_permissioned'), sec);
    System.assert(sec.contains('guest_user_risk'), sec);
    System.assert(sec.contains('fls_broad_edit'), sec);
    System.assert(OI_TD_Rules.isGuestLike('Guest'));
    System.assert(!OI_TD_Rules.isGuestLike(null));

    OI_TD_Rules.OwdInfo owd = new OI_TD_Rules.OwdInfo();
    owd.apiName = 'Account';
    owd.internalModel = 'ReadWrite';
    owd.externalModel = 'ReadWrite';
    List<String> rules = new List<String>();
    for (Integer i = 0; i < 11; i++)
      rules.add('Account');
    List<OI_TD_Rules.RoleInfo> roles = new List<OI_TD_Rules.RoleInfo>();
    for (Integer i = 0; i < 10; i++) {
      OI_TD_Rules.RoleInfo r = new OI_TD_Rules.RoleInfo();
      r.sfId = 'r' + i;
      r.name = 'Role ' + i;
      r.parentRoleId = i == 0 ? null : 'r' + (i - 1);
      roles.add(r);
    }
    Set<String> sh = ruleKeys(
      OI_TD_Rules.analyzeSharingSecurity(
        new List<OI_TD_Rules.OwdInfo>{ owd },
        rules,
        roles
      )
    );
    System.assert(sh.contains('owd_too_open'), sh);
    System.assert(sh.contains('owd_external_too_open'), sh);
    System.assert(sh.contains('sharing_rule_sprawl'), sh);
    System.assert(sh.contains('deep_role_hierarchy'), sh);
  }

  @isTest
  static void dataQualityHelpers() {
    System.assertEquals(
      'Account.Foo__c',
      OI_TD_Rules.unusedField('Account', 'Foo__c', true).componentName
    );
    System.assertEquals(
      'unknown.Foo__c',
      OI_TD_Rules.unusedField(null, 'Foo__c', false).componentName
    );
    System.assertEquals(
      1,
      OI_TD_Rules.duplicateFields(
          'Account',
          new List<String>{ 'Region', 'Region__c', 'Other__c' }
        )
        .size()
    );
    System.assertEquals(
      'unused_object',
      OI_TD_Rules.unusedObject('X__c', false).ruleKey
    );
    System.assertEquals(
      'unused_object',
      OI_TD_Rules.unusedObject('X__c', true).ruleKey
    );
    System.assertEquals(
      'unused_apex_class',
      OI_TD_Rules.unusedApexClass('Util').ruleKey
    );
    System.assertEquals('unused_lwc', OI_TD_Rules.unusedLwc('myCmp').ruleKey);
    System.assertEquals('Invoice', OI_TD_Rules.objectNeedle('Invoice__c'));
    System.assertEquals('Account', OI_TD_Rules.objectNeedle('Account'));
  }

  @isTest
  static void healthAndFormatting() {
    OI_TD_Rules.Health h = OI_TD_Rules.computeHealth(
      new List<String>{ 'security', 'security', 'unknown' },
      new List<String>{ 'critical', 'high', 'low' }
    );
    System.assertEquals(85, h.categoryScores.get('security'));
    System.assertEquals(100, h.categoryScores.get('code_quality'));
    System.assertEquals(3, h.totalFindings);
    System.assertEquals(98, h.overall);
    System.assertEquals('1,234,567', OI_TD_Rules.formatNumber(1234567L));
    System.assertEquals('-1,000', OI_TD_Rules.formatNumber(-1000L));
    System.assertEquals('12', OI_TD_Rules.formatNumber(12L));
    System.assertEquals(
      2,
      OI_TD_Rules.countMatches(Pattern.compile('a'), 'banana'.left(4))
    );
  }
}
