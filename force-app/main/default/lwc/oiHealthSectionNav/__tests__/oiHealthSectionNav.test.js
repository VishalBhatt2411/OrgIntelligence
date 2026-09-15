import { createElement } from "lwc";
import OiHealthSectionNav from "c/oiHealthSectionNav";

const SECTIONS = [
  { sectionKey: "OrgOverview", displayLabel: "Overview", severityKey: null },
  {
    sectionKey: "MetadataHealth",
    displayLabel: "Metadata Health",
    severityKey: "Warning"
  }
];

describe("c-oi-health-section-nav", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("marks the active section as aria-selected and the rest as not selected", () => {
    const element = createElement("c-oi-health-section-nav", {
      is: OiHealthSectionNav
    });
    element.sections = SECTIONS;
    element.activeSectionKey = "MetadataHealth";
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const tabs = element.shadowRoot.querySelectorAll('[role="tab"]');
      expect(tabs.length).toBe(2);
      expect(tabs[0].getAttribute("aria-selected")).toBe("false");
      expect(tabs[1].getAttribute("aria-selected")).toBe("true");
    });
  });

  it("dispatches select with the clicked sectionKey", () => {
    const element = createElement("c-oi-health-section-nav", {
      is: OiHealthSectionNav
    });
    element.sections = SECTIONS;
    element.activeSectionKey = "OrgOverview";
    document.body.appendChild(element);
    const handler = jest.fn();
    element.addEventListener("select", handler);

    return Promise.resolve().then(() => {
      element.shadowRoot.querySelectorAll('[role="tab"]')[1].click();
      expect(handler).toHaveBeenCalledTimes(1);
      expect(handler.mock.calls[0][0].detail.sectionKey).toBe("MetadataHealth");
    });
  });
});
