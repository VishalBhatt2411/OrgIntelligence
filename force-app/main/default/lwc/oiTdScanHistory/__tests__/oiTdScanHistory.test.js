import { createElement } from "lwc";
import OiTdScanHistory from "c/oiTdScanHistory";

const ERROR = "The Salesforce API could not be reached";

function mount(scans) {
  const el = createElement("c-oi-td-scan-history", { is: OiTdScanHistory });
  el.scans = scans;
  document.body.appendChild(el);
  return el;
}

function scan(id, failedSections) {
  return {
    id,
    status: "completed",
    startedAt: "2026-09-28T09:14:03.000Z",
    finishedAt: "2026-09-28T09:14:43.000Z",
    overall: 38,
    failedSections
  };
}

describe("c-oi-td-scan-history partial scans", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("flags a completed scan that skipped sections and names them", async () => {
    const el = mount([
      scan("a1", [
        { category: "objects", error: ERROR },
        { category: "lwc", error: ERROR },
        { category: "installed_packages", error: ERROR }
      ])
    ]);
    await Promise.resolve();

    const text = el.shadowRoot.querySelector(".partial-text");
    expect(text.textContent).toBe(
      "Partial scan: couldn't read Objects, LWC, Installed Packages"
    );
    expect(text.title).toBe(ERROR);
    const chips = [...el.shadowRoot.querySelectorAll(".chip")].map((c) =>
      c.textContent.trim()
    );
    expect(chips).toEqual(["Partial", "completed"]);
  });

  it("shows no partial flag when every section succeeded", async () => {
    const el = mount([scan("a2", []), scan("a3", undefined)]);
    await Promise.resolve();
    expect(el.shadowRoot.querySelector(".partial-text")).toBeNull();
    expect(el.shadowRoot.querySelectorAll(".chip")).toHaveLength(2);
  });
});
