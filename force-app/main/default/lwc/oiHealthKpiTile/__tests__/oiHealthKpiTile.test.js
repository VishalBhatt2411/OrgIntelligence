import { createElement } from "lwc";
import OiHealthKpiTile from "c/oiHealthKpiTile";

describe("c-oi-health-kpi-tile", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders the label and value", () => {
    const element = createElement("c-oi-health-kpi-tile", {
      is: OiHealthKpiTile
    });
    element.label = "Objects";
    element.value = "187";
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      expect(
        element.shadowRoot.querySelector(".oi-health-kpi-eyebrow").textContent
      ).toBe("Objects");
      expect(
        element.shadowRoot.querySelector(".oi-health-kpi-value").textContent
      ).toBe("187");
    });
  });

  it("stays a plain, non-interactive tile when no metricKey is supplied, so every existing caller is unaffected", () => {
    const element = createElement("c-oi-health-kpi-tile", {
      is: OiHealthKpiTile
    });
    element.label = "Objects";
    element.value = "187";
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const tile = element.shadowRoot.querySelector(".oi-health-kpi-tile");
      expect(tile.getAttribute("role")).toBeNull();
      expect(tile.getAttribute("tabindex")).toBeNull();
      expect(tile.className).not.toContain("oi-health-kpi-tile_clickable");
    });
  });

  it("becomes an interactive button and dispatches select with its metricKey on click, when a metricKey is supplied", () => {
    const element = createElement("c-oi-health-kpi-tile", {
      is: OiHealthKpiTile
    });
    element.label = "High field-count objects";
    element.value = "12";
    element.metricKey = "HighFieldCount";
    const handler = jest.fn();
    element.addEventListener("select", handler);
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const tile = element.shadowRoot.querySelector(".oi-health-kpi-tile");
      expect(tile.getAttribute("role")).toBe("button");
      expect(tile.getAttribute("tabindex")).toBe("0");
      expect(tile.className).toContain("oi-health-kpi-tile_clickable");

      tile.click();

      expect(handler).toHaveBeenCalledTimes(1);
      expect(handler.mock.calls[0][0].detail).toEqual({
        metricKey: "HighFieldCount"
      });
    });
  });

  it("also activates on Enter and Space, so a keyboard user can open the drill-down without a mouse", () => {
    const element = createElement("c-oi-health-kpi-tile", {
      is: OiHealthKpiTile
    });
    element.metricKey = "HighDegree";
    const handler = jest.fn();
    element.addEventListener("select", handler);
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const tile = element.shadowRoot.querySelector(".oi-health-kpi-tile");
      tile.dispatchEvent(
        new KeyboardEvent("keydown", { key: "Enter", bubbles: true })
      );
      tile.dispatchEvent(
        new KeyboardEvent("keydown", { key: " ", bubbles: true })
      );

      expect(handler).toHaveBeenCalledTimes(2);
    });
  });
});
