import { createElement } from "lwc";
import OiHealthSeverityBadge from "c/oiHealthSeverityBadge";

describe("c-oi-health-severity-badge", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders the recognized severity class and label", () => {
    const element = createElement("c-oi-health-severity-badge", {
      is: OiHealthSeverityBadge
    });
    element.severityKey = "Warning";
    element.label = "Warning";
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const badge = element.shadowRoot.querySelector(
        ".oi-health-severity-badge_warning"
      );
      expect(badge).not.toBeNull();
      expect(badge.textContent).toContain("Warning");
    });
  });

  it("falls back to the neutral class for an unrecognized severityKey", () => {
    const element = createElement("c-oi-health-severity-badge", {
      is: OiHealthSeverityBadge
    });
    element.severityKey = "SomethingUnknown";
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      expect(
        element.shadowRoot.querySelector(".oi-health-severity-badge_neutral")
      ).not.toBeNull();
    });
  });

  it("renders the dashed facts-only pill instead of a severity pill when factsOnly is true", () => {
    const element = createElement("c-oi-health-severity-badge", {
      is: OiHealthSeverityBadge
    });
    element.factsOnly = true;
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      expect(
        element.shadowRoot.querySelector(".oi-health-facts-badge")
      ).not.toBeNull();
      expect(
        element.shadowRoot.querySelector(".oi-health-severity-badge")
      ).toBeNull();
    });
  });
});
