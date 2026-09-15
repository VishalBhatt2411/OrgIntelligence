import { createElement } from "lwc";
import OiHealthOverviewGrid from "c/oiHealthOverviewGrid";

const OVERVIEW = {
  objectCount: 187,
  fieldCount: 4362,
  apexClassCount: 612,
  triggerCount: 94,
  flowCount: 156,
  permissionSetCount: 38,
  dependencyCount: 8940,
  relationshipCount: 2103
};

const SECTIONS = [
  {
    sectionKey: "OrgOverview",
    displayLabel: "Org Overview",
    isImplemented: true,
    isScored: false,
    score: null,
    severityKey: null,
    topSignals: [],
    coverageNote: "Last scanned"
  },
  {
    sectionKey: "Storage",
    displayLabel: "Storage",
    isImplemented: true,
    isScored: false,
    score: null,
    severityKey: null,
    topSignals: [{ label: "Data storage used", value: "34% of 20 GB" }],
    coverageNote: "Live org limits."
  },
  {
    sectionKey: "MetadataHealth",
    displayLabel: "Metadata Health",
    isImplemented: false,
    isScored: true,
    score: null,
    severityKey: null,
    topSignals: [],
    coverageNote: "Not yet available in this package version."
  }
];

describe("c-oi-health-overview-grid", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders 8 KPI tiles with locale-formatted values from the overview DTO", () => {
    const element = createElement("c-oi-health-overview-grid", {
      is: OiHealthOverviewGrid
    });
    element.overview = OVERVIEW;
    element.sections = SECTIONS;
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const tiles = element.shadowRoot.querySelectorAll("c-oi-health-kpi-tile");
      expect(tiles.length).toBe(8);
      expect(tiles[1].value).toBe("4,362");
    });
  });

  it("excludes the OrgOverview section from the category grid and renders the rest", () => {
    const element = createElement("c-oi-health-overview-grid", {
      is: OiHealthOverviewGrid
    });
    element.overview = OVERVIEW;
    element.sections = SECTIONS;
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const cards = element.shadowRoot.querySelectorAll("[data-section-key]");
      const keys = Array.from(cards).map((c) => c.dataset.sectionKey);
      expect(keys).not.toContain("OrgOverview");
      expect(keys).toContain("Storage");
      expect(keys).toContain("MetadataHealth");
    });
  });

  it("dispatches selectsection when an implemented card is clicked, but not for a not-yet-available stub card", () => {
    const element = createElement("c-oi-health-overview-grid", {
      is: OiHealthOverviewGrid
    });
    element.overview = OVERVIEW;
    element.sections = SECTIONS;
    document.body.appendChild(element);
    const handler = jest.fn();
    element.addEventListener("selectsection", handler);

    return Promise.resolve().then(() => {
      const storageCard = element.shadowRoot.querySelector(
        '[data-section-key="Storage"]'
      );
      storageCard.click();
      expect(handler).toHaveBeenCalledTimes(1);
      expect(handler.mock.calls[0][0].detail.sectionKey).toBe("Storage");

      const stubCard = element.shadowRoot.querySelector(
        '[data-section-key="MetadataHealth"]'
      );
      stubCard.click();
      expect(handler).toHaveBeenCalledTimes(1);
    });
  });

  it("never renders a severity badge for an implemented section with a null severityKey", () => {
    const element = createElement("c-oi-health-overview-grid", {
      is: OiHealthOverviewGrid
    });
    element.overview = OVERVIEW;
    element.sections = SECTIONS;
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const storageCard = element.shadowRoot.querySelector(
        '[data-section-key="Storage"]'
      );
      expect(
        storageCard.querySelector("c-oi-health-severity-badge[severity-key]")
      ).toBeNull();
    });
  });
});
