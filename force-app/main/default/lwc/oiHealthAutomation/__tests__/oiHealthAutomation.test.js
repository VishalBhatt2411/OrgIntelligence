import { createElement } from "lwc";
import OiHealthAutomation from "c/oiHealthAutomation";
import getAutomationHealthDetail from "@salesforce/apex/OI_OrgHealthController.getAutomationHealthDetail";
import getAutomationHealthFindings from "@salesforce/apex/OI_OrgHealthController.getAutomationHealthFindings";
import syncAutomationHealthFindings from "@salesforce/apex/OI_OrgHealthController.syncAutomationHealthFindings";

jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getAutomationHealthDetail",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getAutomationHealthFindings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.syncAutomationHealthFindings",
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
  coverageNote: "3 / 3 automation components scanned",
  isCoverageComplete: true,
  computedAt: "2026-08-31T10:00:00.000Z",
  kpiTiles: [
    { label: "Triggers scanned", value: "2" },
    { label: "Flows scanned", value: "1" },
    { label: "High fan-in/out components", value: "1" },
    { label: "Components in dependency cycles", value: "0" },
    { label: "Most automated object", value: "Account (2)" }
  ],
  breakdownTitle: "Components needing attention",
  breakdownCoverageCaption: "Top 3 of 3",
  metricColumnLabels: ["Fan-out", "Fan-in"],
  breakdownRows: [
    {
      key: "trg1",
      primaryLabel: "AccountTrigger",
      metricValues: [{ key: "fanOut", value: "2" }],
      severityKey: "Warning",
      severityLabel: "Warning"
    }
  ],
  heatmapColumnLabels: ["Fan-out", "Fan-in", "Cycle"],
  heatmapRows: [
    {
      rowLabel: "AccountTrigger",
      cells: [{ key: "fanOut", value: "2", severityKey: "Warning" }]
    }
  ]
};

const SAMPLE_FINDING = {
  id: "001aAutoFinding",
  componentKey: "trg1",
  title: "AccountTrigger has an unusually high combined fan-in/fan-out",
  severityKey: "Warning",
  status: "Open",
  lastDetected: "2026-08-31T10:00:00.000Z"
};

