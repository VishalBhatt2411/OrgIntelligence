import { createElement } from "lwc";
import OiOrgHealthDashboard from "c/oiOrgHealthDashboard";
import getOrgHealthSummary from "@salesforce/apex/OI_OrgHealthController.getOrgHealthSummary";

jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getOrgHealthSummary",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const SUMMARY = {
  overview: {
    objectCount: 187,
    fieldCount: 4362,
    apexClassCount: 612,
    triggerCount: 94,
    flowCount: 156,
    permissionSetCount: 38,
    dependencyCount: 8940,
    relationshipCount: 2103,
    lastScannedAt: "2026-08-31T09:00:00.000Z"
  },
  sections: [
    {
      sectionKey: "OrgOverview",
      displayLabel: "Org Overview",
      isImplemented: true,
      isScored: false,
      score: null,
      severityKey: null,
      topSignals: [],
      coverageNote: "Last scanned"
    },
    {
      sectionKey: "Storage",
      displayLabel: "Storage",
      isImplemented: true,
      isScored: false,
      score: null,
      severityKey: null,
      topSignals: [],
      coverageNote: "Live org limits."
    },
    {
      sectionKey: "MetadataHealth",
      displayLabel: "Metadata Health",
      isImplemented: true,
      isScored: true,
      score: 78,
      severityKey: "Warning",
      topSignals: [],
      coverageNote: "187 / 187 objects scanned"
    },
    {
      sectionKey: "AutomationHealth",
      displayLabel: "Automation Health",
      isImplemented: true,
      isScored: false,
      score: null,
      severityKey: null,
      topSignals: [],
      coverageNote: "12 / 12 automation components scanned"
    },
    {
      sectionKey: "CodeHealth",
      displayLabel: "Code Health",
      isImplemented: true,
      isScored: true,
      score: 85,
      severityKey: "Good",
      topSignals: [],
      coverageNote: "612 / 612 classes scanned"
    },
    {
      sectionKey: "SecurityHealth",
      displayLabel: "Security Health",
      isImplemented: true,
      isScored: false,
      score: null,
      severityKey: null,
      topSignals: [],
      coverageNote: "38 / 38 permission sets & profiles scanned"
    },
    {
      sectionKey: "DataHealth",
      displayLabel: "Data Health",
      isImplemented: true,
      isScored: true,
      score: null,
      severityKey: null,
      topSignals: [],
      coverageNote:
        "Data Health has not been computed yet. Run a scan to see results."
    },
    // Synthetic — every real section is implemented as of Phase 5, so this stands in for a future package version's not-yet-built section, keeping the honest-fallback template path under test.
    {
      sectionKey: "FutureSection",
      displayLabel: "Future Section",
      isImplemented: false,
      isScored: false,
      score: null,
      severityKey: null,
      topSignals: [],
      coverageNote: "Not yet available in this package version."
    }
  ]
};

