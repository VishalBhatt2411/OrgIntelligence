import { createElement } from "lwc";
import OiScanStatusPanel from "c/oiScanStatusPanel";
import startScan from "@salesforce/apex/OI_ScanController.startScan";
import cancelScan from "@salesforce/apex/OI_ScanController.cancelScan";
import getScanHistory from "@salesforce/apex/OI_ScanController.getScanHistory";
import { subscribe, unsubscribe } from "lightning/empApi";

jest.mock(
  "@salesforce/apex/OI_ScanController.startScan",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_ScanController.cancelScan",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_ScanController.getScanHistory",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/empApi",
  () => ({
    subscribe: jest.fn(() =>
      Promise.resolve({ channel: "/event/OI_Scan_Progress__e" })
    ),
    unsubscribe: jest.fn(() => Promise.resolve()),
    onError: jest.fn()
  }),
  { virtual: true }
);

function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe("c-oi-scan-status-panel", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows "No scans yet" when there is no scan history', async () => {
    getScanHistory.mockResolvedValue([]);
    const element = createElement("c-oi-scan-status-panel", {
      is: OiScanStatusPanel
    });
    document.body.appendChild(element);
    await flushPromises();

    const statusEl = element.shadowRoot.querySelector(
      "p.slds-text-heading_small"
    );
    expect(statusEl.textContent).toContain("No scans yet");
    expect(element.shadowRoot.querySelector(".oi-scan-command")).not.toBeNull();
    expect(element.shadowRoot.querySelector("lightning-card")).toBeNull();
  });

  it("renders the most recent scan status on load", async () => {
    getScanHistory.mockResolvedValue([
      { scanRunId: "0Xx000000000001", status: "Completed" }
    ]);
    const element = createElement("c-oi-scan-status-panel", {
      is: OiScanStatusPanel
    });
    document.body.appendChild(element);
    await flushPromises();

    const statusEl = element.shadowRoot.querySelector(
      "p.slds-text-heading_small"
    );
    expect(statusEl.textContent).toContain("Completed");
  });

  it("shows only the Start Scan button when no scan is running", async () => {
    getScanHistory.mockResolvedValue([]);
    const element = createElement("c-oi-scan-status-panel", {
      is: OiScanStatusPanel
    });
    document.body.appendChild(element);
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(
        'lightning-button[data-id="start-scan-button"]'
      )
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelector(
        'lightning-button[data-id="cancel-scan-button"]'
      )
    ).toBeNull();
  });

  it("calls startScan and switches to the Cancel Scan button when Start Scan is clicked", async () => {
    getScanHistory.mockResolvedValue([]);
    startScan.mockResolvedValue({
      scanRunId: "0Xx000000000002",
      status: "Running"
    });
    const element = createElement("c-oi-scan-status-panel", {
      is: OiScanStatusPanel
    });
    document.body.appendChild(element);
    await flushPromises();

    element.shadowRoot
      .querySelector('lightning-button[data-id="start-scan-button"]')
      .click();
    await flushPromises();

    expect(startScan).toHaveBeenCalledWith({
      scanType: "Full",
      metadataTypeOverride: null
    });
    expect(
      element.shadowRoot.querySelector(
        'lightning-button[data-id="cancel-scan-button"]'
      )
    ).not.toBeNull();
  });

  it("calls cancelScan with the current scan run id when Cancel Scan is clicked", async () => {
    getScanHistory.mockResolvedValue([
      { scanRunId: "0Xx000000000003", status: "Running" }
    ]);
    cancelScan.mockResolvedValue();
    const element = createElement("c-oi-scan-status-panel", {
      is: OiScanStatusPanel
    });
    document.body.appendChild(element);
    await flushPromises();

    element.shadowRoot
      .querySelector('lightning-button[data-id="cancel-scan-button"]')
      .click();
    await flushPromises();

    expect(cancelScan).toHaveBeenCalledWith({ scanRunId: "0Xx000000000003" });
  });

  it("subscribes to the OI_Scan_Progress__e channel on connect and unsubscribes on disconnect", async () => {
    getScanHistory.mockResolvedValue([]);
    const element = createElement("c-oi-scan-status-panel", {
      is: OiScanStatusPanel
    });
    document.body.appendChild(element);
    await flushPromises();

    expect(subscribe).toHaveBeenCalledWith(
      "/event/OI_Scan_Progress__e",
      -1,
      expect.any(Function)
    );

    document.body.removeChild(element);
    await flushPromises();

    expect(unsubscribe).toHaveBeenCalled();
  });

  it("updates status from a matching progress event", async () => {
    getScanHistory.mockResolvedValue([
      { scanRunId: "0Xx000000000004", status: "Running" }
    ]);
    const element = createElement("c-oi-scan-status-panel", {
      is: OiScanStatusPanel
    });
    document.body.appendChild(element);
    await flushPromises();

    const subscribeCallback = subscribe.mock.calls[0][2];
    subscribeCallback({
      data: {
        payload: {
          Scan_Run_Id__c: "0Xx000000000004",
          Status__c: "CompletedWithErrors",
          Metadata_Type__c: null,
          Message__c: "Scan completed with errors."
        }
      }
    });
    await flushPromises();

    const statusEl = element.shadowRoot.querySelector(
      "p.slds-text-heading_small"
    );
    expect(statusEl.textContent).toContain("CompletedWithErrors");
  });

  /* Before the first fetch resolves there is no status, so "No scans yet" would be a false claim. */
  it("shows a skeleton instead of a status while the first fetch is still in flight", () => {
    getScanHistory.mockReturnValue(new Promise(() => {}));
    const element = createElement("c-oi-scan-status-panel", {
      is: OiScanStatusPanel
    });
    document.body.appendChild(element);

    expect(
      element.shadowRoot.querySelector('[data-id="status-loading"]')
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelector("p.slds-text-heading_small")
    ).toBeNull();
  });

  /* The disabled button used to be the only feedback that a scan request was in flight. */
  it("shows a busy indication alongside the disabled button while a scan request is in flight", async () => {
    getScanHistory.mockResolvedValue([]);
    startScan.mockReturnValue(new Promise(() => {}));
    const element = createElement("c-oi-scan-status-panel", {
      is: OiScanStatusPanel
    });
    document.body.appendChild(element);
    await flushPromises();

    element.shadowRoot
      .querySelector('lightning-button[data-id="start-scan-button"]')
      .click();
    await flushPromises();

    const busy = element.shadowRoot.querySelector('[data-id="action-busy"]');
    expect(busy.textContent).toBe("Starting scan…");
    expect(
      element.shadowRoot.querySelector(
        'lightning-button[data-id="start-scan-button"]'
      ).disabled
    ).toBe(true);
  });
});
