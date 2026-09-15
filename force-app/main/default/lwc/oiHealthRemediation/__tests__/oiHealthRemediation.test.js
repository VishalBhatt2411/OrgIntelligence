import { createElement } from "lwc";
import OiHealthRemediation from "c/oiHealthRemediation";
import getRemediationQueue from "@salesforce/apex/OI_OrgHealthController.getRemediationQueue";
import getRemediationSummary from "@salesforce/apex/OI_OrgHealthController.getRemediationSummary";
import exportRemediationQueue from "@salesforce/apex/OI_OrgHealthController.exportRemediationQueue";

jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getRemediationQueue",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getRemediationSummary",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.exportRemediationQueue",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.updateFindingStatus",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getRelatedFindings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getFindingComponentNavigation",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getFindingHistory",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/OI_Manage_Finding_Workflow",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock("c/metadataNavigation", () => ({ navigateToTarget: jest.fn() }));

function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

const SUMMARY = {
  totalOpenFindings: 42,
  countBySeverity: [
    { label: "Critical", value: "5" },
    { label: "Warning", value: "20" }
  ],
  countByStatus: [{ label: "Open", value: "30" }],
  countBySection: [{ label: "Security Health", value: "12" }],
  expiringRiskAcceptanceCount: 3,
  overdueCount: 7
};

const FINDING_A = {
  id: "001aFindingA",
  sectionKey: "SecurityHealth",
  title: "A profile grants Modify All Data broadly",
  severityKey: "Critical",
  componentKey: "profileA",
  componentLabel: "System Administrator",
  status: "Open",
  dueDate: "2026-09-15",
  lastDetected: "2026-08-31T10:00:00.000Z",
  firstDetected: "2026-08-01T10:00:00.000Z",
  score: 91.2,
  ownerName: "Jordan Admin"
};

const FINDING_B = {
  id: "001aFindingB",
  sectionKey: "MetadataHealth",
  title: "Ctl_Finding_Object__c has an unusually high field count",
  severityKey: "Warning",
  componentKey: "ctlFind1",
  componentLabel: "Ctl_Finding_Object__c",
  status: "Acknowledged",
  dueDate: null,
  lastDetected: "2026-08-30T10:00:00.000Z",
  firstDetected: "2026-08-01T10:00:00.000Z",
  score: 55,
  ownerName: "Riley User"
};

function queryResult(overrides = {}) {
  return {
    findings: [FINDING_A, FINDING_B],
    totalCount: 2,
    pageNumber: 1,
    pageSize: 25,
    totalPages: 1,
    ...overrides
  };
}

