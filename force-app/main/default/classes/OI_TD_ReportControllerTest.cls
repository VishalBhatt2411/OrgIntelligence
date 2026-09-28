/**
 * Purpose: Verifies the OI_TD_Report (PDF) page controller: report loading, input validation
 *          and the permission gate.
 */
@isTest
private class OI_TD_ReportControllerTest {
  @testSetup
  static void setup() {
    OI_TD_TestSupport.grantAdmin();
    OI_TD_TestSupport.seedCompletedScan();
  }

  private static OI_TD_ReportController open(String scanId) {
    PageReference page = Page.OI_TD_Report;
    if (scanId != null) {
      page.getParameters().put('scanId', scanId);
    }
    Test.setCurrentPage(page);
    return new OI_TD_ReportController();
  }

  @isTest
  static void loadsReportForScan() {
    Id scanId = [SELECT Id FROM OI_TD_Scan__c LIMIT 1].Id;
    OI_TD_ReportController c = open(scanId);
    System.assert(c.hasReport, c.errorMessage);
    System.assertEquals(null, c.errorMessage);
    System.assertEquals(88, c.report.overall);
    System.assertEquals(2, c.report.findings.size());
    System.assert(
      ApexPages.currentPage()
        .getHeaders()
        .get('Content-Disposition')
        .contains('tech-debt-report.pdf')
    );
  }

  @isTest
  static void missingOrInvalidScanId() {
    OI_TD_ReportController missing = open(null);
    System.assert(!missing.hasReport);
    System.assertEquals('A scan is required.', missing.errorMessage);

    OI_TD_ReportController invalid = open('not-an-id');
    System.assertEquals('A scan is required.', invalid.errorMessage);
  }

  @isTest
  static void deniedWithoutPermission() {
    Id scanId = [SELECT Id FROM OI_TD_Scan__c LIMIT 1].Id;
    System.runAs(OI_TD_TestSupport.unprivilegedUser()) {
      OI_TD_ReportController c = open(scanId);
      System.assert(!c.hasReport);
      System.assertEquals(
        'You don\'t have permission to export Tech Debt reports.',
        c.errorMessage
      );
    }
  }
}