function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe("c-oi-org-health-dashboard", () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders a loading skeleton — never a state banner — while the Org Health request is still in flight", () => {
    getOrgHealthSummary.mockReturnValue(new Promise(() => {}));
    const element = createElement("c-oi-org-health-dashboard", {
      is: OiOrgHealthDashboard
    });
    document.body.appendChild(element);

    const skeleton = element.shadowRoot.querySelector("c-oi-skeleton");
    expect(skeleton).not.toBeNull();
    expect(skeleton.label).toBe("Loading Org Health");
    // A pending request is not one of the five settled states.
    expect(element.shadowRoot.querySelector("c-oi-state-banner")).toBeNull();
  });

  it("loads the summary on connect and renders the section nav plus the overview grid by default", async () => {
    getOrgHealthSummary.mockResolvedValue(SUMMARY);
    const element = createElement("c-oi-org-health-dashboard", {
      is: OiOrgHealthDashboard
    });
    document.body.appendChild(element);

    await flushPromises();
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-oi-health-section-nav")
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelector("c-oi-health-overview-grid")
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector("c-oi-health-storage")).toBeNull();
  });

  it("switches to the Storage detail container when the section nav emits select for Storage", async () => {
    getOrgHealthSummary.mockResolvedValue(SUMMARY);
    const element = createElement("c-oi-org-health-dashboard", {
      is: OiOrgHealthDashboard
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const nav = element.shadowRoot.querySelector("c-oi-health-section-nav");
    nav.dispatchEvent(
      new CustomEvent("select", { detail: { sectionKey: "Storage" } })
    );
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-oi-health-storage")
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelector("c-oi-health-overview-grid")
    ).toBeNull();
  });

  it("switches to the Metadata Health detail container when the section nav emits select for MetadataHealth", async () => {
    getOrgHealthSummary.mockResolvedValue(SUMMARY);
    const element = createElement("c-oi-org-health-dashboard", {
      is: OiOrgHealthDashboard
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const nav = element.shadowRoot.querySelector("c-oi-health-section-nav");
    nav.dispatchEvent(
      new CustomEvent("select", { detail: { sectionKey: "MetadataHealth" } })
    );
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-oi-health-metadata")
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector("c-oi-state-banner")).toBeNull();
  });

  it("switches to the Automation Health detail container when the section nav emits select for AutomationHealth", async () => {
    getOrgHealthSummary.mockResolvedValue(SUMMARY);
    const element = createElement("c-oi-org-health-dashboard", {
      is: OiOrgHealthDashboard
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const nav = element.shadowRoot.querySelector("c-oi-health-section-nav");
    nav.dispatchEvent(
      new CustomEvent("select", { detail: { sectionKey: "AutomationHealth" } })
    );
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-oi-health-automation")
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector("c-oi-state-banner")).toBeNull();
  });

  it("switches to the Code Health detail container when the section nav emits select for CodeHealth", async () => {
    getOrgHealthSummary.mockResolvedValue(SUMMARY);
    const element = createElement("c-oi-org-health-dashboard", {
      is: OiOrgHealthDashboard
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const nav = element.shadowRoot.querySelector("c-oi-health-section-nav");
    nav.dispatchEvent(
      new CustomEvent("select", { detail: { sectionKey: "CodeHealth" } })
    );
    await Promise.resolve();

    expect(element.shadowRoot.querySelector("c-oi-health-code")).not.toBeNull();
    expect(element.shadowRoot.querySelector("c-oi-state-banner")).toBeNull();
  });

  it("switches to the Security Health detail container when the section nav emits select for SecurityHealth", async () => {
    getOrgHealthSummary.mockResolvedValue(SUMMARY);
    const element = createElement("c-oi-org-health-dashboard", {
      is: OiOrgHealthDashboard
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const nav = element.shadowRoot.querySelector("c-oi-health-section-nav");
    nav.dispatchEvent(
      new CustomEvent("select", { detail: { sectionKey: "SecurityHealth" } })
    );
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-oi-health-security")
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector("c-oi-state-banner")).toBeNull();
  });

  it("switches to the Data Health detail container when the section nav emits select for DataHealth", async () => {
    getOrgHealthSummary.mockResolvedValue(SUMMARY);
    const element = createElement("c-oi-org-health-dashboard", {
      is: OiOrgHealthDashboard
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const nav = element.shadowRoot.querySelector("c-oi-health-section-nav");
    nav.dispatchEvent(
      new CustomEvent("select", { detail: { sectionKey: "DataHealth" } })
    );
    await Promise.resolve();

    expect(element.shadowRoot.querySelector("c-oi-health-data")).not.toBeNull();
  });

  it("appends Remediation as a client-side nav tab and switches to its workspace container when selected", async () => {
    getOrgHealthSummary.mockResolvedValue(SUMMARY);
    const element = createElement("c-oi-org-health-dashboard", {
      is: OiOrgHealthDashboard
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const nav = element.shadowRoot.querySelector("c-oi-health-section-nav");
    expect(nav.sections).toContainEqual({
      sectionKey: "Remediation",
      displayLabel: "Remediation",
      severityKey: null
    });

    nav.dispatchEvent(
      new CustomEvent("select", { detail: { sectionKey: "Remediation" } })
    );
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-oi-health-remediation")
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector("c-oi-state-banner")).toBeNull();
  });

  it("shows an honest not-yet-available banner for a section with no Phase container yet", async () => {
    getOrgHealthSummary.mockResolvedValue(SUMMARY);
    const element = createElement("c-oi-org-health-dashboard", {
      is: OiOrgHealthDashboard
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const nav = element.shadowRoot.querySelector("c-oi-health-section-nav");
    nav.dispatchEvent(
      new CustomEvent("select", { detail: { sectionKey: "FutureSection" } })
    );
    await Promise.resolve();

    const banner = element.shadowRoot.querySelector("c-oi-state-banner");
    expect(banner).not.toBeNull();
    expect(banner.message).toBe("Not yet available in this package version.");
  });

  it("renders the error banner when the Apex call rejects", async () => {
    getOrgHealthSummary.mockRejectedValue({ body: { message: "Boom" } });
    const element = createElement("c-oi-org-health-dashboard", {
      is: OiOrgHealthDashboard
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const banner = element.shadowRoot.querySelector("c-oi-state-banner");
    expect(banner).not.toBeNull();
    expect(banner.state).toBe("error");
    expect(banner.message).toBe("Boom");
  });
});
