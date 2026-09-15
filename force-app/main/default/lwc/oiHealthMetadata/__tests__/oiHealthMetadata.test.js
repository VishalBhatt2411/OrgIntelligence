import { createElement } from "lwc";
import OiHealthMetadata from "c/oiHealthMetadata";
import getMetadataHealthDetail from "@salesforce/apex/OI_OrgHealthController.getMetadataHealthDetail";
import getMetadataHealthFindings from "@salesforce/apex/OI_OrgHealthController.getMetadataHealthFindings";
import syncMetadataHealthFindings from "@salesforce/apex/OI_OrgHealthController.syncMetadataHealthFindings";
import getMetadataHealthKpiDrilldown from "@salesforce/apex/OI_OrgHealthController.getMetadataHealthKpiDrilldown";

jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getMetadataHealthDetail",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getMetadataHealthFindings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.syncMetadataHealthFindings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getMetadataHealthKpiDrilldown",
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
  score: 78,
  severityKey: "Warning",
  formulaSummary: "Score = 100 - weighted penalty per threshold breached.",
  formulaComponents: [{ label: "High field count", value: "(weight 35%)" }],
  coverageNote: "3 / 3 objects scanned",
  isCoverageComplete: true,
  computedAt: "2026-08-31T10:00:00.000Z",
  kpiTiles: [
    {
      label: "High field-count objects",
      value: "1",
      metricKey: "HighFieldCount"
    },
    { label: "High-degree objects", value: "1", metricKey: "HighDegree" },
    {
      label: "No incoming references detected",
      value: "1",
      metricKey: "OrphanRate"
    },
    {
      label: "Dependency density",
      value: "1.3",
      metricKey: "DependencyDensity"
    }
  ],
  breakdownTitle: "Objects needing attention",
  breakdownCoverageCaption: "Top 3 of 3",
  metricColumnLabels: ["Fields", "Degree"],
  breakdownRows: [
    {
      key: "obj1",
      primaryLabel: "Hub_Object__c",
      metricValues: [{ key: "fields", value: "4" }],
      severityKey: "Warning",
      severityLabel: "Warning",
      explanation: "4 custom fields — at or above this org's threshold of 3."
    }
  ],
  heatmapColumnLabels: ["Fields", "Degree", "No refs detected"],
  heatmapRows: [
    {
      rowLabel: "Hub_Object__c",
      cells: [{ key: "fields", value: "4", severityKey: "Good" }]
    }
  ]
};

const SAMPLE_FINDING = {
  id: "001aFinding",
  componentKey: "obj1",
  title: "Hub_Object__c has an unusually high field count",
  severityKey: "Warning",
  status: "Open",
  lastDetected: "2026-08-31T10:00:00.000Z"
};

