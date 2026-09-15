import { createElement } from "lwc";
import OiHealthData from "c/oiHealthData";
import getDataHealthDetail from "@salesforce/apex/OI_OrgHealthController.getDataHealthDetail";
import recomputeDataHealth from "@salesforce/apex/OI_OrgHealthController.recomputeDataHealth";
import getDataHealthFindings from "@salesforce/apex/OI_OrgHealthController.getDataHealthFindings";

jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getDataHealthDetail",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.recomputeDataHealth",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getDataHealthFindings",
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

/** setTimeout-based flushPromises deadlocks once jest.useFakeTimers() is active — this drains microtasks (native Promise resolution is never faked) without depending on any timer. */
async function flushMicrotasks() {
  for (let i = 0; i < 10; i++) {
    // eslint-disable-next-line no-await-in-loop -- each iteration must wait for the prior microtask to drain before queuing the next.
    await Promise.resolve();
  }
}

const NOT_YET_RUN_DETAIL = {
  runStatus: "NotYetRun",
  score: null,
  severityKey: null,
  formulaComponents: [],
  coverageNote:
    "Data Health has not been computed yet. Run a scan to see results.",
  isCoverageComplete: false,
  computedAt: null,
  kpiTiles: [],
  breakdownRows: [],
  heatmapRows: []
};

const COMPLETED_DETAIL = {
  runStatus: "Completed",
  score: 88,
  severityKey: "Good",
  formulaSummary: "Score = 100 - weighted penalty per metric.",
  formulaComponents: [{ label: "Stale records", value: "(weight 35%)" }],
  coverageNote: "5 objects scanned",
  isCoverageComplete: true,
  computedAt: "2026-08-31T10:00:00.000Z",
  kpiTiles: [
    { label: "Objects scanned", value: "5" },
    { label: "Records sampled", value: "400" },
    { label: "Stale records", value: "10" },
    { label: "Incomplete records", value: "2" },
    { label: "Duplicate records", value: "4" }
  ],
  breakdownTitle: "Objects needing attention",
  breakdownCoverageCaption: "Top 2 of 2",
  metricColumnLabels: ["Stale %", "Incomplete %", "Duplicate %"],
  breakdownRows: [
    {
      key: "Contact",
      primaryLabel: "Contact (200 total)",
      metricValues: [{ key: "duplicate", value: "20.0" }],
      severityKey: "Critical",
      severityLabel: "Critical"
    }
  ],
  heatmapColumnLabels: ["Stale %", "Incomplete %", "Duplicate %"],
  heatmapRows: [
    {
      rowLabel: "Contact",
      cells: [{ key: "duplicate", value: "20.0", severityKey: "Critical" }]
    }
  ]
};

const SAMPLE_FINDING = {
  id: "001aDataFinding",
  componentKey: "Contact",
  title: "Contact has an unusually high rate of exact-match duplicate records",
  severityKey: "Critical",
  status: "Open",
  lastDetected: "2026-08-31T10:00:00.000Z"
};

