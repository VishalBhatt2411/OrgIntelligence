import { createElement } from "lwc";
import OiHealthScoreRing from "c/oiHealthScoreRing";

describe("c-oi-health-score-ring", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders the rounded score value and a severity-colored value circle", () => {
    const element = createElement("c-oi-health-score-ring", {
      is: OiHealthScoreRing
    });
    element.score = 77.6;
    element.severityKey = "Warning";
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const numEl = element.shadowRoot.querySelector(".oi-health-ring-num");
      expect(numEl.textContent).toBe("78");
      const valueCircle = element.shadowRoot.querySelector(
        ".oi-health-ring-value"
      );
      expect(valueCircle.getAttribute("style")).toContain(
        "--oi-color-severity-warning"
      );
    });
  });

  it("renders the dashed empty state and an em-dash when score is null", () => {
    const element = createElement("c-oi-health-score-ring", {
      is: OiHealthScoreRing
    });
    element.score = null;
    element.severityKey = null;
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const numEl = element.shadowRoot.querySelector(".oi-health-ring-num");
      expect(numEl.textContent).toBe("—");
      const valueCircle = element.shadowRoot.querySelector(
        ".oi-health-ring-value"
      );
      expect(valueCircle.getAttribute("stroke-dasharray")).toBe("3 4");
    });
  });

  it("applies the lg wrapper class when size is lg", () => {
    const element = createElement("c-oi-health-score-ring", {
      is: OiHealthScoreRing
    });
    element.score = 50;
    element.size = "lg";
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      expect(
        element.shadowRoot.querySelector(".oi-health-ring-wrap_lg")
      ).not.toBeNull();
    });
  });
});
