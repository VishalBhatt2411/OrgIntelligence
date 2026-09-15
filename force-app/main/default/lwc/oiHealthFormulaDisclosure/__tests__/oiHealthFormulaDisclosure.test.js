import { createElement } from "lwc";
import OiHealthFormulaDisclosure from "c/oiHealthFormulaDisclosure";

describe("c-oi-health-formula-disclosure", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders the summary and each formula component", () => {
    const element = createElement("c-oi-health-formula-disclosure", {
      is: OiHealthFormulaDisclosure
    });
    element.summary = "Score = 100 - weighted penalty per threshold breached.";
    element.components = [
      { label: "High field count", detail: "(weight 35%)" },
      { label: "Orphan rate", detail: "(weight 30%)" }
    ];
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      expect(element.shadowRoot.textContent).toContain(
        "Score = 100 - weighted penalty per threshold breached."
      );
      const items = element.shadowRoot.querySelectorAll("li");
      expect(items.length).toBe(2);
      expect(items[0].textContent).toContain("High field count");
      expect(items[0].textContent).toContain("(weight 35%)");
    });
  });

  it("defaults to closed unless isOpenByDefault is set", () => {
    const element = createElement("c-oi-health-formula-disclosure", {
      is: OiHealthFormulaDisclosure
    });
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      expect(element.shadowRoot.querySelector("details").open).toBe(false);
    });
  });
});
