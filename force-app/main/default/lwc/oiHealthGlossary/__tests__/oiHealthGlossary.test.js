import { createElement } from "lwc";
import OiHealthGlossary from "c/oiHealthGlossary";

describe("c-oi-health-glossary", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders nothing when the caller supplies no terms, rather than an empty heading", () => {
    const element = createElement("c-oi-health-glossary", {
      is: OiHealthGlossary
    });
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      expect(
        element.shadowRoot.querySelector(".oi-health-glossary")
      ).toBeNull();
    });
  });

  it("renders every supplied term and definition under the caller-supplied title", () => {
    const element = createElement("c-oi-health-glossary", {
      is: OiHealthGlossary
    });
    element.title = "Terms used on this page";
    element.terms = [
      {
        term: "Degree",
        definition: "How many other objects reference this one."
      },
      {
        term: "Signal heatmap",
        definition: "A grid of the same rows and signals, colored by severity."
      }
    ];
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      expect(element.shadowRoot.querySelector("h3").textContent).toBe(
        "Terms used on this page"
      );
      const entries = element.shadowRoot.querySelectorAll(
        ".oi-health-glossary-entry"
      );
      expect(entries).toHaveLength(2);
      expect(entries[0].querySelector("dt").textContent).toBe("Degree");
      expect(entries[0].querySelector("dd").textContent).toBe(
        "How many other objects reference this one."
      );
      expect(entries[1].querySelector("dt").textContent).toBe("Signal heatmap");
    });
  });
});
