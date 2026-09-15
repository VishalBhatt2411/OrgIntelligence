import { createElement } from "lwc";
import OiHealthSecurity from "c/oiHealthSecurity";
import getSecurityHealthDetail from "@salesforce/apex/OI_OrgHealthController.getSecurityHealthDetail";
import getSecurityHealthFindings from "@salesforce/apex/OI_OrgHealthController.getSecurityHealthFindings";
import syncSecurityHealthFindings from "@salesforce/apex/OI_OrgHealthController.syncSecurityHealthFindings";

jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getSecurityHealthDetail",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getSecurityHealthFindings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.syncSecurityHealthFindings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/OI_Run_Org_Health_Compute",
  () => ({ default: true }),
  { virtual: true }
);

function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

const SAMPLE_DETAIL = {
  coverageNote: "3 / 3 permission sets & profiles scanned",
  isCoverageComplete: true,
  computedAt: "2026-08-31T10:00:00.000Z",
  kpiTiles: [
    { label: "Permission sets & profiles scanned", value: "3" },
    { label: "Elevated permission sets", value: "1" },
    { label: "Permission sets with broad grants", value: "1" },
    { label: "Sensitive object grants", value: "1" },
    { label: "Unassigned custom permission sets", value: "0" }
  ],
  breakdownTitle: "Permission sets needing attention",
  breakdownCoverageCaption: "Top 3 of 3",
  metricColumnLabels: ["Elevated perms", "Broad grants"],
  breakdownRows: [
    {
      key: "ps1",
      primaryLabel: "OI Test Elevated Sensitive",
      metricValues: [{ key: "elevated", value: "2" }],
      severityKey: "Critical",
      severityLabel: "Critical"
    }
  ],
  heatmapColumnLabels: ["Elevated", "Broad grants", "Sensitive"],
  heatmapRows: [
    {
      rowLabel: "OI Test Elevated Sensitive",
      cells: [{ key: "elevated", value: "2", severityKey: "Critical" }]
    }
  ]
};

const SAMPLE_FINDING = {
  id: "001aSecurityFinding",
  componentKey: "ps1",
  title: "OI Test Elevated Sensitive grants broad access to a sensitive object",
  severityKey: "Critical",
  status: "Open",
  lastDetected: "2026-08-31T10:00:00.000Z"
};

