import { createElement } from "lwc";
import OiHealthHeatmapGrid from "c/oiHealthHeatmapGrid";

describe("c-oi-health-heatmap-grid", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders one row label and one severity-classed cell per column", () => {
    const element = createElement("c-oi-health-heatmap-grid", {
      is: OiHealthHeatmapGrid
    });
    element.title = "Signal heatmap";
    element.columnLabels = ["Fields", "Degree"];
    element.rows = [
      {
        rowLabel: "Opportunity",
        cells: [
          { key: "Opportunity-Fields", value: "89", severityKey: "Critical" },
          { key: "Opportunity-Degree", value: "41", severityKey: "Critical" }
        ]
      }
    ];
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      expect(
        element.shadowRoot.querySelector(".oi-health-heatmap-row-label")
          .textContent
      ).toBe("Opportunity");
      const cells = element.shadowRoot.querySelectorAll(
        ".oi-health-heat-cell_critical"
      );
      expect(cells.length).toBe(2);
    });
  });

  it("falls back to the neutral cell class for an unrecognized severity", () => {
    const element = createElement("c-oi-health-heatmap-grid", {
      is: OiHealthHeatmapGrid
    });
    element.columnLabels = ["Orphan"];
    element.rows = [
      {
        rowLabel: "Legacy_Import__c",
        cells: [{ key: "x", value: "Y", severityKey: null }]
      }
    ];
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const cell = element.shadowRoot.querySelector(".oi-health-heat-cell");
      expect(cell.classList.contains("oi-health-heat-cell_good")).toBe(false);
      expect(cell.classList.contains("oi-health-heat-cell_warning")).toBe(
        false
      );
      expect(cell.classList.contains("oi-health-heat-cell_critical")).toBe(
        false
      );
    });
  });
});
