/**
 * Purpose: Backs the OI_TD_Report Visualforce page, which renders the Tech Debt PDF report
 *          (the reference app's "Export report -> PDF").
 * Responsibilities: Gate on OI_View_Org_Health, load the report via OI_TD_Controller.buildReport
 *                    and mark the response as a tech-debt-report.pdf download.
 * Dependencies: OI_TD_Controller, OI_SecurityService.
 * Limitations: Visualforce PDF rendering (standard fonts only).
 */
public with sharing class OI_TD_ReportController {
  public OI_TD_Controller.ReportDTO report { get; private set; }
  public String errorMessage { get; private set; }

  public OI_TD_ReportController() {
    try {
      OI_SecurityService.assertPermission('OI_View_Org_Health');
      String scanId = ApexPages.currentPage().getParameters().get('scanId');
      Id parsed;
      try {
        parsed = String.isBlank(scanId) ? null : Id.valueOf(scanId);
      } catch (Exception e) {
        throw new OI_ValidationException('A scan is required.');
      }
      report = OI_TD_Controller.buildReport(parsed);
      ApexPages.currentPage()
        .getHeaders()
        .put(
          'Content-Disposition',
          'attachment; filename="tech-debt-report.pdf"'
        );
    } catch (OI_SecurityException e) {
      errorMessage = 'You don\'t have permission to export Tech Debt reports.';
    } catch (OI_ApplicationException e) {
      errorMessage = e.getMessage();
    }
  }

  public Boolean hasReport {
    get {
      return report != null;
    }
  }
}
