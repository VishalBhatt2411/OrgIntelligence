import { createElement } from "lwc";
import OiHealthLiveInsightPanel from "c/oiHealthLiveInsightPanel";
import getFindingComponentNavigation from "@salesforce/apex/OI_OrgHealthController.getFindingComponentNavigation";
import { navigateToTarget } from "c/metadataNavigation";

jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getFindingComponentNavigation",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("c/metadataNavigation", () => ({
  navigateToTarget: jest.fn()
}));

function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function sampleRow(overrides) {
  return {
    key: "obj1",
    primaryLabel: "Ctl_Object__c",
    metricValues: [
      { key: "fields", value: "92" },
      { key: "degree", value: "4" }
    ],
    severityKey: "Critical",
    severityLabel: "Critical",
    explanation: "92 custom fields — at or above this org's threshold of 60.",
    ...overrides
  };
}

function render(props = {}) {
  const element = createElement("c-oi-health-live-insight-panel", {
    is: OiHealthLiveInsightPanel
  });
  element.row = sampleRow();
  element.metricColumnLabels = ["Fields", "Degree"];
  element.sectionLabel = "Metadata Health";
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

describe("c-oi-health-live-insight-panel", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders the object label, severity, live explanation, and measured metrics — never a dead-end sentence", async () => {
    const element = render();
    await flushPromises();

    expect(element.shadowRoot.querySelector("h2").textContent).toBe(
      "Ctl_Object__c"
    );
    expect(
      element.shadowRoot.querySelector("c-oi-health-severity-badge").severityKey
    ).toBe("Critical");
    expect(element.shadowRoot.textContent).toContain("92 custom fields");
    const metrics = element.shadowRoot.querySelectorAll(
      ".oi-live-insight-metric"
    );
    expect(metrics).toHaveLength(2);
    expect(metrics[0].textContent).toContain("Fields");
    expect(metrics[0].textContent).toContain("92");
  });

  it("resolves and opens the affected object using the row's own key as the componentKey, exactly like the finding drawer does", async () => {
    getFindingComponentNavigation.mockResolvedValue({
      kind: "record",
      recordId: "001x1",
      objectApiName: "Ctl_Object__c"
    });
    navigateToTarget.mockReturnValue({ navigated: true, message: null });
    const element = render();
    await flushPromises();

    element.shadowRoot.querySelector(".oi-btn").click();
    await flushPromises();

    expect(getFindingComponentNavigation).toHaveBeenCalledWith({
      componentKey: "obj1"
    });
    expect(navigateToTarget).toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector(
        '[data-id="live-insight-navigation-error"]'
      )
    ).toBeNull();
  });

  it("surfaces an honest message when the object cannot be opened, rather than a dead click", async () => {
    getFindingComponentNavigation.mockResolvedValue({
      kind: "unsupported",
      reason: "This component type has no dedicated page."
    });
    navigateToTarget.mockReturnValue({
      navigated: false,
      message: "This component type has no dedicated page."
    });
    const element = render();
    await flushPromises();

    element.shadowRoot.querySelector(".oi-btn").click();
    await flushPromises();

    const banner = element.shadowRoot.querySelector(
      '[data-id="live-insight-navigation-error"]'
    );
    expect(banner.state).toBe("error");
    expect(banner.message).toBe("This component type has no dedicated page.");
  });

  it("shows the Sync findings call-to-action only when the caller grants canSync", async () => {
    const withoutSync = render({ canSync: false });
    await flushPromises();
    expect(
      withoutSync.shadowRoot.querySelector(".oi-live-insight-sync")
    ).toBeNull();

    withoutSync.remove();
    const withSync = render({ canSync: true });
    await flushPromises();
    expect(
      withSync.shadowRoot.querySelector(".oi-live-insight-sync")
    ).not.toBeNull();
  });

  it("dispatches sync when the call-to-action is clicked, leaving the sync action itself to the container", async () => {
    const element = render({ canSync: true });
    await flushPromises();
    const handler = jest.fn();
    element.addEventListener("sync", handler);

    element.shadowRoot
      .querySelector(".oi-live-insight-sync .oi-btn_primary")
      .click();

    expect(handler).toHaveBeenCalledTimes(1);
  });

  it("dispatches close on the close button and on Escape", async () => {
    const element = render();
    await flushPromises();
    const handler = jest.fn();
    element.addEventListener("close", handler);

    element.shadowRoot.querySelector(".slds-modal__close").click();
    expect(handler).toHaveBeenCalledTimes(1);

    element.shadowRoot
      .querySelector(".oi-live-insight-panel")
      .dispatchEvent(
        new KeyboardEvent("keydown", { key: "Escape", bubbles: true })
      );
    expect(handler).toHaveBeenCalledTimes(2);
  });
});
