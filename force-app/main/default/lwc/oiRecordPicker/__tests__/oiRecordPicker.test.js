import { createElement } from "lwc";
import OiRecordPicker from "c/oiRecordPicker";
import searchRecords from "@salesforce/apex/OI_RecordSearchController.searchRecords";
import browseRecords from "@salesforce/apex/OI_RecordSearchController.browseRecords";

jest.mock(
  "@salesforce/apex/OI_RecordSearchController.searchRecords",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_RecordSearchController.browseRecords",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function flushPromises() {
  return Promise.resolve().then(() => Promise.resolve());
}

describe("c-oi-record-picker", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  beforeEach(() => {
    searchRecords.mockReset();
    browseRecords.mockReset();
    browseRecords.mockResolvedValue([]);
  });

  it("debounces the typed term and calls OI_RecordSearchController.searchRecords scoped to the given object", async () => {
    searchRecords.mockResolvedValue([
      { recordId: "001x1", label: "Acme Corp", objectApiName: "Account" }
    ]);
    const element = createElement("c-oi-record-picker", { is: OiRecordPicker });
    element.objectApiName = "Account";
    document.body.appendChild(element);

    const input = element.shadowRoot.querySelector("lightning-input");
    input.value = "Acme";
    input.dispatchEvent(new CustomEvent("change"));

    await wait(400);

    expect(searchRecords).toHaveBeenCalledWith({
      objectApiName: "Account",
      queryTerm: "Acme"
    });
  });

  it("never calls search for a blank query", async () => {
    const element = createElement("c-oi-record-picker", { is: OiRecordPicker });
    element.objectApiName = "Account";
    document.body.appendChild(element);

    const input = element.shadowRoot.querySelector("lightning-input");
    input.value = "   ";
    input.dispatchEvent(new CustomEvent("change"));
    await wait(400);

    expect(searchRecords).not.toHaveBeenCalled();
  });

  it("renders results and dispatches select with the clicked recordId, then clears the result list", async () => {
    searchRecords.mockResolvedValue([
      { recordId: "001x1", label: "Acme Corp", objectApiName: "Account" }
    ]);
    const element = createElement("c-oi-record-picker", { is: OiRecordPicker });
    element.objectApiName = "Account";
    document.body.appendChild(element);
    const handler = jest.fn();
    element.addEventListener("select", handler);

    const input = element.shadowRoot.querySelector("lightning-input");
    input.value = "Acme";
    input.dispatchEvent(new CustomEvent("change"));
    await wait(400);

    const resultButton = element.shadowRoot.querySelector(
      '[data-id="search-result-item"]'
    );
    expect(resultButton).not.toBeNull();
    expect(
      resultButton.querySelector(".oi-combobox-option-label").textContent.trim()
    ).toBe("Acme Corp");
    resultButton.click();

    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail.recordId).toBe("001x1");
    expect(handler.mock.calls[0][0].detail.label).toBe("Acme Corp");

    return Promise.resolve().then(() => {
      expect(
        element.shadowRoot.querySelector('[data-id="search-results"]')
      ).toBeNull();
    });
  });

  it("the Search button triggers search immediately, without waiting for the debounce", async () => {
    searchRecords.mockResolvedValue([
      { recordId: "001x1", label: "Acme Corp", objectApiName: "Account" }
    ]);
    const element = createElement("c-oi-record-picker", { is: OiRecordPicker });
    element.objectApiName = "Account";
    document.body.appendChild(element);

    const input = element.shadowRoot.querySelector("lightning-input");
    input.value = "Acme";
    input.dispatchEvent(new CustomEvent("change"));

    element.shadowRoot.querySelector('[data-id="search-button"]').click();
    await Promise.resolve();
    await Promise.resolve();

    expect(searchRecords).toHaveBeenCalledWith({
      objectApiName: "Account",
      queryTerm: "Acme"
    });
  });

  it("renders a sanitized error banner when the search call fails, instead of failing silently", async () => {
    searchRecords.mockRejectedValue({
      body: { message: "You don't have permission to search records." }
    });
    const element = createElement("c-oi-record-picker", { is: OiRecordPicker });
    element.objectApiName = "Account";
    document.body.appendChild(element);

    const input = element.shadowRoot.querySelector("lightning-input");
    input.value = "Acme";
    input.dispatchEvent(new CustomEvent("change"));
    await wait(400);

    const errorEl = element.shadowRoot.querySelector(
      '[data-id="search-error"]'
    );
    expect(errorEl).not.toBeNull();
    expect(errorEl.textContent).toContain("permission");
    expect(
      element.shadowRoot.querySelector('[data-id="search-results"]')
    ).toBeNull();
  });

  it("shows a loading spinner while the search is in flight", async () => {
    let resolveSearch;
    searchRecords.mockReturnValue(
      new Promise((resolve) => {
        resolveSearch = resolve;
      })
    );
    const element = createElement("c-oi-record-picker", { is: OiRecordPicker });
    element.objectApiName = "Account";
    document.body.appendChild(element);

    const input = element.shadowRoot.querySelector("lightning-input");
    input.value = "Acme";
    input.dispatchEvent(new CustomEvent("change"));
    await wait(400);

    expect(
      element.shadowRoot.querySelector('[data-id="search-loading"]')
    ).not.toBeNull();

    resolveSearch([]);
    await Promise.resolve();
    await Promise.resolve();
  });

  it("focusing an empty box loads and shows the bounded alphabetical browse list for the current object", async () => {
    browseRecords.mockResolvedValue([
      { recordId: "001x1", label: "Acme Corp", objectApiName: "Account" },
      { recordId: "001x2", label: "Zenith Inc", objectApiName: "Account" }
    ]);
    const element = createElement("c-oi-record-picker", { is: OiRecordPicker });
    element.objectApiName = "Account";
    document.body.appendChild(element);

    const input = element.shadowRoot.querySelector("lightning-input");
    input.dispatchEvent(new CustomEvent("focus"));
    await flushPromises();

    expect(browseRecords).toHaveBeenCalledWith({ objectApiName: "Account" });
    const results = element.shadowRoot.querySelectorAll(
      '[data-id="search-result-item"]'
    );
    expect(results).toHaveLength(2);
    expect(
      results[0].querySelector(".oi-combobox-option-label").textContent.trim()
    ).toBe("Acme Corp");
  });

  it("never shows the browse list before the box is focused, and hides it again on blur", async () => {
    browseRecords.mockResolvedValue([
      { recordId: "001x1", label: "Acme Corp", objectApiName: "Account" }
    ]);
    const element = createElement("c-oi-record-picker", { is: OiRecordPicker });
    element.objectApiName = "Account";
    document.body.appendChild(element);

    expect(
      element.shadowRoot.querySelector('[data-id="search-results"]')
    ).toBeNull();

    const input = element.shadowRoot.querySelector("lightning-input");
    input.dispatchEvent(new CustomEvent("focus"));
    await flushPromises();
    expect(
      element.shadowRoot.querySelector('[data-id="search-results"]')
    ).not.toBeNull();

    input.dispatchEvent(new CustomEvent("blur"));
    await wait(200);
    expect(
      element.shadowRoot.querySelector('[data-id="search-results"]')
    ).toBeNull();
  });

  it("typing instantly filters the already-loaded browse list client-side, ahead of the debounced server search", async () => {
    browseRecords.mockResolvedValue([
      { recordId: "001x1", label: "Acme Corp", objectApiName: "Account" },
      { recordId: "001x2", label: "Zenith Inc", objectApiName: "Account" }
    ]);
    searchRecords.mockResolvedValue([]);
    const element = createElement("c-oi-record-picker", { is: OiRecordPicker });
    element.objectApiName = "Account";
    document.body.appendChild(element);

    const input = element.shadowRoot.querySelector("lightning-input");
    input.dispatchEvent(new CustomEvent("focus"));
    await flushPromises();

    input.value = "Acme";
    input.dispatchEvent(new CustomEvent("change"));
    await flushPromises();

    const results = element.shadowRoot.querySelectorAll(
      '[data-id="search-result-item"]'
    );
    expect(results).toHaveLength(1);
    expect(
      results[0].querySelector(".oi-combobox-option-label").textContent.trim()
    ).toBe("Acme Corp");
  });
});
