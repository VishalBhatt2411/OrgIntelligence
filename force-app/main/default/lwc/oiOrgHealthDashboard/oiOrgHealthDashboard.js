/**
 * Purpose: Org Health's top-level container (ADR-0026, OrgHealthVisualDesignSpecification.md)
 *          — the single component the OI_Org_Health FlexiPage hosts.
 * Responsibilities: Load the landing-grid summary (OI_OrgHealthController.getOrgHealthSummary),
 *                    own which section is active, render the shared section nav, and switch
 *                    between the Overview landing grid and each section's own detail
 *                    container. Sections without a Phase container yet render an honest
 *                    "not yet available" message rather than a broken drill-down.
 * Dependencies: OI_OrgHealthController, oiHealthSectionNav, oiHealthOverviewGrid,
 *               oiHealthStorage, oiHealthMetadata, oiHealthAutomation, oiHealthCode,
 *               oiHealthSecurity, oiHealthData, oiHealthRemediation, oiStateBanner, oiSkeleton.
 * Limitations: All seven Phase 1-5 sections (Org Overview, Storage, Metadata Health,
 *              Automation Health, Code Health, Security Health, Data Health) now have a real
 *              detail container; the not-yet-available fallback stays in place for any future
 *              section a newer package version might introduce ahead of this component's own
 *              update, matching OI_OrgHealthSummaryService's own documented limitation.
 *              Remediation is appended to the nav client-side rather than read from
 *              summary.sections, because it is a cross-section workspace, not a scored Health
 *              domain — OI_OrgHealthSummaryService has nothing to say about it, and
 *              oiHealthSectionNav already renders a neutral dot for a null severityKey.
 */
import { LightningElement } from "lwc";
import getOrgHealthSummary from "@salesforce/apex/OI_OrgHealthController.getOrgHealthSummary";

const OVERVIEW_SECTION_KEY = "OrgOverview";
const REMEDIATION_SECTION_KEY = "Remediation";
const IMPLEMENTED_DETAIL_SECTION_KEYS = new Set([
  "Storage",
  "MetadataHealth",
  "AutomationHealth",
  "CodeHealth",
  "SecurityHealth",
  "DataHealth",
  "Remediation"
]);

export default class OiOrgHealthDashboard extends LightningElement {
  isLoading = true;
  loadError;
  summary;
  activeSectionKey = OVERVIEW_SECTION_KEY;

  connectedCallback() {
    this.loadSummary();
  }

  async loadSummary() {
    this.isLoading = true;
    this.loadError = undefined;
    try {
      this.summary = await getOrgHealthSummary();
    } catch (error) {
      this.loadError =
        (error && error.body && error.body.message) ||
        "Something went wrong loading Org Health.";
    } finally {
      this.isLoading = false;
    }
  }

  get hasError() {
    return !!this.loadError;
  }

  get hasSummary() {
    return !this.isLoading && !this.hasError && !!this.summary;
  }

  get overview() {
    return this.summary ? this.summary.overview : null;
  }

  get sections() {
    return this.summary ? this.summary.sections : [];
  }

  get navSections() {
    return [
      ...this.sections.map((section) => ({
        sectionKey: section.sectionKey,
        displayLabel: section.displayLabel,
        severityKey: section.severityKey
      })),
      {
        sectionKey: REMEDIATION_SECTION_KEY,
        displayLabel: "Remediation",
        severityKey: null
      }
    ];
  }

  get isOverviewActive() {
    return this.activeSectionKey === OVERVIEW_SECTION_KEY;
  }

  get isStorageActive() {
    return this.activeSectionKey === "Storage";
  }

  get isMetadataHealthActive() {
    return this.activeSectionKey === "MetadataHealth";
  }

  get isAutomationHealthActive() {
    return this.activeSectionKey === "AutomationHealth";
  }

  get isCodeHealthActive() {
    return this.activeSectionKey === "CodeHealth";
  }

  get isSecurityHealthActive() {
    return this.activeSectionKey === "SecurityHealth";
  }

  get isDataHealthActive() {
    return this.activeSectionKey === "DataHealth";
  }

  get isRemediationActive() {
    return this.activeSectionKey === REMEDIATION_SECTION_KEY;
  }

  get isUnimplementedSectionActive() {
    return (
      !this.isOverviewActive &&
      !IMPLEMENTED_DETAIL_SECTION_KEYS.has(this.activeSectionKey)
    );
  }

  get activeSectionLabel() {
    const match = this.sections.find(
      (section) => section.sectionKey === this.activeSectionKey
    );
    return match ? match.displayLabel : this.activeSectionKey;
  }

  get lastScannedLabel() {
    return this.overview && this.overview.lastScannedAt
      ? new Date(this.overview.lastScannedAt).toLocaleString()
      : "Not scanned yet";
  }

  handleSectionSelect(event) {
    this.activeSectionKey = event.detail.sectionKey;
  }

  handleBackToOverview() {
    this.activeSectionKey = OVERVIEW_SECTION_KEY;
  }

  handleRefresh() {
    this.loadSummary();
  }
}
