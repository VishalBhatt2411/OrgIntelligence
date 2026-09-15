import { createElement } from "lwc";
import OiHealthKpiDrilldownModal from "c/oiHealthKpiDrilldownModal";
import getMetadataHealthKpiDrilldown from "@salesforce/apex/OI_OrgHealthController.getMetadataHealthKpiDrilldown";

jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getMetadataHealthKpiDrilldown",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function sampleDrilldown() {
  return {
    title: "High field-count objects",
    coverageCaption: "12 objects",
    metricColumnLabels: ["Fields", "Degree"],
    rows: [
      {
        key: "obj1",
        primaryLabel: "Ctl_Object__c",
        metricValues: [
          { key: "fields", value: "92" },
          { key: "degree", value: "4" }
        ],
        severityKey: "Critical",
        severityLabel: "Critical",
        explanation: "92 custom fields — above threshold."
      }
    ]
  };
}

describe("c-oi-health-kpi-drilldown-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("loads and renders the full object list for the given metric key, not just the breakdown table's top-8", async () => {
    getMetadataHealthKpiDrilldown.mockResolvedValue(sampleDrilldown());
    const element = createElement("c-oi-health-kpi-drilldown-modal", {
      is: OiHealthKpiDrilldownModal
    });
    document.body.appendChild(element);
    element.metricKey = "HighFieldCount";
    await flushPromises();

    expect(getMetadataHealthKpiDrilldown).toHaveBeenCalledWith({
      metricKey: "HighFieldCount"
    });
    const list = element.shadowRoot.querySelector("c-oi-health-breakdown-list");
    expect(list.title).toBe("High field-count objects");
    expect(list.rows).toHaveLength(1);
    expect(list.clickable).toBe(true);
  });

  it("shows a skeleton while loading and a retryable error banner on failure", async () => {
    getMetadataHealthKpiDrilldown.mockRejectedValue({
      body: { message: "boom" }
    });
    const element = createElement("c-oi-health-kpi-drilldown-modal", {
      is: OiHealthKpiDrilldownModal
    });
    document.body.appendChild(element);
    element.metricKey = "HighDegree";
    await Promise.resolve();
    expect(element.shadowRoot.querySelector("c-oi-skeleton")).not.toBeNull();

    await flushPromises();

    const banner = element.shadowRoot.querySelector("c-oi-state-banner");
    expect(banner.state).toBe("error");
    expect(banner.message).toBe("boom");
  });

  it("re-emits a row selection from the inner breakdown list as its own rowselect", async () => {
    getMetadataHealthKpiDrilldown.mockResolvedValue(sampleDrilldown());
    const element = createElement("c-oi-health-kpi-drilldown-modal", {
      is: OiHealthKpiDrilldownModal
    });
    document.body.appendChild(element);
    element.metricKey = "HighFieldCount";
    await flushPromises();

    const handler = jest.fn();
    element.addEventListener("rowselect", handler);
    const list = element.shadowRoot.querySelector("c-oi-health-breakdown-list");
    list.dispatchEvent(
      new CustomEvent("rowselect", {
        detail: { key: "obj1", row: sampleDrilldown().rows[0] }
      })
    );

    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail.key).toBe("obj1");
  });

  it("dispatches close on the close button and on Escape", async () => {
    getMetadataHealthKpiDrilldown.mockResolvedValue(sampleDrilldown());
    const element = createElement("c-oi-health-kpi-drilldown-modal", {
      is: OiHealthKpiDrilldownModal
    });
    document.body.appendChild(element);
    element.metricKey = "HighFieldCount";
    await flushPromises();

    const handler = jest.fn();
    element.addEventListener("close", handler);

    element.shadowRoot.querySelector(".slds-modal__close").click();
    expect(handler).toHaveBeenCalledTimes(1);

    element.shadowRoot
      .querySelector(".oi-kpi-drilldown-modal")
      .dispatchEvent(
        new KeyboardEvent("keydown", { key: "Escape", bubbles: true })
      );
    expect(handler).toHaveBeenCalledTimes(2);
  });
});