describe("c-oi-health-metadata", () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders a loading skeleton — never a state banner — while the Metadata Health request is still in flight", () => {
    getMetadataHealthDetail.mockReturnValue(new Promise(() => {}));
    getMetadataHealthFindings.mockReturnValue(new Promise(() => {}));
    const element = createElement("c-oi-health-metadata", {
      is: OiHealthMetadata
    });
    document.body.appendChild(element);

    const skeleton = element.shadowRoot.querySelector("c-oi-skeleton");
    expect(skeleton).not.toBeNull();
    expect(skeleton.label).toBe("Loading Metadata Health");
    // A pending request is not one of the five settled states.
    expect(element.shadowRoot.querySelector("c-oi-state-banner")).toBeNull();
  });

  it("renders the score ring, formula disclosure, KPI tiles, breakdown list, and heatmap from a real detail DTO", async () => {
    getMetadataHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getMetadataHealthFindings.mockResolvedValue([]);
    const element = createElement("c-oi-health-metadata", {
      is: OiHealthMetadata
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-oi-health-score-ring").score
    ).toBe(78);
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
    getMetadataHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getMetadataHealthFindings.mockResolvedValue([]);
    const element = createElement("c-oi-health-metadata", {
      is: OiHealthMetadata
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const disclosure = element.shadowRoot.querySelector(
      "c-oi-health-formula-disclosure"
    );
    expect(disclosure.components[0].detail).toBe("(weight 35%)");
  });

  it("renders the error banner and retries on demand", async () => {
    getMetadataHealthDetail.mockRejectedValueOnce({
      body: { message: "Denied" }
    });
    getMetadataHealthFindings.mockResolvedValue([]);
    getMetadataHealthDetail.mockResolvedValueOnce(SAMPLE_DETAIL);
    const element = createElement("c-oi-health-metadata", {
      is: OiHealthMetadata
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
    ).toBe(4);
  });

  it("opens the finding drawer with the matching finding when a breakdown row is selected", async () => {
    getMetadataHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getMetadataHealthFindings.mockResolvedValue([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-metadata", {
      is: OiHealthMetadata
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const breakdownList = element.shadowRoot.querySelector(
      "c-oi-health-breakdown-list"
    );
    breakdownList.dispatchEvent(
      new CustomEvent("rowselect", { detail: { key: "obj1" } })
    );
    await Promise.resolve();

    const drawer = element.shadowRoot.querySelector(
      "c-oi-health-finding-drawer"
    );
    expect(drawer).not.toBeNull();
    expect(drawer.finding.id).toBe("001aFinding");
    expect(
      element.shadowRoot.querySelector(".oi-health-selection-note")
    ).toBeNull();
  });

  it("switches the drawer to a related finding when the drawer dispatches relatedselect", async () => {
    getMetadataHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getMetadataHealthFindings.mockResolvedValue([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-metadata", {
      is: OiHealthMetadata
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot
      .querySelector("c-oi-health-breakdown-list")
      .dispatchEvent(new CustomEvent("rowselect", { detail: { key: "obj1" } }));
    await Promise.resolve();

    const relatedFinding = {
      ...SAMPLE_FINDING,
      id: "001aRelatedFinding",
      componentKey: "obj2",
      title: "Related_Object__c has an unusually high degree"
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
    expect(drawer.finding.id).toBe("001aRelatedFinding");
    expect(drawer.finding.title).toBe(
      "Related_Object__c has an unusually high degree"
    );
  });

  it("opens the live insight panel with the row's own evidence instead of a dead-end note when no finding is on file yet", async () => {
    getMetadataHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getMetadataHealthFindings.mockResolvedValue([]);
    const element = createElement("c-oi-health-metadata", {
      is: OiHealthMetadata
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const breakdownList = element.shadowRoot.querySelector(
      "c-oi-health-breakdown-list"
    );
    breakdownList.dispatchEvent(
      new CustomEvent("rowselect", {
        detail: { key: "obj1", row: SAMPLE_DETAIL.breakdownRows[0] }
      })
    );
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-oi-health-finding-drawer")
    ).toBeNull();
    const insightPanel = element.shadowRoot.querySelector(
      "c-oi-health-live-insight-panel"
    );
    expect(insightPanel).not.toBeNull();
    expect(insightPanel.row.key).toBe("obj1");
    expect(insightPanel.canSync).toBe(true);
  });

  it("closes the live insight panel when it dispatches close, and forwards its sync event to the same Sync findings action", async () => {
    getMetadataHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getMetadataHealthFindings.mockResolvedValue([]);
    syncMetadataHealthFindings.mockResolvedValue("Synced");
    const element = createElement("c-oi-health-metadata", {
      is: OiHealthMetadata
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot
      .querySelector("c-oi-health-breakdown-list")
      .dispatchEvent(
        new CustomEvent("rowselect", {
          detail: { key: "obj1", row: SAMPLE_DETAIL.breakdownRows[0] }
        })
      );
    await Promise.resolve();

    let insightPanel = element.shadowRoot.querySelector(
      "c-oi-health-live-insight-panel"
    );
    insightPanel.dispatchEvent(new CustomEvent("sync"));
    await flushPromises();
    await Promise.resolve();
    expect(syncMetadataHealthFindings).toHaveBeenCalledTimes(1);

    insightPanel = element.shadowRoot.querySelector(
      "c-oi-health-live-insight-panel"
    );
    insightPanel.dispatchEvent(new CustomEvent("close"));
    await Promise.resolve();
    expect(
      element.shadowRoot.querySelector("c-oi-health-live-insight-panel")
    ).toBeNull();
  });

  it("opens the KPI drilldown modal for the tile's metric key, and closes it when a row inside it is selected", async () => {
    getMetadataHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getMetadataHealthFindings.mockResolvedValue([]);
    getMetadataHealthKpiDrilldown.mockResolvedValue({
      title: "High field-count objects",
      coverageCaption: "1 object",
      metricColumnLabels: ["Fields", "Degree"],
      rows: [SAMPLE_DETAIL.breakdownRows[0]]
    });
    const element = createElement("c-oi-health-metadata", {
      is: OiHealthMetadata
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot
      .querySelector("c-oi-health-kpi-tile")
      .dispatchEvent(
        new CustomEvent("select", { detail: { metricKey: "HighFieldCount" } })
      );
    await Promise.resolve();

    let modal = element.shadowRoot.querySelector(
      "c-oi-health-kpi-drilldown-modal"
    );
    expect(modal).not.toBeNull();
    expect(modal.metricKey).toBe("HighFieldCount");

    modal.dispatchEvent(
      new CustomEvent("rowselect", {
        detail: { key: "obj1", row: SAMPLE_DETAIL.breakdownRows[0] }
      })
    );
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-oi-health-kpi-drilldown-modal")
    ).toBeNull();
    expect(
      element.shadowRoot.querySelector("c-oi-health-live-insight-panel")
    ).not.toBeNull();
  });

  it("renders the glossary panel with plain-English definitions for the terms used on this page", async () => {
    getMetadataHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getMetadataHealthFindings.mockResolvedValue([]);
    const element = createElement("c-oi-health-metadata", {
      is: OiHealthMetadata
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const glossary = element.shadowRoot.querySelector("c-oi-health-glossary");
    expect(glossary).not.toBeNull();
    expect(glossary.terms.length).toBeGreaterThan(0);
    expect(glossary.terms.some((entry) => entry.term === "Degree")).toBe(true);
  });

  it("closes the drawer when the drawer dispatches close", async () => {
    getMetadataHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getMetadataHealthFindings.mockResolvedValue([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-metadata", {
      is: OiHealthMetadata
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot
      .querySelector("c-oi-health-breakdown-list")
      .dispatchEvent(new CustomEvent("rowselect", { detail: { key: "obj1" } }));
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
    getMetadataHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getMetadataHealthFindings.mockResolvedValueOnce([SAMPLE_FINDING]);
    const element = createElement("c-oi-health-metadata", {
      is: OiHealthMetadata
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot
      .querySelector("c-oi-health-breakdown-list")
      .dispatchEvent(new CustomEvent("rowselect", { detail: { key: "obj1" } }));
    await Promise.resolve();

    const updatedFinding = { ...SAMPLE_FINDING, status: "Acknowledged" };
    getMetadataHealthFindings.mockResolvedValueOnce([updatedFinding]);
    element.shadowRoot
      .querySelector("c-oi-health-finding-drawer")
      .dispatchEvent(new CustomEvent("saved"));
    await flushPromises();
    await Promise.resolve();

    expect(getMetadataHealthFindings).toHaveBeenCalledTimes(2);
    expect(
      element.shadowRoot.querySelector("c-oi-health-finding-drawer").finding
        .status
    ).toBe("Acknowledged");
  });

  it("runs a sync and reloads the detail and findings when the Sync findings button is clicked", async () => {
    getMetadataHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getMetadataHealthFindings.mockResolvedValue([]);
    syncMetadataHealthFindings.mockResolvedValue("Synced");
    const element = createElement("c-oi-health-metadata", {
      is: OiHealthMetadata
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    element.shadowRoot.querySelector("button.oi-btn").click();
    await flushPromises();
    await Promise.resolve();

    expect(syncMetadataHealthFindings).toHaveBeenCalledTimes(1);
    expect(getMetadataHealthDetail).toHaveBeenCalledTimes(2);
    expect(getMetadataHealthFindings).toHaveBeenCalledTimes(2);
  });

  it("shows a sync error without losing the currently loaded detail", async () => {
    getMetadataHealthDetail.mockResolvedValue(SAMPLE_DETAIL);
    getMetadataHealthFindings.mockResolvedValue([]);
    syncMetadataHealthFindings.mockRejectedValueOnce({
      body: { message: "You don’t have permission." }
    });
    const element = createElement("c-oi-health-metadata", {
      is: OiHealthMetadata
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
      element.shadowRoot.querySelector("c-oi-health-score-ring")
    ).not.toBeNull();
  });
});
