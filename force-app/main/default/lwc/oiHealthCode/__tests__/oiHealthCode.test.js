import { createElement } from "lwc";
import OiHealthCode from "c/oiHealthCode";
import getCodeHealthDetail from "@salesforce/apex/OI_OrgHealthController.getCodeHealthDetail";
import getCodeHealthFindings from "@salesforce/apex/OI_OrgHealthController.getCodeHealthFindings";
import syncCodeHealthFindings from "@salesforce/apex/OI_OrgHealthController.syncCodeHealthFindings";

jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getCodeHealthDetail",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getCodeHealthFindings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.syncCodeHealthFindings",
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
  score: 82,
  severityKey: "Good",
  formulaSummary: "Score = 100 - weighted penalty per threshold breached.",
  formulaComponents: [{ label: "High dependency", value: "(weight 55%)" }],
  coverageNote: "3 / 3 classes scanned",
  isCoverageComplete: true,
  computedAt: "2026-08-31T10:00:00.000Z",
  kpiTiles: [
    { label: "Apex classes scanned", value: "3" },
    { label: "High-dependency classes", value: "1" },
    { label: "Stale API version classes", value: "1" },
    { label: "Classes in dependency cycles", value: "0" }
  ],
  breakdownTitle: "Classes needing attention",
  breakdownCoverageCaption: "Top 3 of 3",
  metricColumnLabels: ["Dependencies", "API Ver"],
  breakdownRows: [
    {
      key: "cls1",
      primaryLabel: "Hub_Class",
      metricValues: [{ key: "dependency", value: "22" }],
      severityKey: "Warning",
      severityLabel: "Warning"
    }
  ],
  heatmapColumnLabels: ["Dependencies", "API Ver"],
  heatmapRows: [
    {
      rowLabel: "Hub_Class",
      cells: [{ key: "dependency", value: "22", severityKey: "Warning" }]
    }
  ]
};

const SAMPLE_FINDING = {
  id: "001aCodeFinding",
  componentKey: "cls1",
  title: "Hub_Class has an unusually high combined fan-in/fan-out",
  severityKey: "Warning",
  status: "Open",
  lastDetected: "2026-08-31T10:00:00.000Z"
};