describe("c-oi-health-remediation", () => {
  let createObjectURLSpy;
  let revokeObjectURLSpy;
  let anchorClickSpy;

  beforeEach(() => {
    getRemediationSummary.mockResolvedValue(SUMMARY);
    getRemediationQueue.mockResolvedValue(queryResult());
    global.URL.createObjectURL = jest.fn(() => "blob:mock-url");
    global.URL.revokeObjectURL = jest.fn();
    createObjectURLSpy = global.URL.createObjectURL;
    revokeObjectURLSpy = global.URL.revokeObjectURL;
    anchorClickSpy = jest
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(() => {});
  });

  afterEach(() => {
    jest.clearAllMocks();
    anchorClickSpy.mockRestore();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders a loading skeleton — never a state banner — while the Remediation request is still in flight", () => {
    getRemediationSummary.mockReturnValue(new Promise(() => {}));
    getRemediationQueue.mockReturnValue(new Promise(() => {}));
    const element = createElement("c-oi-health-remediation", {
      is: OiHealthRemediation
    });
    document.body.appendChild(element);

    const skeleton = element.shadowRoot.querySelector("c-oi-skeleton");
    expect(skeleton).not.toBeNull();
    expect(skeleton.label).toBe("Loading Remediation");
    // A pending request is not one of the five settled states.
    expect(element.shadowRoot.querySelector("c-oi-state-banner")).toBeNull();
  });

  it("loads the summary and first page of the queue on connect and renders them", async () => {
    const element = createElement("c-oi-health-remediation", {
      is: OiHealthRemediation
    });
    document.body.appendChild(element);
    await flushPromises();

    expect(getRemediationSummary).toHaveBeenCalledTimes(1);
    expect(getRemediationQueue).toHaveBeenCalledWith(
      expect.objectContaining({
        pageNumber: 1,
        pageSize: 25,
        sortField: "severity",
        sortDirection: "ASC"
      })
    );

    const kpiTiles = element.shadowRoot.querySelectorAll(
      "c-oi-health-kpi-tile"
    );
    expect(kpiTiles).toHaveLength(3);

    const rows = element.shadowRoot.querySelectorAll(".oi-remediation-row");
    expect(rows).toHaveLength(2);
    expect(
      element.shadowRoot.querySelector(".oi-remediation-table-wrap").textContent
    ).toContain("A profile grants Modify All Data broadly");
  });

  it("renders the error banner when the initial load rejects", async () => {
    getRemediationSummary.mockRejectedValue({ body: { message: "Boom" } });
    const element = createElement("c-oi-health-remediation", {
      is: OiHealthRemediation
    });
    document.body.appendChild(element);
    await flushPromises();

    const banner = element.shadowRoot.querySelector("c-oi-state-banner");
    expect(banner).not.toBeNull();
    expect(banner.state).toBe("error");
    expect(banner.message).toBe("Boom");
  });

  it("re-queries with the chosen severities and resets to page 1 when the severity filter changes", async () => {
    getRemediationQueue
      .mockResolvedValueOnce(queryResult({ pageNumber: 2 }))
      .mockResolvedValue(queryResult());
    const element = createElement("c-oi-health-remediation", {
      is: OiHealthRemediation
    });
    document.body.appendChild(element);
    await flushPromises();

    const severityListbox = element.shadowRoot.querySelectorAll(
      "lightning-dual-listbox"
    )[1];
    severityListbox.dispatchEvent(
      new CustomEvent("change", { detail: { value: ["Critical"] } })
    );
    await flushPromises();

    expect(getRemediationQueue).toHaveBeenLastCalledWith(
      expect.objectContaining({ severityKeys: ["Critical"], pageNumber: 1 })
    );
  });

  it("toggles sort direction when the same column header is clicked twice, and resets on a different column", async () => {
    const element = createElement("c-oi-health-remediation", {
      is: OiHealthRemediation
    });
    document.body.appendChild(element);
    await flushPromises();

    const statusHeader = Array.from(
      element.shadowRoot.querySelectorAll(".oi-remediation-th")
    ).find((btn) => btn.textContent.includes("Status"));
    statusHeader.click();
    await flushPromises();
    expect(getRemediationQueue).toHaveBeenLastCalledWith(
      expect.objectContaining({ sortField: "status", sortDirection: "ASC" })
    );

    statusHeader.click();
    await flushPromises();
    expect(getRemediationQueue).toHaveBeenLastCalledWith(
      expect.objectContaining({ sortField: "status", sortDirection: "DESC" })
    );
  });

  it("opens the drawer with the clicked row finding", async () => {
    const element = createElement("c-oi-health-remediation", {
      is: OiHealthRemediation
    });
    document.body.appendChild(element);
    await flushPromises();

    element.shadowRoot
      .querySelector('[data-finding-id="001aFindingB"]')
      .click();
    await flushPromises();

    const drawer = element.shadowRoot.querySelector(
      "c-oi-health-finding-drawer"
    );
    expect(drawer).not.toBeNull();
    expect(drawer.finding.id).toBe("001aFindingB");
  });

  it("switches the drawer to a related finding when the drawer dispatches relatedselect", async () => {
    const element = createElement("c-oi-health-remediation", {
      is: OiHealthRemediation
    });
    document.body.appendChild(element);
    await flushPromises();

    element.shadowRoot
      .querySelector('[data-finding-id="001aFindingA"]')
      .click();
    await flushPromises();

    const drawer = element.shadowRoot.querySelector(
      "c-oi-health-finding-drawer"
    );
    drawer.dispatchEvent(
      new CustomEvent("relatedselect", { detail: { finding: FINDING_B } })
    );
    await flushPromises();

    expect(
      element.shadowRoot.querySelector("c-oi-health-finding-drawer").finding.id
    ).toBe("001aFindingB");
  });

  it("disables Previous on the first page and Next on the last page, and Next advances the page", async () => {
    getRemediationQueue.mockResolvedValue(
      queryResult({ pageNumber: 1, totalPages: 2, totalCount: 40 })
    );
    const element = createElement("c-oi-health-remediation", {
      is: OiHealthRemediation
    });
    document.body.appendChild(element);
    await flushPromises();

    const prevButton = element.shadowRoot.querySelector(
      ".oi-remediation-pagination-buttons button:first-child"
    );
    const nextButton = element.shadowRoot.querySelector(
      ".oi-remediation-pagination-buttons button:last-child"
    );
    expect(prevButton.disabled).toBe(true);
    expect(nextButton.disabled).toBe(false);

    nextButton.click();
    await flushPromises();

    expect(getRemediationQueue).toHaveBeenLastCalledWith(
      expect.objectContaining({ pageNumber: 2 })
    );
  });

  it("shows an honest empty-state note when no findings match the filter", async () => {
    getRemediationQueue.mockResolvedValue(
      queryResult({ findings: [], totalCount: 0, totalPages: 1 })
    );
    const element = createElement("c-oi-health-remediation", {
      is: OiHealthRemediation
    });
    document.body.appendChild(element);
    await flushPromises();

    const emptyBanner = element.shadowRoot.querySelector(
      'c-oi-state-banner[data-id="queue-empty"]'
    );
    expect(emptyBanner).not.toBeNull();
    expect(emptyBanner.state).toBe("true-zero");
    expect(emptyBanner.title).toBe("No findings match this filter");
    expect(
      element.shadowRoot.querySelectorAll(".oi-remediation-row")
    ).toHaveLength(0);
  });

  it("exports every matching row as a CSV download, using the current filter but ignoring the current page", async () => {
    exportRemediationQueue.mockResolvedValue([FINDING_A, FINDING_B]);
    const element = createElement("c-oi-health-remediation", {
      is: OiHealthRemediation
    });
    document.body.appendChild(element);
    await flushPromises();

    const exportButton = Array.from(
      element.shadowRoot.querySelectorAll("button")
    ).find((btn) => btn.textContent === "Export CSV");
    exportButton.click();
    await flushPromises();

    expect(exportRemediationQueue).toHaveBeenCalledWith(
      expect.objectContaining({ pageNumber: 1, pageSize: 25 })
    );
    expect(createObjectURLSpy).toHaveBeenCalledTimes(1);
    expect(anchorClickSpy).toHaveBeenCalledTimes(1);
    expect(revokeObjectURLSpy).toHaveBeenCalledTimes(1);
  });

  it("neutralizes a leading formula-trigger character in exported CSV cells (CSV/formula injection defense)", async () => {
    exportRemediationQueue.mockResolvedValue([
      { ...FINDING_A, title: "=2+2", ownerName: "+1234567890" }
    ]);
    const capturedBlobParts = [];
    const OriginalBlob = global.Blob;
    global.Blob = jest.fn(function mockBlob(parts, options) {
      capturedBlobParts.push(parts[0]);
      return new OriginalBlob(parts, options);
    });

    const element = createElement("c-oi-health-remediation", {
      is: OiHealthRemediation
    });
    document.body.appendChild(element);
    await flushPromises();

    const exportButton = Array.from(
      element.shadowRoot.querySelectorAll("button")
    ).find((btn) => btn.textContent === "Export CSV");
    exportButton.click();
    await flushPromises();

    expect(capturedBlobParts[0]).toContain("'=2+2");
    expect(capturedBlobParts[0]).toContain("'+1234567890");

    global.Blob = OriginalBlob;
  });

  it("shows an export error instead of downloading when exportRemediationQueue rejects", async () => {
    exportRemediationQueue.mockRejectedValue({
      body: { message: "Export failed." }
    });
    const element = createElement("c-oi-health-remediation", {
      is: OiHealthRemediation
    });
    document.body.appendChild(element);
    await flushPromises();

    const exportButton = Array.from(
      element.shadowRoot.querySelectorAll("button")
    ).find((btn) => btn.textContent === "Export CSV");
    exportButton.click();
    await flushPromises();

    const exportBanner = element.shadowRoot.querySelector(
      'c-oi-state-banner[data-id="export-error"]'
    );
    expect(exportBanner).not.toBeNull();
    expect(exportBanner.state).toBe("error");
    expect(exportBanner.message).toBe("Export failed.");
    expect(createObjectURLSpy).not.toHaveBeenCalled();
  });

  it("resets every filter and re-queries when Clear filters is clicked", async () => {
    const element = createElement("c-oi-health-remediation", {
      is: OiHealthRemediation
    });
    document.body.appendChild(element);
    await flushPromises();

    const severityListbox = element.shadowRoot.querySelectorAll(
      "lightning-dual-listbox"
    )[1];
    severityListbox.dispatchEvent(
      new CustomEvent("change", { detail: { value: ["Critical"] } })
    );
    await flushPromises();

    const clearButton = Array.from(
      element.shadowRoot.querySelectorAll("button")
    ).find((btn) => btn.textContent === "Clear filters");
    clearButton.click();
    await flushPromises();

    expect(getRemediationQueue).toHaveBeenLastCalledWith(
      expect.objectContaining({
        sectionKeys: null,
        severityKeys: null,
        statuses: null,
        ownerId: null,
        searchText: null,
        pageNumber: 1
      })
    );
  });
});
