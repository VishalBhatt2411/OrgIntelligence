import { createElement } from "lwc";
import OiFieldPicker from "c/oiFieldPicker";

const OPTIONS = [
  { label: "Account Name (Account.Name)", value: "Account.Name" },
  { label: "Billing City (Account.BillingCity)", value: "Account.BillingCity" }
];

function createPicker() {
  const element = createElement("c-oi-field-picker", { is: OiFieldPicker });
  element.options = OPTIONS;
  document.body.appendChild(element);
  return element;
}

describe("c-oi-field-picker", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders field labels and API names as separate information levels", () => {
    const element = createPicker();
    const first = element.shadowRoot.querySelector(".oi-field-picker-option");
    expect(first.textContent).toContain("Account Name");
    expect(first.textContent).toContain("Account.Name");
  });

  it("filters locally and emits the selected field value", async () => {
    const element = createPicker();
    const listener = jest.fn();
    element.addEventListener("change", listener);
    const input = element.shadowRoot.querySelector("input");
    input.value = "Billing";
    input.dispatchEvent(new CustomEvent("input"));
    await Promise.resolve();

    const options = element.shadowRoot.querySelectorAll(
      ".oi-field-picker-option"
    );
    expect(options).toHaveLength(1);
    options[0].click();
    expect(listener.mock.calls[0][0].detail.value).toBe("Account.BillingCity");
  });
});
