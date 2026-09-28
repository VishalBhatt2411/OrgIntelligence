/**
 * Purpose: Shared fixtures for the Tech Debt (OI_TD_*) test classes.
 * Responsibilities: In-memory fakes for OI_TD_ToolingClient and OI_MetadataApiAdapter (DI-based
 *                    fakes, per CodingStandards.md), permission helpers and seeded scan data.
 */
@isTest
public class OI_TD_TestSupport {
  /** Canned Tooling responses keyed by a substring of the SOQL; unknown queries return no rows. */
  public class FakeTooling extends OI_TD_ToolingClient {
    public Map<String, List<Map<String, Object>>> rowsByQuery = new Map<String, List<Map<String, Object>>>();
    public String describeBody = '{"sobjects":[]}';
    public String failOn;
    public List<String> queries = new List<String>();

    public override QueryPage queryPage(String soql) {
      queries.add(soql);
      if (failOn != null && soql.contains(failOn)) {
        throw new OI_ServiceException('Tooling unavailable');
      }
      QueryPage page = new QueryPage();
      for (String key : rowsByQuery.keySet()) {
        if (soql.contains(key)) {
          page.records.addAll(rowsByQuery.get(key));
          break;
        }
      }
      return page;
    }

    public override QueryPage nextPage(String nextRecordsUrl) {
      return new QueryPage();
    }

    public override String get(String path) {
      return describeBody;
    }
  }

  /** Canned Metadata API reads keyed by metadata type. */
  public class FakeMetadata extends OI_MetadataApiAdapter {
    public Map<String, Map<String, Map<String, Object>>> byType = new Map<String, Map<String, Map<String, Object>>>();

    public override List<Map<String, Object>> readMetadata(
      String metadataType,
      List<String> fullNames
    ) {
      List<Map<String, Object>> out = new List<Map<String, Object>>();
      Map<String, Map<String, Object>> defs = byType.get(metadataType);
      List<Object> records = new List<Object>();
      for (String name : fullNames) {
        Map<String, Object> d = defs == null ? null : defs.get(name);
        if (d != null) {
          Map<String, Object> copy = new Map<String, Object>(d);
          copy.put('fullName', name);
          records.add(copy);
        }
      }
      out.add(new Map<String, Object>{ 'records' => records });
      return out;
    }
  }

  public static Map<String, Object> row(List<Object> keyValues) {
    Map<String, Object> m = new Map<String, Object>();
    for (Integer i = 0; i + 1 < keyValues.size(); i += 2) {
      m.put((String) keyValues[i], keyValues[i + 1]);
    }
    return m;
  }