describe("c-oi-health-automation", () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders a loading skeleton — never a state banner — while the Automation Health request is still in flight", () => {
    getAutomationHealthDetail.mockReturnValue(new Promise(() => {}));
    getAutomationHealthFindings.mockReturnValue(new Promise(() => {}));
    const element = createElement("c-oi-health-automation", {
      is: OiHealthAutomation
    });
    document.body.appendChild(element);

    const skeleton = element.shadowRoot.querySelector("c-oi-skeleton");
    expect(skeleton).not.toBeNull();
    expect(skeleton.label).toBe("Loading Automation Health");
    // A pending request is not one of the five settled states.
    expect(element.shadowRoot.querySelector("c-oi-state-banner")).toBeNull();
  });

  it("renders a facts-only badge (never a score ring), KPI tiles, breakdown list, and heatmap from a real detail DTO", async () => {
    getAutomationHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getAutomationHealthFindings.mockResolvedValue([]);
    const element = createElement("c-oi-health-automation", {
      is: OiHealthAutomation
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
    getAutomationHealthDetail.mockRejectedValueOnce({
      body: { message: "Denied" }
    });
    getAutomationHealthFindings.mockResolvedValue([]);
    getAutomationHealthDetail.mockResolvedValueOnce(SAMPLE_DETAIL);
    const element = createElement("c-oi-health-automation", {
      is: OiHealthAutomation
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
    getAutomationHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getAutomationHealthFindings.mockResolvedValue([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-automation", {
      is: OiHealthAutomation
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const breakdownList = element.shadowRoot.querySelector(
      "c-oi-health-breakdown-list"
    );
    breakdownList.dispatchEvent(
      new CustomEvent("rowselect", { detail: { key: "trg1" } })
    );
    await Promise.resolve();

    const drawer = element.shadowRoot.querySelector(
      "c-oi-health-finding-drawer"
    );
    expect(drawer).not.toBeNull();
    expect(drawer.finding.id).toBe("001aAutoFinding");
    expect(
      element.shadowRoot.querySelector(".oi-health-selection-note")
    ).toBeNull();
  });

  it("switches the drawer to a related finding when the drawer dispatches relatedselect", async () => {
    getAutomationHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getAutomationHealthFindings.mockResolvedValue([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-automation", {
      is: OiHealthAutomation
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot
      .querySelector("c-oi-health-breakdown-list")
      .dispatchEvent(new CustomEvent("rowselect", { detail: { key: "trg1" } }));
    await Promise.resolve();

    const relatedFinding = {
      ...SAMPLE_FINDING,
      id: "001aRelatedAutoFinding",
      componentKey: "trg2",
      title: "ContactTrigger is part of a dependency cycle"
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
    expect(drawer.finding.id).toBe("001aRelatedAutoFinding");
    expect(drawer.finding.title).toBe(
      "ContactTrigger is part of a dependency cycle"
    );
  });

  it("shows an honest note instead of the drawer when the selected row has no finding on file", async () => {
    getAutomationHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getAutomationHealthFindings.mockResolvedValue([]);
    const element = createElement("c-oi-health-automation", {
      is: OiHealthAutomation
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const breakdownList = element.shadowRoot.querySelector(
      "c-oi-health-breakdown-list"
    );
    breakdownList.dispatchEvent(
      new CustomEvent("rowselect", { detail: { key: "trg1" } })
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
    getAutomationHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getAutomationHealthFindings.mockResolvedValue([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-automation", {
      is: OiHealthAutomation
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot
      .querySelector("c-oi-health-breakdown-list")
      .dispatchEvent(new CustomEvent("rowselect", { detail: { key: "trg1" } }));
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
    getAutomationHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getAutomationHealthFindings.mockResolvedValueOnce([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-automation", {
      is: OiHealthAutomation
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot
      .querySelector("c-oi-health-breakdown-list")
      .dispatchEvent(new CustomEvent("rowselect", { detail: { key: "trg1" } }));
    await Promise.resolve();

    const updatedFinding = { ...SAMPLE_FINDING, status: "Acknowledged" };
    getAutomationHealthFindings.mockResolvedValueOnce([updatedFinding]);
    element.shadowRoot
      .querySelector("c-oi-health-finding-drawer")
      .dispatchEvent(new CustomEvent("saved"));
    await flushPromises();
    await Promise.resolve();

    expect(getAutomationHealthFindings).toHaveBeenCalledTimes(2);
    expect(
      element.shadowRoot.querySelector("c-oi-health-finding-drawer").finding
        .status
    ).toBe("Acknowledged");
  });

  it("runs a sync and reloads the detail and findings when the Sync findings button is clicked", async () => {
    getAutomationHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getAutomationHealthFindings.mockResolvedValue([]);
    syncAutomationHealthFindings.mockResolvedValue("Synced");
    const element = createElement("c-oi-health-automation", {
      is: OiHealthAutomation
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot.querySelector("button.oi-btn").click();
    await flushPromises();
    await Promise.resolve();

    expect(syncAutomationHealthFindings).toHaveBeenCalledTimes(1);
    expect(getAutomationHealthDetail).toHaveBeenCalledTimes(2);
    expect(getAutomationHealthFindings).toHaveBeenCalledTimes(2);
  });

  it("shows a sync error without losing the currently loaded detail", async () => {
    getAutomationHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getAutomationHealthFindings.mockResolvedValue([]);
    syncAutomationHealthFindings.mockRejectedValueOnce({
      body: { message: "You don’t have permission." }
    });
    const element = createElement("c-oi-health-automation", {
      is: OiHealthAutomation
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