describe("c-oi-health-data", () => {
  afterEach(() => {
    jest.clearAllMocks();
    jest.useRealTimers();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders a loading skeleton — never a state banner — while the Data Health request is still in flight", () => {
    getDataHealthDetail.mockReturnValue(new Promise(() => {}));
    getDataHealthFindings.mockReturnValue(new Promise(() => {}));
    const element = createElement("c-oi-health-data", { is: OiHealthData });
    document.body.appendChild(element);

    const skeleton = element.shadowRoot.querySelector("c-oi-skeleton");
    expect(skeleton).not.toBeNull();
    expect(skeleton.label).toBe("Loading Data Health");
    // A pending request is not one of the five settled states.
    expect(element.shadowRoot.querySelector("c-oi-state-banner")).toBeNull();
  });

  it("renders the not-yet-run prompt with a Run Scan button when no computation has ever completed", async () => {
    getDataHealthDetail.mockResolvedValue(NOT_YET_RUN_DETAIL);
    getDataHealthFindings.mockResolvedValue([]);
    const element = createElement("c-oi-health-data", { is: OiHealthData });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const banners = element.shadowRoot.querySelectorAll("c-oi-state-banner");
    expect(banners.length).toBe(1);
    expect(banners[0].state).toBe("not-yet-run");
    const button = element.shadowRoot.querySelector("button.oi-btn_primary");
    expect(button).not.toBeNull();
    expect(button.textContent).toBe("Run Data Health Scan");
    expect(
      element.shadowRoot.querySelector("c-oi-health-score-ring")
    ).toBeNull();
  });

  it("starts a recompute, then polls while the run is in progress, and stops once completed", async () => {
    jest.useFakeTimers();
    getDataHealthDetail.mockResolvedValueOnce(NOT_YET_RUN_DETAIL);
    getDataHealthFindings.mockResolvedValue([]);
    recomputeDataHealth.mockResolvedValueOnce("Queued");
    getDataHealthDetail.mockResolvedValueOnce({
      ...NOT_YET_RUN_DETAIL,
      runStatus: "Processing"
    });
    getDataHealthDetail.mockResolvedValueOnce(COMPLETED_DETAIL);

    const element = createElement("c-oi-health-data", { is: OiHealthData });
    document.body.appendChild(element);
    await flushMicrotasks();

    element.shadowRoot.querySelector("button.oi-btn_primary").click();
    await flushMicrotasks();

    expect(recomputeDataHealth).toHaveBeenCalledTimes(1);
    expect(getDataHealthDetail).toHaveBeenCalledTimes(2);
    let banner = element.shadowRoot.querySelector("c-oi-state-banner");
    expect(banner.title).toBe("Data Health scan in progress");

    jest.advanceTimersByTime(5000);
    await flushMicrotasks();

    expect(getDataHealthDetail).toHaveBeenCalledTimes(3);
    expect(
      element.shadowRoot.querySelector("c-oi-health-score-ring").score
    ).toBe(88);
    expect(
      element.shadowRoot.querySelectorAll("c-oi-state-banner").length
    ).toBe(0);

    jest.advanceTimersByTime(10000);
    await flushMicrotasks();
    expect(getDataHealthDetail).toHaveBeenCalledTimes(3);
  });

  it("keeps the last known good result visible underneath a failed-run banner and retries via recompute", async () => {
    getDataHealthDetail.mockResolvedValueOnce({
      ...COMPLETED_DETAIL,
      runStatus: "Failed"
    });
    getDataHealthFindings.mockResolvedValue([]);
    const element = createElement("c-oi-health-data", { is: OiHealthData });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const banner = element.shadowRoot.querySelector("c-oi-state-banner");
    expect(banner.state).toBe("error");
    expect(
      element.shadowRoot.querySelector("c-oi-health-score-ring").score
    ).toBe(88);

    recomputeDataHealth.mockResolvedValueOnce("Queued");
    getDataHealthDetail.mockResolvedValueOnce({
      ...COMPLETED_DETAIL,
      runStatus: "Processing"
    });
    banner.dispatchEvent(new CustomEvent("retry"));
    await flushPromises();

    expect(recomputeDataHealth).toHaveBeenCalledTimes(1);
  });

  it("renders the error banner and retries on demand", async () => {
    getDataHealthDetail.mockRejectedValueOnce({ body: { message: "Denied" } });
    getDataHealthFindings.mockResolvedValue([]);
    getDataHealthDetail.mockResolvedValueOnce(NOT_YET_RUN_DETAIL);
    const element = createElement("c-oi-health-data", { is: OiHealthData });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const banner = element.shadowRoot.querySelector("c-oi-state-banner");
    expect(banner.state).toBe("error");
    expect(banner.message).toBe("Denied");

    banner.dispatchEvent(new CustomEvent("retry"));
    await flushPromises();
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("button.oi-btn_primary")
    ).not.toBeNull();
  });

  it("opens the finding drawer with the matching finding when a breakdown row is selected", async () => {
    getDataHealthDetail.mockResolvedValue(COMPLETED_DETAIL);
    getDataHealthFindings.mockResolvedValue([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-data", { is: OiHealthData });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const breakdownList = element.shadowRoot.querySelector(
      "c-oi-health-breakdown-list"
    );
    expect(breakdownList.clickable).toBeTruthy();
    breakdownList.dispatchEvent(
      new CustomEvent("rowselect", { detail: { key: "Contact" } })
    );
    await Promise.resolve();

    const drawer = element.shadowRoot.querySelector(
      "c-oi-health-finding-drawer"
    );
    expect(drawer).not.toBeNull();
    expect(drawer.finding.id).toBe("001aDataFinding");
    expect(
      element.shadowRoot.querySelector(".oi-health-selection-note")
    ).toBeNull();
  });

  it("switches the drawer to a related finding when the drawer dispatches relatedselect", async () => {
    getDataHealthDetail.mockResolvedValue(COMPLETED_DETAIL);
    getDataHealthFindings.mockResolvedValue([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-data", { is: OiHealthData });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot
      .querySelector("c-oi-health-breakdown-list")
      .dispatchEvent(
        new CustomEvent("rowselect", { detail: { key: "Contact" } })
      );
    await Promise.resolve();

    const relatedFinding = {
      ...SAMPLE_FINDING,
      id: "001aRelatedDataFinding",
      componentKey: "Lead",
      title: "Lead has an unusually high rate of stale records"
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
    expect(drawer.finding.id).toBe("001aRelatedDataFinding");
    expect(drawer.finding.title).toBe(
      "Lead has an unusually high rate of stale records"
    );
  });

  it("shows an honest note instead of the drawer when the selected row has no finding on file", async () => {
    getDataHealthDetail.mockResolvedValue(COMPLETED_DETAIL);
    getDataHealthFindings.mockResolvedValue([]);
    const element = createElement("c-oi-health-data", { is: OiHealthData });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const breakdownList = element.shadowRoot.querySelector(
      "c-oi-health-breakdown-list"
    );
    breakdownList.dispatchEvent(
      new CustomEvent("rowselect", { detail: { key: "Contact" } })
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
    getDataHealthDetail.mockResolvedValue(COMPLETED_DETAIL);
    getDataHealthFindings.mockResolvedValue([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-data", { is: OiHealthData });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot
      .querySelector("c-oi-health-breakdown-list")
      .dispatchEvent(
        new CustomEvent("rowselect", { detail: { key: "Contact" } })
      );
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
    getDataHealthDetail.mockResolvedValue(COMPLETED_DETAIL);
    getDataHealthFindings.mockResolvedValueOnce([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-data", { is: OiHealthData });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot
      .querySelector("c-oi-health-breakdown-list")
      .dispatchEvent(
        new CustomEvent("rowselect", { detail: { key: "Contact" } })
      );
    await Promise.resolve();

    const updatedFinding = { ...SAMPLE_FINDING, status: "Acknowledged" };
    getDataHealthFindings.mockResolvedValueOnce([updatedFinding]);
    element.shadowRoot
      .querySelector("c-oi-health-finding-drawer")
      .dispatchEvent(new CustomEvent("saved"));
    await flushPromises();
    await Promise.resolve();

    expect(getDataHealthFindings).toHaveBeenCalledTimes(2);
    expect(
      element.shadowRoot.querySelector("c-oi-health-finding-drawer").finding
        .status
    ).toBe("Acknowledged");
  });
});
