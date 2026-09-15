import { createElement } from "lwc";
import OiHealthBreakdownList from "c/oiHealthBreakdownList";

describe("c-oi-health-breakdown-list", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders one row per entry with its metric values and severity badge", () => {
    const element = createElement("c-oi-health-breakdown-list", {
      is: OiHealthBreakdownList
    });
    element.title = "Objects needing attention";
    element.coverageCaption = "Top 8 of 14";
    element.metricColumnLabels = ["Fields", "Degree"];
    element.rows = [
      {
        key: "Opportunity",
        primaryLabel: "Opportunity",
        metricValues: [
          { key: "Fields", value: "89" },
          { key: "Degree", value: "41" }
        ],
        severityKey: "Critical",
        severityLabel: "Critical"
      }
    ];
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const rows = element.shadowRoot.querySelectorAll("tbody tr");
      expect(rows.length).toBe(1);
      expect(rows[0].textContent).toContain("Opportunity");
      expect(rows[0].textContent).toContain("89");
      expect(rows[0].textContent).toContain("41");
      expect(
        element.shadowRoot.querySelector("c-oi-health-severity-badge")
      ).not.toBeNull();
    });
  });

  it("renders no table when there are no rows", () => {
    const element = createElement("c-oi-health-breakdown-list", {
      is: OiHealthBreakdownList
    });
    element.rows = [];
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      expect(element.shadowRoot.querySelector("table")).toBeNull();
    });
  });

  it("dispatches rowselect with the row key when clickable and a row is clicked", () => {
    const element = createElement("c-oi-health-breakdown-list", {
      is: OiHealthBreakdownList
    });
    element.clickable = true;
    element.rows = [
      {
        key: "Opportunity",
        primaryLabel: "Opportunity",
        metricValues: [],
        severityKey: "Critical",
        severityLabel: "Critical"
      }
    ];
    document.body.appendChild(element);

    const selectHandler = jest.fn();
    element.addEventListener("rowselect", selectHandler);

    return Promise.resolve().then(() => {
      const row = element.shadowRoot.querySelector("tbody tr");
      expect(row.classList.contains("oi-health-breakdown-row_clickable")).toBe(
        true
      );
      row.click();
      expect(selectHandler).toHaveBeenCalledTimes(1);
      expect(selectHandler.mock.calls[0][0].detail.key).toBe("Opportunity");
    });
  });

  it("also carries the row's own data in rowselect, so a caller can render a detail view without a second lookup", () => {
    const element = createElement("c-oi-health-breakdown-list", {
      is: OiHealthBreakdownList
    });
    element.clickable = true;
    const row = {
      key: "Opportunity",
      primaryLabel: "Opportunity",
      metricValues: [],
      severityKey: "Critical",
      severityLabel: "Critical",
      explanation: "Because reasons."
    };
    element.rows = [row];
    document.body.appendChild(element);

    const selectHandler = jest.fn();
    element.addEventListener("rowselect", selectHandler);

    return Promise.resolve().then(() => {
      element.shadowRoot.querySelector("tbody tr").click();
      expect(selectHandler.mock.calls[0][0].detail.row).toEqual(row);
    });
  });

  it("does not dispatch rowselect when clickable is not set", () => {
    const element = createElement("c-oi-health-breakdown-list", {
      is: OiHealthBreakdownList
    });
    element.rows = [
      {
        key: "Opportunity",
        primaryLabel: "Opportunity",
        metricValues: [],
        severityKey: "Critical",
        severityLabel: "Critical"
      }
    ];
    document.body.appendChild(element);

    const selectHandler = jest.fn();
    element.addEventListener("rowselect", selectHandler);

    return Promise.resolve().then(() => {
      element.shadowRoot.querySelector("tbody tr").click();
      expect(selectHandler).not.toHaveBeenCalled();
    });
  });
});