  /**
   * Points OI_TD_ScanEngine at in-memory Tooling / Metadata fakes with a small inventory of
   * every component kind, and caps real-org list queries so a full scan fits one transaction.
   */
  public static FakeTooling installEngineFakes() {
    FakeTooling tooling = new FakeTooling();
    tooling.describeBody =
      '{"sobjects":[' +
      '{"name":"OI_TD_Scan__c","layoutable":true,"custom":true},' +
      '{"name":"Account","layoutable":true,"custom":false},' +
      '{"name":"AccountHistory","layoutable":false,"custom":false},' +
      '{"name":"Not_Real_Object_XYZ__c","layoutable":false,"custom":true}]}';
    tooling.rowsByQuery.put(
      'FROM CustomObject',
      new List<Map<String, Object>>{
        row(
          new List<Object>{
            'Id',
            '01I000000000001AAA',
            'DeveloperName',
            'OI_TD_Scan'
          }
        )
      }
    );
    tooling.rowsByQuery.put(
      'FROM CustomField',
      new List<Map<String, Object>>{
        row(
          new List<Object>{
            'Id',
            '00N000000000001AAA',
            'DeveloperName',
            'Status',
            'TableEnumOrId',
            '01I000000000001AAA'
          }
        ),
        row(
          new List<Object>{
            'Id',
            '00N000000000002AAA',
            'DeveloperName',
            'Never_Used',
            'TableEnumOrId',
            'Account'
          }
        )
      }
    );
    tooling.rowsByQuery.put(
      'FROM WorkflowRule',
      new List<Map<String, Object>>{
        row(
          new List<Object>{
            'Id',
            '01Q000000000001AAA',
            'Name',
            'Notify',
            'TableEnumOrId',
            'Account'
          }
        )
      }
    );
    tooling.rowsByQuery.put(
      'LightningComponentBundle.DeveloperName FROM',
      new List<Map<String, Object>>{
        row(
          new List<Object>{
            'Id',
            '0Rd000000000001AAA',
            'LightningComponentBundleId',
            '0Rb000000000001AAA',
            'LightningComponentBundle',
            new Map<String, Object>{ 'DeveloperName' => 'invoiceCard' }
          }
        ),
        row(
          new List<Object>{
            'Id',
            '0Rd000000000002AAA',
            'LightningComponentBundle',
            null
          }
        )
      }
    );
    tooling.rowsByQuery.put(
      'Id, Source FROM LightningComponentResource',
      new List<Map<String, Object>>{
        row(
          new List<Object>{
            'Id',
            '0Rd000000000001AAA',
            'Source',
            'import { LightningElement } from "lwc"; // Account OI_TD_Scan__c'
          }
        )
      }
    );
    tooling.rowsByQuery.put(
      'InstalledSubscriberPackage',
      new List<Map<String, Object>>{
        row(
          new List<Object>{
            'SubscriberPackage',
            new Map<String, Object>{
              'Name' => 'Acme Tools',
              'NamespacePrefix' => 'acme'
            },
            'SubscriberPackageVersion',
            new Map<String, Object>{
              'Name' => 'Spring',
              'MajorVersion' => 1,
              'MinorVersion' => 4
            }
          }
        ),
        row(new List<Object>{ 'SubscriberPackage', null })
      }
    );
    tooling.rowsByQuery.put(
      'MetadataComponentDependency',
      new List<Map<String, Object>>{
        row(
          new List<Object>{
            'MetadataComponentId',
            '0Rb000000000001AAA',
            'MetadataComponentName',
            'invoiceCard',
            'MetadataComponentType',
            'LightningComponentBundle',
            'RefMetadataComponentId',
            '00N000000000001AAA',
            'RefMetadataComponentName',
            'Status__c',
            'RefMetadataComponentType',
            'CustomField'
          }
        )
      }
    );

    FakeMetadata metadata = new FakeMetadata();
    metadata.byType.put(
      'WorkflowRule',
      new Map<String, Map<String, Object>>{
        'Account.Notify' => new Map<String, Object>{
          'active' => 'true',
          'triggerType' => 'onCreateOnly'
        }
      }
    );
    metadata.byType.put(
      'SharingRules',
      new Map<String, Map<String, Object>>{
        'Account' => new Map<String, Object>{
          'sharingCriteriaRules' => new List<Object>{
            new Map<String, Object>{ 'fullName' => 'A' }
          },
          'sharingOwnerRules' => new Map<String, Object>{ 'fullName' => 'B' }
        }
      }
    );

    OI_TD_ScanEngine.toolingOverride = tooling;
    OI_TD_ScanEngine.metadataOverride = metadata;
    OI_TD_ScanEngine.maxListRows = 2;
    return tooling;
  }

