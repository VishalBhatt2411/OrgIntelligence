/**
 * Purpose: Verifies OI_TD_Controller's permission-check -> data -> DTO contract for the Tech Debt
 *          tab, and that every entry point denies access with a sanitized AuraHandledException
 *          when the Tech Debt custom permissions are not assigned.
 */
@isTest
private class OI_TD_ControllerTest {
  private static final String DENIED = 'You don\'t have permission to perform this Tech Debt action.';

  private class AiMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setBody(
        '{"candidates":[{"content":{"role":"model","parts":[{"text":"EXPLANATION: It matters. RECOMMENDATION: Fix it."}]},"finishReason":"STOP"}]}'
      );
      return res;
    }
  }

  @testSetup
  static void setup() {
    OI_TD_TestSupport.grantAdmin();
    OI_TD_TestSupport.seedCompletedScan();
  }

  private static OI_TD_Scan__c scan() {
    return [
      SELECT Id, Started_At__c
      FROM OI_TD_Scan__c
      ORDER BY Started_At__c DESC
      LIMIT 1
    ];
  }

  private static OI_TD_Finding__c firstFinding() {
    return [SELECT Id FROM OI_TD_Finding__c ORDER BY Sort_Order__c LIMIT 1];
  }

  @isTest
  static void appShellMethods() {
    OI_TD_Controller.AppContext ctx = OI_TD_Controller.getAppContext();
    System.assert(ctx.canRunScan);
    System.assert(ctx.canManageFindings);
    System.assert(ctx.canManageSettings);

    System.assertEquals(
      'off',
      OI_TD_Controller.getSchedule().scheduleFrequency
    );
    OI_TD_ScanService.ScheduleInfo updated = OI_TD_Controller.updateSchedule(
      'weekly'
    );
    System.assertEquals('weekly', updated.scheduleFrequency);
    System.assertNotEquals(null, updated.nextScanAt);
  }

  @isTest
  static void scansHealthAndHistory() {
    Id scanId = scan().Id;
    List<OI_TD_Controller.ScanDTO> scans = OI_TD_Controller.getScans();
    System.assertEquals(1, scans.size());
    System.assertEquals(88, scans[0].overall);

    OI_TD_Controller.HealthDTO h = OI_TD_Controller.getHealth(scanId);
    System.assertEquals(88, h.overall);
    System.assertEquals(88, h.categoryScores.get('security'));
    System.assertEquals(100, h.categoryScores.get('automation'));

    List<OI_TD_Controller.HistoryPoint> history = OI_TD_Controller.getHealthHistory();
    System.assertEquals(1, history.size());
  }

  @isTest
  static void scansReportSectionsThatFailed() {
    OI_TD_Scan__c s = scan();
    s.Section_Results__c = JSON.serialize(
      new List<OI_TD_ScanState.SectionResult>{
        new OI_TD_ScanState.SectionResult('objects', 0, 'API unreachable'),
        new OI_TD_ScanState.SectionResult('apex_classes', 12, null),
        new OI_TD_ScanState.SectionResult('lwc', 0, 'API unreachable')
      }
    );
    update s;

    List<OI_TD_Controller.SectionIssue> failed = OI_TD_Controller.getScans()[0]
      .failedSections;
    System.assertEquals(
      2,
      failed.size(),
      'Only sections with an error are reported.'
    );
    System.assertEquals('objects', failed[0].category);
    System.assertEquals('API unreachable', failed[0].error);
    System.assertEquals('lwc', failed[1].category);
  }

  @isTest
  static void failedSectionsToleratesMissingAndUnreadableResults() {
    System.assertEquals(0, OI_TD_Controller.failedSections(null).size());
    System.assertEquals(0, OI_TD_Controller.failedSections('not json').size());
    System.assertEquals(
      0,
      OI_TD_Controller.failedSections(
          '[{"category":"flows","itemCount":3,"error":null}]'
        )
        .size()
    );
  }

  @isTest
  static void healthIsComputedWhenNotStored() {
    OI_TD_Scan__c s = OI_TD_TestSupport.insertScan(
      OI_TD_ScanEngine.STATUS_COMPLETED,
      System.now(),
      null
    );
    insert OI_TD_TestSupport.finding(s.Id, 'hardcoded_id', 'critical', 'X', 0);
    OI_TD_Controller.HealthDTO h = OI_TD_Controller.getHealth(s.Id);
    System.assertEquals(90, h.categoryScores.get('code_quality'));
    System.assertEquals(1, h.totalFindings);
  }

  @isTest
  static void diffComparesWithPreviousCompletedScan() {
    OI_TD_Scan__c latest = scan();
    OI_TD_Controller.DiffDTO none = OI_TD_Controller.getDiff(latest.Id);
    System.assertEquals(null, none.previousScanId);

    OI_TD_Scan__c older = OI_TD_TestSupport.insertScan(
      OI_TD_ScanEngine.STATUS_COMPLETED,
      latest.Started_At__c.addDays(-1),
      70
    );
    insert new List<OI_TD_Finding__c>{
      OI_TD_TestSupport.finding(
        older.Id,
        'soql_in_loop',
        'high',
        'AccountService',
        0
      ),
      OI_TD_TestSupport.finding(
        older.Id,
        'empty_catch_block',
        'high',
        'Legacy',
        1
      )
    };
    OI_TD_Controller.DiffDTO diff = OI_TD_Controller.getDiff(latest.Id);
    System.assertEquals(older.Id, diff.previousScanId);
    System.assertEquals(1, diff.newFindings.size());
    System.assertEquals('debug_statement_left_in', diff.newFindings[0].ruleKey);
    System.assertEquals(1, diff.resolvedFindings.size());
    System.assertEquals('empty_catch_block', diff.resolvedFindings[0].ruleKey);
  }

  @isTest
  static void findingWorkflow() {
    Id scanId = scan().Id;
    List<OI_TD_Controller.FindingDTO> findings = OI_TD_Controller.getFindings(
      scanId
    );
    System.assertEquals(2, findings.size());
    Id findingId = findings[0].id;

    System.assertEquals(
      'acknowledged',
      OI_TD_Controller.updateFindingStatus(findingId, 'acknowledged').status
    );
    System.assertEquals(
      'Priya',
      OI_TD_Controller.assignFinding(findingId, '  Priya ').assignedTo
    );
    System.assertEquals(
      null,
      OI_TD_Controller.assignFinding(findingId, '   ').assignedTo
    );

    try {
      OI_TD_Controller.updateFindingStatus(findingId, 'bogus');
      System.assert(false, 'expected a validation error');
    } catch (AuraHandledException e) {
      System.assert(
        e.getMessage().startsWith('status must be one of'),
        e.getMessage()
      );
    }
    try {
      OI_TD_Controller.updateFindingStatus(null, 'open');
      System.assert(false, 'expected a validation error');
    } catch (AuraHandledException e) {
      System.assertEquals('A finding is required.', e.getMessage());
    }
    try {
      OI_TD_Controller.getFindings(null);
      System.assert(false, 'expected a validation error');
    } catch (AuraHandledException e) {
      System.assertEquals('A scan is required.', e.getMessage());
    }
  }

  @isTest
  static void explainFindingStoresAiText() {
    Id findingId = firstFinding().Id;
    Test.setMock(HttpCalloutMock.class, new AiMock());
    Test.startTest();
    OI_TD_Controller.FindingDTO d = OI_TD_Controller.explainFinding(findingId);
    Test.stopTest();
    System.assertEquals('It matters.', d.aiExplanation);
    System.assertEquals('Fix it.', d.aiRecommendation);
  }

  @isTest
  static void explainComponentDescribesStoredComponents() {
    Id scanId = scan().Id;
    Test.setMock(HttpCalloutMock.class, new AiMock());
    Test.startTest();
    String text = OI_TD_Controller.explainComponent(
      scanId,
      'SfObject',
      'Invoice__c'
    );
    Test.stopTest();
    System.assert(text.contains('EXPLANATION'), text);
  }

  @isTest
  static void explainComponentValidation() {
    Id scanId = scan().Id;
    try {
      OI_TD_Controller.explainComponent(scanId, '', 'x');
      System.assert(false, 'expected a validation error');
    } catch (AuraHandledException e) {
      System.assertEquals('type and name are required', e.getMessage());
    }
    try {
      OI_TD_Controller.explainComponent(scanId, 'SfObject', 'Missing__c');
      System.assert(false, 'expected not found');
    } catch (AuraHandledException e) {
      System.assert(
        e.getMessage().startsWith('Component not found'),
        e.getMessage()
      );
    }
  }

  @isTest
  static void describeComponentCoversEveryType() {
    Id scanId = scan().Id;
    OI_TD_TestSupport.FakeTooling tooling = new OI_TD_TestSupport.FakeTooling();
    tooling.rowsByQuery.put(
      'LightningComponentResource',
      new List<Map<String, Object>>{
        OI_TD_TestSupport.row(
          new List<Object>{
            'FilePath',
            'lwc/invoiceCard/invoiceCard.js',
            'Source',
            'export default class {}'
          }
        )
      }
    );
    OI_TD_Controller.toolingOverride = tooling;

    System.assert(
      OI_TD_Controller.describeComponent(scanId, 'SfObject', 'Invoice__c')
        .contains('2 fields')
    );
    System.assert(
      OI_TD_Controller.describeComponent(
          scanId,
          'SfField',
          'Invoice__c.Amount__c'
        )
        .contains('currency')
    );
    System.assertEquals(
      null,
      OI_TD_Controller.describeComponent(scanId, 'SfField', 'Invoice__c')
    );
    System.assertEquals(
      null,
      OI_TD_Controller.describeComponent(
        scanId,
        'SfField',
        'Invoice__c.Nope__c'
      )
    );
    System.assert(
      OI_TD_Controller.describeComponent(scanId, 'Flow', 'Invoice_Flow')
        .contains('RecordAfterSave')
    );
    System.assertEquals(
      null,
      OI_TD_Controller.describeComponent(scanId, 'Flow', 'Nope')
    );
    System.assert(
      OI_TD_Controller.describeComponent(
          scanId,
          'LightningWebComponent',
          'invoiceCard'
        )
        .contains('export default')
    );
    System.assertEquals(
      null,
      OI_TD_Controller.describeComponent(
        scanId,
        'LightningWebComponent',
        'nope'
      )
    );
    System.assert(
      OI_TD_Controller.describeComponent(
          scanId,
          'WorkflowRule',
          'Invoice__c.Notify'
        )
        .contains('active')
    );
    System.assert(
      OI_TD_Controller.describeComponent(scanId, 'WorkflowRule', 'Notify')
        .contains('Notify')
    );
    System.assertEquals(
      null,
      OI_TD_Controller.describeComponent(scanId, 'WorkflowRule', 'Other')
    );
    System.assert(
      OI_TD_Controller.describeComponent(scanId, 'EmailTemplate', 'Welcome')
        .contains('Welcome_Email')
    );
    System.assertEquals(
      null,
      OI_TD_Controller.describeComponent(scanId, 'EmailTemplate', 'Nope')
    );
    System.assert(
      OI_TD_Controller.describeComponent(
          scanId,
          'ApexClass',
          'OI_TD_Controller'
        )
        .startsWith('Apex class source')
    );
    System.assertEquals(
      null,
      OI_TD_Controller.describeComponent(
        scanId,
        'ApexClass',
        'No_Such_Class_XYZ'
      )
    );
    System.assertEquals(
      null,
      OI_TD_Controller.describeComponent(
        scanId,
        'ApexTrigger',
        'No_Such_Trigger_XYZ'
      )
    );
    System.assertEquals(
      null,
      OI_TD_Controller.describeComponent(scanId, 'ApexPage', 'No_Such_Page_XYZ')
    );
    System.assertNotEquals(
      null,
      OI_TD_Controller.describeComponent(scanId, 'ApexPage', 'OI_TD_Report')
    );
    System.assertEquals(
      null,
      OI_TD_Controller.describeComponent(
        scanId,
        'ApexComponent',
        'No_Such_Cmp_XYZ'
      )
    );
    System.assertEquals(
      null,
      OI_TD_Controller.describeComponent(scanId, 'Unknown', 'x')
    );
  }

  @isTest
  static void setupLinks() {
    Id scanId = scan().Id;
    System.assert(
      OI_TD_Controller.getSetupLink(scanId, 'SfObject', 'Invoice__c')
        .contains('/ObjectManager/Invoice__c/Details/view')
    );
    System.assert(
      OI_TD_Controller.getSetupLink(scanId, 'SfField', 'Invoice__c.Amount__c')
        .contains('/FieldsAndRelationships/Amount__c/view')
    );
    System.assertEquals(
      null,
      OI_TD_Controller.getSetupLink(scanId, 'SfField', 'Invoice__c')
    );
    System.assert(
      OI_TD_Controller.getSetupLink(scanId, 'ApexClass', 'OI_TD_Controller')
        .contains('/ApexClasses/page')
    );
    System.assertEquals(
      null,
      OI_TD_Controller.getSetupLink(scanId, 'ApexClass', 'No_Such_Class_XYZ')
    );
    System.assertEquals(
      null,
      OI_TD_Controller.getSetupLink(
        scanId,
        'ApexTrigger',
        'No_Such_Trigger_XYZ'
      )
    );
    System.assert(
      OI_TD_Controller.getSetupLink(scanId, 'ApexPage', 'OI_TD_Report')
        .contains('/ApexPages/page')
    );
    System.assertEquals(
      null,
      OI_TD_Controller.getSetupLink(scanId, 'ApexComponent', 'No_Such_Cmp_XYZ')
    );
    System.assert(
      OI_TD_Controller.getSetupLink(scanId, 'Flow', 'Invoice_Flow')
        .contains('flowId=301000000000001')
    );
    System.assert(
      OI_TD_Controller.getSetupLink(
          scanId,
          'LightningWebComponent',
          'invoiceCard'
        )
        .contains('0Rb000000000001')
    );
    System.assert(
      OI_TD_Controller.getSetupLink(scanId, 'Profile', 'Custom Profile')
        .contains('00e000000000001')
    );
    System.assert(
      OI_TD_Controller.getSetupLink(scanId, 'PermissionSet', 'OI_Administrator')
        .contains('/PermSets/page')
    );
    System.assert(
      OI_TD_Controller.getSetupLink(scanId, 'PermissionSet', 'Custom PS')
        .contains('0PS000000000001')
    );
    System.assert(
      OI_TD_Controller.getSetupLink(scanId, 'WorkflowRule', 'Invoice__c.Notify')
        .contains('01Q000000000001')
    );
    System.assertEquals(
      null,
      OI_TD_Controller.getSetupLink(scanId, 'WorkflowRule', 'Other')
    );
    System.assertEquals(
      null,
      OI_TD_Controller.getSetupLink(scanId, 'Unknown', 'x')
    );
    try {
      OI_TD_Controller.getSetupLink(scanId, null, 'x');
      System.assert(false, 'expected a validation error');
    } catch (AuraHandledException e) {
      System.assertEquals('type and name are required', e.getMessage());
    }
  }

  @isTest
  static void componentsAndFields() {
    Id scanId = scan().Id;
    Map<String, Object> doc = (Map<String, Object>) JSON.deserializeUntyped(
      OI_TD_Controller.getComponents(scanId)
    );
    System.assertEquals(true, doc.get('available'));
    System.assertEquals(1, ((List<Object>) doc.get('objects')).size());
    System.assertEquals(0, ((List<Object>) doc.get('classes')).size());

    List<Object> fields = (List<Object>) JSON.deserializeUntyped(
      OI_TD_Controller.getObjectFields(scanId, 0, 'Invoice__c')
    );
    System.assertEquals(2, fields.size());
    Map<String, Object> amount = (Map<String, Object>) fields[0];
    System.assertEquals('Amount__c', amount.get('a'));
    System.assertEquals(1, ((List<Object>) amount.get('u')).size());
    System.assertEquals(
      '[]',
      OI_TD_Controller.getObjectFields(scanId, 5, 'Invoice__c')
    );
    try {
      OI_TD_Controller.getObjectFields(scanId, null, 'Invoice__c');
      System.assert(false, 'expected a validation error');
    } catch (AuraHandledException e) {
      System.assertEquals('An object is required.', e.getMessage());
    }
  }

  @isTest
  static void componentAccessForObjectAndField() {
    List<OI_TD_Controller.AccessGrant> objectGrants = OI_TD_Controller.getComponentAccess(
      'Account',
      null
    );
    System.assertNotEquals(null, objectGrants);
    List<OI_TD_Controller.AccessGrant> fieldGrants = OI_TD_Controller.getComponentAccess(
      'Account',
      'Industry'
    );
    System.assertNotEquals(null, fieldGrants);
    try {
      OI_TD_Controller.getComponentAccess('', null);
      System.assert(false, 'expected a validation error');
    } catch (AuraHandledException e) {
      System.assertEquals('An object is required.', e.getMessage());
    }
  }

  @isTest
  static void reportPdfIsReturnedAsBase64() {
    String pdf = OI_TD_Controller.getReportPdf(scan().Id);
    System.assertEquals('%PDF-test', EncodingUtil.base64Decode(pdf).toString());
  }

  @isTest
  static void reportDataOrdersFindingsBySeverity() {
    OI_TD_Controller.ReportDTO r = OI_TD_Controller.getReportData(scan().Id);
    System.assertEquals(88, r.overall);
    System.assertEquals(
      OI_TD_Rules.DEBT_CATEGORIES.size(),
      r.categoryScores.size()
    );
    System.assertEquals('high', r.findings[0].severity);
    System.assertEquals('low', r.findings[1].severity);
  }

  @isTest
  static void startScanLaunchesBatch() {
    OI_TD_TestSupport.installEngineFakes();
    Test.startTest();
    Id scanId = OI_TD_Controller.startScan();
    Test.stopTest();
    OI_TD_Scan__c s = [
      SELECT Triggered_By__c
      FROM OI_TD_Scan__c
      WHERE Id = :scanId
    ];
    System.assertEquals('manual', s.Triggered_By__c);
  }

  @isTest
  static void missingScanIsReported() {
    Id scanId = scan().Id;
    delete [SELECT Id FROM OI_TD_Scan__c WHERE Id = :scanId];
    try {
      OI_TD_Controller.getHealth(scanId);
      System.assert(false, 'expected not found');
    } catch (AuraHandledException e) {
      System.assertEquals('Scan not found', e.getMessage());
    }
  }

  @isTest
  static void everyEntryPointDeniesUnprivilegedUsers() {
    Id scanId = scan().Id;
    Id findingId = firstFinding().Id;
    User u = OI_TD_TestSupport.unprivilegedUser();
    Integer deniedCount = 0;
    System.runAs(u) {
      List<String> calls = new List<String>{
        'getAppContext',
        'getSchedule',
        'updateSchedule',
        'getScans',
        'startScan',
        'getHealth',
        'getHealthHistory',
        'getDiff',
        'getFindings',
        'updateFindingStatus',
        'assignFinding',
        'explainFinding',
        'getComponents',
        'getObjectFields',
        'getComponentAccess',
        'explainComponent',
        'getSetupLink',
        'getReportData',
        'getReportPdf'
      };
      for (String call : calls) {
        try {
          invoke(call, scanId, findingId);
        } catch (AuraHandledException e) {
          System.assertEquals(DENIED, e.getMessage(), call);
          deniedCount++;
        }
      }
      System.assertEquals(calls.size(), deniedCount);
    }
  }

  private static void invoke(String call, Id scanId, Id findingId) {
    if (call == 'getAppContext')
      OI_TD_Controller.getAppContext();
    else if (call == 'getSchedule')
      OI_TD_Controller.getSchedule();
    else if (call == 'updateSchedule')
      OI_TD_Controller.updateSchedule('daily');
    else if (call == 'getScans')
      OI_TD_Controller.getScans();
    else if (call == 'startScan')
      OI_TD_Controller.startScan();
    else if (call == 'getHealth')
      OI_TD_Controller.getHealth(scanId);
    else if (call == 'getHealthHistory')
      OI_TD_Controller.getHealthHistory();
    else if (call == 'getDiff')
      OI_TD_Controller.getDiff(scanId);
    else if (call == 'getFindings')
      OI_TD_Controller.getFindings(scanId);
    else if (call == 'updateFindingStatus')
      OI_TD_Controller.updateFindingStatus(findingId, 'open');
    else if (call == 'assignFinding')
      OI_TD_Controller.assignFinding(findingId, 'x');
    else if (call == 'explainFinding')
      OI_TD_Controller.explainFinding(findingId);
    else if (call == 'getComponents')
      OI_TD_Controller.getComponents(scanId);
    else if (call == 'getObjectFields')
      OI_TD_Controller.getObjectFields(scanId, 0, 'Invoice__c');
    else if (call == 'getComponentAccess')
      OI_TD_Controller.getComponentAccess('Account', null);
    else if (call == 'explainComponent')
      OI_TD_Controller.explainComponent(scanId, 'SfObject', 'Invoice__c');
    else if (call == 'getSetupLink')
      OI_TD_Controller.getSetupLink(scanId, 'SfObject', 'Invoice__c');
    else if (call == 'getReportData')
      OI_TD_Controller.getReportData(scanId);
    else if (call == 'getReportPdf')
      OI_TD_Controller.getReportPdf(scanId);
  }
}
