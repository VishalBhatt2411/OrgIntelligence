import { createElement } from "lwc";
import OiHealthStorage from "c/oiHealthStorage";
import getStorageDetail from "@salesforce/apex/OI_OrgHealthController.getStorageDetail";

jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getStorageDetail",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe("c-oi-health-storage", () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders a loading skeleton — never a state banner — while the Storage request is still in flight", () => {
    getStorageDetail.mockReturnValue(new Promise(() => {}));
    const element = createElement("c-oi-health-storage", {
      is: OiHealthStorage
    });
    document.body.appendChild(element);

    const skeleton = element.shadowRoot.querySelector("c-oi-skeleton");
    expect(skeleton).not.toBeNull();
    expect(skeleton.label).toBe("Loading Storage");
    // A pending request is not one of the five settled states.
    expect(element.shadowRoot.querySelector("c-oi-state-banner")).toBeNull();
  });

  it("renders one KPI tile trio per known limit type and no unavailable-metrics banner when both are present", async () => {
    getStorageDetail.mockResolvedValue({
      dataUsedMb: 6800,
      dataLimitMb: 20000,
      dataRemainingMb: 13200,
      fileUsedMb: 6000,
      fileLimitMb: 50000,
      fileRemainingMb: 44000,
      unavailableMetrics: []
    });
    const element = createElement("c-oi-health-storage", {
      is: OiHealthStorage
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const tiles = element.shadowRoot.querySelectorAll("c-oi-health-kpi-tile");
    expect(tiles.length).toBe(6);
    expect(
      element.shadowRoot.querySelectorAll("c-oi-state-banner").length
    ).toBe(0);
  });

  it("renders the not-obtainable banner listing exactly the unavailable metrics", async () => {
    getStorageDetail.mockResolvedValue({
      dataUsedMb: 6800,
      dataLimitMb: 20000,
      dataRemainingMb: 13200,
      fileUsedMb: null,
      fileLimitMb: null,
      fileRemainingMb: null,
      unavailableMetrics: ["FileStorageMB"]
    });
    const element = createElement("c-oi-health-storage", {
      is: OiHealthStorage
    });
    document.body.appendChild(element);
    await flushPromises();
    await Promise.resolve();

    const banner = element.shadowRoot.querySelector("c-oi-state-banner");
    expect(banner).not.toBeNull();
    expect(banner.message).toContain("FileStorageMB");
    expect(
      element.shadowRoot.querySelectorAll("c-oi-health-kpi-tile").length
    ).toBe(3);
  });

  it("renders the error banner and retries on demand", async () => {
    getStorageDetail.mockRejectedValueOnce({ body: { message: "Denied" } });
    getStorageDetail.mockResolvedValueOnce({
      dataUsedMb: 1,
      dataLimitMb: 2,
      dataRemainingMb: 1,
      fileUsedMb: 1,
      fileLimitMb: 2,
      fileRemainingMb: 1,
      unavailableMetrics: []
    });
    const element = createElement("c-oi-health-storage", {
      is: OiHealthStorage
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
    ).toBe(6);
  });
});