describe("c-oi-health-code", () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders a loading skeleton — never a state banner — while the Code Health request is still in flight", () => {
    getCodeHealthDetail.mockReturnValue(new Promise(() => {}));
    getCodeHealthFindings.mockReturnValue(new Promise(() => {}));
    const element = createElement("c-oi-health-code", { is: OiHealthCode });
    document.body.appendChild(element);

    const skeleton = element.shadowRoot.querySelector("c-oi-skeleton");
    expect(skeleton).not.toBeNull();
    expect(skeleton.label).toBe("Loading Code Health");
    // A pending request is not one of the five settled states.
    expect(element.shadowRoot.querySelector("c-oi-state-banner")).toBeNull();
  });

  it("renders the score ring, formula disclosure, KPI tiles, breakdown list, and heatmap from a real detail DTO", async () => {
    getCodeHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getCodeHealthFindings.mockResolvedValue([]);
    const element = createElement("c-oi-health-code", { is: OiHealthCode });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-oi-health-score-ring").score
    ).toBe(82);
    expect(
      element.shadowRoot.querySelector("c-oi-health-formula-disclosure")
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelectorAll("c-oi-health-kpi-tile").length
    ).toBe(4);
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

  it("maps formula component value to detail for the shared disclosure component", async () => {
    getCodeHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getCodeHealthFindings.mockResolvedValue([]);
    const element = createElement("c-oi-health-code", { is: OiHealthCode });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const disclosure = element.shadowRoot.querySelector(
      "c-oi-health-formula-disclosure"
    );
    expect(disclosure.components[0].detail).toBe("(weight 55%)");
  });

  it("renders the error banner and retries on demand", async () => {
    getCodeHealthDetail.mockRejectedValueOnce({ body: { message: "Denied" } });
    getCodeHealthFindings.mockResolvedValue([]);
    getCodeHealthDetail.mockResolvedValueOnce(SAMPLE_DETAIL);
    const element = createElement("c-oi-health-code", { is: OiHealthCode });
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
    ).toBe(4);
  });

  it("opens the finding drawer with the matching finding when a breakdown row is selected", async () => {
    getCodeHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getCodeHealthFindings.mockResolvedValue([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-code", { is: OiHealthCode });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const breakdownList = element.shadowRoot.querySelector(
      "c-oi-health-breakdown-list"
    );
    breakdownList.dispatchEvent(
      new CustomEvent("rowselect", { detail: { key: "cls1" } })
    );
    await Promise.resolve();

    const drawer = element.shadowRoot.querySelector(
      "c-oi-health-finding-drawer"
    );
    expect(drawer).not.toBeNull();
    expect(drawer.finding.id).toBe("001aCodeFinding");
    expect(
      element.shadowRoot.querySelector(".oi-health-selection-note")
    ).toBeNull();
  });

  it("switches the drawer to a related finding when the drawer dispatches relatedselect", async () => {
    getCodeHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getCodeHealthFindings.mockResolvedValue([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-code", { is: OiHealthCode });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot
      .querySelector("c-oi-health-breakdown-list")
      .dispatchEvent(new CustomEvent("rowselect", { detail: { key: "cls1" } }));
    await Promise.resolve();

    const relatedFinding = {
      ...SAMPLE_FINDING,
      id: "001aRelatedCodeFinding",
      componentKey: "cls2",
      title: "Utility_Class has a stale API version"
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
    expect(drawer.finding.id).toBe("001aRelatedCodeFinding");
    expect(drawer.finding.title).toBe("Utility_Class has a stale API version");
  });

  it("shows an honest note instead of the drawer when the selected row has no finding on file", async () => {
    getCodeHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getCodeHealthFindings.mockResolvedValue([]);
    const element = createElement("c-oi-health-code", { is: OiHealthCode });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const breakdownList = element.shadowRoot.querySelector(
      "c-oi-health-breakdown-list"
    );
    breakdownList.dispatchEvent(
      new CustomEvent("rowselect", { detail: { key: "cls1" } })
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
    getCodeHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getCodeHealthFindings.mockResolvedValue([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-code", { is: OiHealthCode });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot
      .querySelector("c-oi-health-breakdown-list")
      .dispatchEvent(new CustomEvent("rowselect", { detail: { key: "cls1" } }));
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
    getCodeHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getCodeHealthFindings.mockResolvedValueOnce([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-code", { is: OiHealthCode });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot
      .querySelector("c-oi-health-breakdown-list")
      .dispatchEvent(new CustomEvent("rowselect", { detail: { key: "cls1" } }));
    await Promise.resolve();

    const updatedFinding = { ...SAMPLE_FINDING, status: "Acknowledged" };
    getCodeHealthFindings.mockResolvedValueOnce([updatedFinding]);
    element.shadowRoot
      .querySelector("c-oi-health-finding-drawer")
      .dispatchEvent(new CustomEvent("saved"));
    await flushPromises();
    await Promise.resolve();

    expect(getCodeHealthFindings).toHaveBeenCalledTimes(2);
    expect(
      element.shadowRoot.querySelector("c-oi-health-finding-drawer").finding
        .status
    ).toBe("Acknowledged");
  });

  it("runs a sync and reloads the detail and findings when the Sync findings button is clicked", async () => {
    getCodeHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getCodeHealthFindings.mockResolvedValue([]);
    syncCodeHealthFindings.mockResolvedValue("Synced");
    const element = createElement("c-oi-health-code", { is: OiHealthCode });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot.querySelector("button.oi-btn").click();
    await flushPromises();
    await Promise.resolve();

    expect(syncCodeHealthFindings).toHaveBeenCalledTimes(1);
    expect(getCodeHealthDetail).toHaveBeenCalledTimes(2);
    expect(getCodeHealthFindings).toHaveBeenCalledTimes(2);
  });

  it("shows a sync error without losing the currently loaded detail", async () => {
    getCodeHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getCodeHealthFindings.mockResolvedValue([]);
    syncCodeHealthFindings.mockRejectedValueOnce({
      body: { message: "You don’t have permission." }
    });
    const element = createElement("c-oi-health-code", { is: OiHealthCode });
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
      element.shadowRoot.querySelector("c-oi-health-score-ring")
    ).not.toBeNull();
  });
});