  /** Gives the running user OI_Administrator (all four Tech Debt custom permissions). */
  public static void grantAdmin() {
    List<PermissionSet> ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'OI_Administrator'
      LIMIT 1
    ];
    if (ps.isEmpty()) {
      return;
    }
    Id userId = UserInfo.getUserId();
    if (
      ![
          SELECT Id
          FROM PermissionSetAssignment
          WHERE AssigneeId = :userId AND PermissionSetId = :ps[0].Id
          LIMIT 1
        ]
        .isEmpty()
    ) {
      return;
    }
    System.runAs(new User(Id = userId)) {
      insert new PermissionSetAssignment(
        AssigneeId = userId,
        PermissionSetId = ps[0].Id
      );
    }
  }

  public static User unprivilegedUser() {
    Profile standardProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    String suffix = String.valueOf(Crypto.getRandomInteger())
      .replace('-', '')
      .right(8);
    User u = new User(
      FirstName = 'OI Test',
      LastName = 'TD' + suffix,
      Email = 'oi.test.td' + suffix + '@example.invalid',
      Username = 'oi.test.td' + suffix + '@example.invalid',
      Alias = 'oitd' + suffix.left(4),
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = standardProfile.Id
    );
    insert u;
    return u;
  }

  public static OI_TD_Scan__c insertScan(
    String status,
    Datetime startedAt,
    Integer overall
  ) {
    OI_TD_Scan__c scan = new OI_TD_Scan__c(
      Status__c = status,
      Started_At__c = startedAt,
      Finished_At__c = status == OI_TD_ScanEngine.STATUS_RUNNING
        ? null
        : startedAt.addMinutes(2),
      Triggered_By__c = 'manual',
      Overall_Score__c = overall,
      Total_Findings__c = overall == null ? null : 2,
      Category_Scores__c = overall == null
        ? null
        : '{"security":' + overall + ',"code_quality":90}',
      Summary__c = '{"hasDependencyData":true,"objects":1}'
    );
    insert scan;
    return scan;
  }

  public static OI_TD_Finding__c finding(
    Id scanId,
    String ruleKey,
    String severity,
    String componentName,
    Integer sortOrder
  ) {
    return new OI_TD_Finding__c(
      Scan__c = scanId,
      Category__c = 'code_quality',
      Rule_Key__c = ruleKey,
      Severity__c = severity,
      Title__c = ruleKey + ' in ' + componentName,
      Detail__c = 'Detail for ' + ruleKey,
      Component_Type__c = 'ApexClass',
      Component_Name__c = componentName,
      Status__c = 'open',
      Sort_Order__c = sortOrder
    );
  }

  /** A completed scan with findings and a small stored component inventory. */
  public static OI_TD_Scan__c seedCompletedScan() {
    OI_TD_Scan__c scan = insertScan(
      OI_TD_ScanEngine.STATUS_COMPLETED,
      System.now().addHours(-1),
      88
    );
    insert new List<OI_TD_Finding__c>{
      finding(scan.Id, 'soql_in_loop', 'high', 'AccountService', 0),
      finding(scan.Id, 'debug_statement_left_in', 'low', 'Util', 1)
    };
    List<OI_TD_Scan_Data__c> data = new List<OI_TD_Scan_Data__c>();
    data.addAll(
      OI_TD_DataStore.chunks(
        scan.Id,
        'objects',
        '[{"a":"Invoice__c","l":"Invoice","c":2,"i":"01I000000000001","s":0}]'
      )
    );
    data.addAll(
      OI_TD_DataStore.chunks(
        scan.Id,
        'triggers',
        '[{"n":"InvoiceTrigger","o":"Invoice__c","i":"01q000000000001"}]'
      )
    );
    data.addAll(
      OI_TD_DataStore.chunks(
        scan.Id,
        'flows',
        '[{"a":"Invoice_Flow","l":"Invoice Flow","s":"Active","tt":"RecordAfterSave","o":"Invoice__c","i":"301000000000001"}]'
      )
    );
    data.addAll(
      OI_TD_DataStore.chunks(
        scan.Id,
        'lwc',
        '[{"a":"invoiceCard","i":"0Rb000000000001"}]'
      )
    );
    data.addAll(
      OI_TD_DataStore.chunks(
        scan.Id,
        'wf',
        '[{"n":"Notify","o":"Invoice__c","ac":true,"tt":"onCreateOnly","i":"01Q000000000001"}]'
      )
    );
    data.addAll(
      OI_TD_DataStore.chunks(
        scan.Id,
        'email',
        '[{"n":"Welcome","d":"Welcome_Email","t":"text","ac":true,"i":"00X000000000001"}]'
      )
    );
    data.addAll(
      OI_TD_DataStore.chunks(
        scan.Id,
        'holders',
        '[{"n":"Custom Profile","t":"Profile","i":"00e000000000001"},{"n":"Custom PS","t":"PermissionSet","i":"0PS000000000001"}]'
      )
    );
    data.addAll(
      OI_TD_DataStore.chunks(
        scan.Id,
        'refs',
        '[["ApexClass","AccountService"]]'
      )
    );
    data.addAll(
      OI_TD_DataStore.chunks(
        scan.Id,
        'fields:0',
        '{"Invoice__c":[{"a":"Amount__c","t":"currency","i":"00N000000000001"},{"a":"Name","t":"string"}]}'
      )
    );
    data.addAll(
      OI_TD_DataStore.chunks(
        scan.Id,
        'fu:0',
        '{"n":{"Name":[0]},"d":{"Invoice__c.Amount__c":[[0],[0]]}}'
      )
    );
    insert data;
    return scan;
  }
}