describe("c-oi-health-security", () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders a loading skeleton — never a state banner — while the Security Health request is still in flight", () => {
    getSecurityHealthDetail.mockReturnValue(new Promise(() => {}));
    getSecurityHealthFindings.mockReturnValue(new Promise(() => {}));
    const element = createElement("c-oi-health-security", {
      is: OiHealthSecurity
    });
    document.body.appendChild(element);

    const skeleton = element.shadowRoot.querySelector("c-oi-skeleton");
    expect(skeleton).not.toBeNull();
    expect(skeleton.label).toBe("Loading Security Health");
    // A pending request is not one of the five settled states.
    expect(element.shadowRoot.querySelector("c-oi-state-banner")).toBeNull();
  });

  it("renders a facts-only badge (never a score ring), KPI tiles, breakdown list, and heatmap from a real detail DTO", async () => {
    getSecurityHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getSecurityHealthFindings.mockResolvedValue([]);
    const element = createElement("c-oi-health-security", {
      is: OiHealthSecurity
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const badge = element.shadowRoot.querySelector(
      "c-oi-health-severity-badge"
    );
    expect(badge).not.toBeNull();
    expect(badge.factsOnly).toBeTruthy();
    expect(
      element.shadowRoot.querySelector("c-oi-health-score-ring")
    ).toBeNull();
    expect(
      element.shadowRoot.querySelector("c-oi-health-formula-disclosure")
    ).toBeNull();
    expect(
      element.shadowRoot.querySelectorAll("c-oi-health-kpi-tile").length
    ).toBe(5);
    const breakdownList = element.shadowRoot.querySelector(
      "c-oi-health-breakdown-list"
    );
    expect(breakdownList.rows.length).toBe(1);
    expect(breakdownList.clickable).toBeTruthy();
    const heatmap = element.shadowRoot.querySelector(
      "c-oi-health-heatmap-grid"
    );
    expect(heatmap.rows.length).toBe(1);
    expect(
      element.shadowRoot.querySelectorAll("c-oi-state-banner").length
    ).toBe(0);
  });

  it("renders the error banner and retries on demand", async () => {
    getSecurityHealthDetail.mockRejectedValueOnce({
      body: { message: "Denied" }
    });
    getSecurityHealthFindings.mockResolvedValue([]);
    getSecurityHealthDetail.mockResolvedValueOnce(SAMPLE_DETAIL);
    const element = createElement("c-oi-health-security", {
      is: OiHealthSecurity
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    let banner = element.shadowRoot.querySelector("c-oi-state-banner");
    expect(banner.state).toBe("error");
    expect(banner.message).toBe("Denied");

    banner.dispatchEvent(new CustomEvent("retry"));
    await flushPromises();
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelectorAll("c-oi-health-kpi-tile").length
    ).toBe(5);
  });

  it("opens the finding drawer with the matching finding when a breakdown row is selected", async () => {
    getSecurityHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getSecurityHealthFindings.mockResolvedValue([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-security", {
      is: OiHealthSecurity
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const breakdownList = element.shadowRoot.querySelector(
      "c-oi-health-breakdown-list"
    );
    breakdownList.dispatchEvent(
      new CustomEvent("rowselect", { detail: { key: "ps1" } })
    );
    await Promise.resolve();

    const drawer = element.shadowRoot.querySelector(
      "c-oi-health-finding-drawer"
    );
    expect(drawer).not.toBeNull();
    expect(drawer.finding.id).toBe("001aSecurityFinding");
    expect(
      element.shadowRoot.querySelector(".oi-health-selection-note")
    ).toBeNull();
  });

  it("switches the drawer to a related finding when the drawer dispatches relatedselect", async () => {
    getSecurityHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getSecurityHealthFindings.mockResolvedValue([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-security", {
      is: OiHealthSecurity
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot
      .querySelector("c-oi-health-breakdown-list")
      .dispatchEvent(new CustomEvent("rowselect", { detail: { key: "ps1" } }));
    await Promise.resolve();

    const relatedFinding = {
      ...SAMPLE_FINDING,
      id: "001aRelatedSecurityFinding",
      componentKey: "ps2",
      title: "OI Test Broad Grant grants Modify All on a sensitive object"
    };
    element.shadowRoot
      .querySelector("c-oi-health-finding-drawer")
      .dispatchEvent(
        new CustomEvent("relatedselect", {
          detail: { finding: relatedFinding }
        })
      );
    await Promise.resolve();

    const drawer = element.shadowRoot.querySelector(
      "c-oi-health-finding-drawer"
    );
    expect(drawer.finding.id).toBe("001aRelatedSecurityFinding");
    expect(drawer.finding.title).toBe(
      "OI Test Broad Grant grants Modify All on a sensitive object"
    );
  });

  it("shows an honest note instead of the drawer when the selected row has no finding on file", async () => {
    getSecurityHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getSecurityHealthFindings.mockResolvedValue([]);
    const element = createElement("c-oi-health-security", {
      is: OiHealthSecurity
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const breakdownList = element.shadowRoot.querySelector(
      "c-oi-health-breakdown-list"
    );
    breakdownList.dispatchEvent(
      new CustomEvent("rowselect", { detail: { key: "ps1" } })
    );
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-oi-health-finding-drawer")
    ).toBeNull();
    expect(
      element.shadowRoot.querySelector(".oi-health-selection-note").textContent
    ).toContain("No finding is on file");
  });

  it("closes the drawer when the drawer dispatches close", async () => {
    getSecurityHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getSecurityHealthFindings.mockResolvedValue([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-security", {
      is: OiHealthSecurity
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot
      .querySelector("c-oi-health-breakdown-list")
      .dispatchEvent(new CustomEvent("rowselect", { detail: { key: "ps1" } }));
    await Promise.resolve();
    element.shadowRoot
      .querySelector("c-oi-health-finding-drawer")
      .dispatchEvent(new CustomEvent("close"));
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-oi-health-finding-drawer")
    ).toBeNull();
  });

  it("re-fetches findings when the drawer dispatches saved, keeping the drawer open with the refreshed finding", async () => {
    getSecurityHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getSecurityHealthFindings.mockResolvedValueOnce([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-security", {
      is: OiHealthSecurity
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot
      .querySelector("c-oi-health-breakdown-list")
      .dispatchEvent(new CustomEvent("rowselect", { detail: { key: "ps1" } }));
    await Promise.resolve();

    const updatedFinding = { ...SAMPLE_FINDING, status: "Acknowledged" };
    getSecurityHealthFindings.mockResolvedValueOnce([updatedFinding]);
    element.shadowRoot
      .querySelector("c-oi-health-finding-drawer")
      .dispatchEvent(new CustomEvent("saved"));
    await flushPromises();
    await Promise.resolve();

    expect(getSecurityHealthFindings).toHaveBeenCalledTimes(2);
    expect(
      element.shadowRoot.querySelector("c-oi-health-finding-drawer").finding
        .status
    ).toBe("Acknowledged");
  });

  it("runs a sync and reloads the detail and findings when the Sync findings button is clicked", async () => {
    getSecurityHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getSecurityHealthFindings.mockResolvedValue([]);
    syncSecurityHealthFindings.mockResolvedValue("Synced");
    const element = createElement("c-oi-health-security", {
      is: OiHealthSecurity
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot.querySelector("button.oi-btn").click();
    await flushPromises();
    await Promise.resolve();

    expect(syncSecurityHealthFindings).toHaveBeenCalledTimes(1);
    expect(getSecurityHealthDetail).toHaveBeenCalledTimes(2);
    expect(getSecurityHealthFindings).toHaveBeenCalledTimes(2);
  });

  it("shows a sync error without losing the currently loaded detail", async () => {
    getSecurityHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getSecurityHealthFindings.mockResolvedValue([]);
    syncSecurityHealthFindings.mockRejectedValueOnce({
      body: { message: "You don’t have permission." }
    });
    const element = createElement("c-oi-health-security", {
      is: OiHealthSecurity
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot.querySelector("button.oi-btn").click();
    await flushPromises();
    await Promise.resolve();

    const syncBanner = element.shadowRoot.querySelector("c-oi-state-banner");
    expect(syncBanner).not.toBeNull();
    expect(syncBanner.state).toBe("error");
    expect(syncBanner.message).toBe("You don’t have permission.");
    expect(
      element.shadowRoot.querySelector("c-oi-health-severity-badge")
    ).not.toBeNull();
  });
});
