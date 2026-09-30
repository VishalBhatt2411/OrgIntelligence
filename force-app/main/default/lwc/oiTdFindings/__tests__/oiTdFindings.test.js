import { createElement } from "lwc";
import OiTdFindings from "c/oiTdFindings";

const FINDINGS = [
  {
    id: "f1",
    title: "System Administrator grants broad org-wide permissions",
    componentName: "System Administrator",
    componentType: "Profile",
    category: "security",
    severity: "high",
    status: "open"
  },
  {
    id: "f2",
    title: "SOQL query inside a loop in AccountService",
    componentName: "AccountService",
    componentType: "ApexClass",
    category: "code_quality",
    severity: "high",
    status: "open"
  },
  {
    id: "f3",
    title: "Too many flows on Case",
    componentName: "Case",
    componentType: "CustomObject",
    category: "governor_limits",
    severity: "low",
    status: "open"
  }
];

function createFindings() {
  const element = createElement("c-oi-td-findings", { is: OiTdFindings });
  element.findings = FINDINGS;
  document.body.appendChild(element);
  return element;
}

function countText(element) {
  return element.shadowRoot.querySelector(".count").textContent;
}

describe("c-oi-td-findings", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("matches a search against the component type shown on each row", async () => {
    const element = createFindings();
    const input = element.shadowRoot.querySelector("input");
    input.value = "profile";
    input.dispatchEvent(new CustomEvent("input"));
    await Promise.resolve();
    expect(countText(element)).toBe("1 of 3 issues");

    input.value = "accountservice";
    input.dispatchEvent(new CustomEvent("input"));
    await Promise.resolve();
    expect(countText(element)).toBe("1 of 3 issues");

    input.value = "no such thing";
    input.dispatchEvent(new CustomEvent("input"));
    await Promise.resolve();
    expect(countText(element)).toBe("0 of 3 issues");
  });

  it("labels category and severity filters the way the dashboard does", () => {
    const element = createFindings();
    const [categorySelect, severitySelect] =
      element.shadowRoot.querySelectorAll("select");
    const categoryLabels = Array.from(categorySelect.options).map(
      (o) => o.textContent
    );
    expect(categoryLabels).toEqual([
      "All categories",
      "Code Quality",
      "Governor Limits",
      "Security"
    ]);
    const severityLabels = Array.from(severitySelect.options).map(
      (o) => o.textContent
    );
    expect(severityLabels).toContain("High");
    expect(severityLabels).not.toContain("high");
  });
});
