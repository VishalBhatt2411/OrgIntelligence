import { createElement } from "lwc";
import OiHealthFindingDrawer from "c/oiHealthFindingDrawer";
import updateFindingStatus from "@salesforce/apex/OI_OrgHealthController.updateFindingStatus";
import getRelatedFindings from "@salesforce/apex/OI_OrgHealthController.getRelatedFindings";
import getFindingComponentNavigation from "@salesforce/apex/OI_OrgHealthController.getFindingComponentNavigation";
import getFindingHistory from "@salesforce/apex/OI_OrgHealthController.getFindingHistory";
import { navigateToTarget } from "c/metadataNavigation";

jest.mock(
  "@salesforce/apex/OI_OrgHealthController.updateFindingStatus",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getRelatedFindings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getFindingComponentNavigation",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_OrgHealthController.getFindingHistory",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/OI_Manage_Finding_Workflow",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock("c/metadataNavigation", () => ({
  navigateToTarget: jest.fn()
}));

function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

const SAMPLE_FINDING = {
  id: "001aFinding",
  sectionKey: "MetadataHealth",
  ruleId: "MetadataHealth.HighFieldCount",
  title: "Ctl_Finding_Object__c has an unusually high field count",
  severityKey: "Critical",
  componentKey: "ctlFind1",
  componentLabel: "Ctl_Finding_Object__c",
  evidence: "100 fields detected, threshold is 60.",
  measuredValue: "100 fields",
  expectedValue: "< 60 fields",
  explanation: "A high field count increases maintenance burden.",
  orgRisk: "This object may be difficult to govern.",
  potentialImpact: "Slower page loads and harder onboarding.",
  remediation: "Review field usage and archive unused fields.",
  validationSteps: "Re-run Metadata Health after cleanup.",
  firstDetected: "2026-08-01T10:00:00.000Z",
  lastDetected: "2026-08-31T10:00:00.000Z",
  status: "Open",
  ownerId: "005aOwner",
  ownerName: "Jordan Admin",
  dueDate: null,
  notes: null,
  compensatingControl: null,
  score: 78.3,
  scoreExplanation: "Weighted by field-count magnitude and confidence.",
  scoreContributors: [
    {
      label: "High field count",
      magnitude: 1.2,
      confidence: 0.9,
      contribution: 42,
      hasCompensatingControl: false,
      wasCorrelatedOut: false
    }
  ],
  resolvedDate: null,
  riskAcceptanceExpiry: null,
  isRiskAcceptanceExpired: false,
  falsePositiveJustification: null
};

describe("c-oi-health-finding-drawer", () => {
  beforeEach(() => {
    getRelatedFindings.mockResolvedValue([]);
    getFindingHistory.mockResolvedValue([]);
  });

  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders nothing when no finding is provided", () => {
    const element = createElement("c-oi-health-finding-drawer", {
      is: OiHealthFindingDrawer
    });
    document.body.appendChild(element);

    expect(element.shadowRoot.querySelector("section")).toBeNull();
  });

  it("renders the finding evidence, explanation, remediation, and metadata from a real DTO", async () => {
    const element = createElement("c-oi-health-finding-drawer", {
      is: OiHealthFindingDrawer
    });
    element.finding = SAMPLE_FINDING;
    document.body.appendChild(element);
    await flushPromises();

    expect(element.shadowRoot.querySelector("h2").textContent).toBe(
      SAMPLE_FINDING.title
    );
    const body = element.shadowRoot.querySelector(
      ".oi-finding-drawer-body"
    ).textContent;
    expect(body).toContain("100 fields detected, threshold is 60.");
    expect(body).toContain("A high field count increases maintenance burden.");
    expect(body).toContain("Review field usage and archive unused fields.");
    expect(body).toContain("Jordan Admin");
  });

  it("renders the severity score as plain text with its contributor breakdown, not a health-equivalent ring", async () => {
    const element = createElement("c-oi-health-finding-drawer", {
      is: OiHealthFindingDrawer
    });
    element.finding = SAMPLE_FINDING;
    document.body.appendChild(element);
    await flushPromises();

    expect(element.shadowRoot.querySelector("oi-health-score-ring")).toBeNull();
    const body = element.shadowRoot.querySelector(
      ".oi-finding-drawer-body"
    ).textContent;
    expect(body).toContain("78.3");
    const disclosure = element.shadowRoot.querySelector(
      "c-oi-health-formula-disclosure"
    );
    expect(disclosure).not.toBeNull();
    expect(disclosure.components).toEqual([
      {
        label: "High field count",
        detail: "(42 pts, magnitude 1.2, confidence 0.9)"
      }
    ]);
  });

  it("pre-populates the triage form from the finding and saves an edit via updateFindingStatus", async () => {
    updateFindingStatus.mockResolvedValue();
    const element = createElement("c-oi-health-finding-drawer", {
      is: OiHealthFindingDrawer
    });
    element.finding = SAMPLE_FINDING;
    document.body.appendChild(element);
    await flushPromises();

    const combobox = element.shadowRoot.querySelector("lightning-combobox");
    expect(combobox.value).toBe("Open");

    const savedHandler = jest.fn();
    element.addEventListener("saved", savedHandler);

    const textareas = element.shadowRoot.querySelectorAll("lightning-textarea");
    textareas[0].value = "Reviewed with the object owner.";
    textareas[0].dispatchEvent(new CustomEvent("change", { detail: {} }));

    element.shadowRoot.querySelector("button.oi-btn_primary").click();
    await flushPromises();

    expect(updateFindingStatus).toHaveBeenCalledWith({
      findingId: "001aFinding",
      status: "Open",
      notes: "Reviewed with the object owner.",
      dueDate: null,
      ownerId: "005aOwner",
      compensatingControl: "",
      riskAcceptanceExpiry: null,
      falsePositiveJustification: null
    });
    expect(savedHandler).toHaveBeenCalledTimes(1);
  });

  it("reassigns the owner via the record picker and saves the new owner id", async () => {
    updateFindingStatus.mockResolvedValue();
    const element = createElement("c-oi-health-finding-drawer", {
      is: OiHealthFindingDrawer
    });
    element.finding = SAMPLE_FINDING;
    document.body.appendChild(element);
    await flushPromises();

    const picker = element.shadowRoot.querySelector("lightning-record-picker");
    expect(picker).not.toBeNull();
    picker.dispatchEvent(
      new CustomEvent("change", { detail: { recordId: "005aNewOwner" } })
    );

    element.shadowRoot.querySelector("button.oi-btn_primary").click();
    await flushPromises();

    expect(updateFindingStatus).toHaveBeenCalledWith(
      expect.objectContaining({ ownerId: "005aNewOwner" })
    );
  });

  it("only shows the risk-acceptance-expiry input once the draft status is set to Risk Accepted", async () => {
    const element = createElement("c-oi-health-finding-drawer", {
      is: OiHealthFindingDrawer
    });
    element.finding = SAMPLE_FINDING;
    document.body.appendChild(element);
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(
        'lightning-input[data-field="riskAcceptanceExpiry"]'
      )
    ).toBeNull();

    const combobox = element.shadowRoot.querySelector("lightning-combobox");
    combobox.value = "Risk Accepted";
    combobox.dispatchEvent(new CustomEvent("change", { detail: {} }));
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(
        'lightning-input[data-field="riskAcceptanceExpiry"]'
      )
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelector(
        'lightning-textarea[data-field="falsePositiveJustification"]'
      )
    ).toBeNull();
  });

  it("only shows the false-positive-justification field once the draft status is set to False Positive", async () => {
    const element = createElement("c-oi-health-finding-drawer", {
      is: OiHealthFindingDrawer
    });
    element.finding = SAMPLE_FINDING;
    document.body.appendChild(element);
    await flushPromises();

    const combobox = element.shadowRoot.querySelector("lightning-combobox");
    combobox.value = "False Positive";
    combobox.dispatchEvent(new CustomEvent("change", { detail: {} }));
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(
        'lightning-textarea[data-field="falsePositiveJustification"]'
      )
    ).not.toBeNull();
  });

  it("shows a save error instead of the success message when updateFindingStatus rejects", async () => {
    updateFindingStatus.mockRejectedValueOnce({
      body: { message: "Access denied." }
    });
    const element = createElement("c-oi-health-finding-drawer", {
      is: OiHealthFindingDrawer
    });
    element.finding = SAMPLE_FINDING;
    document.body.appendChild(element);
    await flushPromises();

    element.shadowRoot.querySelector("button.oi-btn_primary").click();
    await flushPromises();

    const saveBanner = element.shadowRoot.querySelector(
      'c-oi-state-banner[data-id="save-error"]'
    );
    expect(saveBanner).not.toBeNull();
    expect(saveBanner.state).toBe("error");
    expect(saveBanner.message).toBe("Access denied.");
    expect(
      element.shadowRoot.querySelector(".oi-finding-drawer-success")
    ).toBeNull();
  });

  it("dispatches close when the close button or Escape key is used", async () => {
    const element = createElement("c-oi-health-finding-drawer", {
      is: OiHealthFindingDrawer
    });
    element.finding = SAMPLE_FINDING;
    document.body.appendChild(element);
    await flushPromises();

    const closeHandler = jest.fn();
    element.addEventListener("close", closeHandler);

    element.shadowRoot.querySelector(".slds-modal__close").click();
    expect(closeHandler).toHaveBeenCalledTimes(1);

    element.shadowRoot
      .querySelector("section")
      .dispatchEvent(
        new KeyboardEvent("keydown", { key: "Escape", bubbles: true })
      );
    expect(closeHandler).toHaveBeenCalledTimes(2);
  });

  it("loads related findings for the component and lets the user select one", async () => {
    const related = {
      id: "001aRelated",
      title: "A related finding on the same component",
      severityKey: "Warning"
    };
    getRelatedFindings.mockResolvedValue([related]);

    const element = createElement("c-oi-health-finding-drawer", {
      is: OiHealthFindingDrawer
    });
    element.finding = SAMPLE_FINDING;
    document.body.appendChild(element);
    await flushPromises();

    expect(getRelatedFindings).toHaveBeenCalledWith({
      componentKey: "ctlFind1",
      excludeFindingId: "001aFinding"
    });

    const relatedSelectHandler = jest.fn();
    element.addEventListener("relatedselect", relatedSelectHandler);

    const relatedButton = element.shadowRoot.querySelector(
      ".oi-finding-drawer-related-item"
    );
    expect(relatedButton.textContent).toContain(
      "A related finding on the same component"
    );
    relatedButton.click();

    expect(relatedSelectHandler).toHaveBeenCalledTimes(1);
    expect(relatedSelectHandler.mock.calls[0][0].detail.finding).toEqual(
      related
    );
  });

  it("shows an honest inline message when related findings fail to load, without blocking the rest of the drawer", async () => {
    getRelatedFindings.mockRejectedValue({
      body: { message: "Related lookup failed." }
    });

    const element = createElement("c-oi-health-finding-drawer", {
      is: OiHealthFindingDrawer
    });
    element.finding = SAMPLE_FINDING;
    document.body.appendChild(element);
    await flushPromises();

    const relatedBanner = element.shadowRoot.querySelector(
      'c-oi-state-banner[data-id="related-findings-error"]'
    );
    expect(relatedBanner).not.toBeNull();
    expect(relatedBanner.state).toBe("error");
    expect(relatedBanner.message).toBe("Related lookup failed.");
    // A failed lookup is not a confirmed zero, so the true-zero banner must stay off screen.
    expect(
      element.shadowRoot.querySelector(
        'c-oi-state-banner[data-id="related-findings-empty"]'
      )
    ).toBeNull();
    expect(element.shadowRoot.querySelector("h2").textContent).toBe(
      SAMPLE_FINDING.title
    );
  });

  it("loads and renders the finding audit history", async () => {
    getFindingHistory.mockResolvedValue([
      {
        fieldLabel: "Status",
        oldValue: "Open",
        newValue: "Acknowledged",
        changedDate: "2026-08-20T09:00:00.000Z",
        changedByName: "Jordan Admin"
      }
    ]);

    const element = createElement("c-oi-health-finding-drawer", {
      is: OiHealthFindingDrawer
    });
    element.finding = SAMPLE_FINDING;
    document.body.appendChild(element);
    await flushPromises();

    expect(getFindingHistory).toHaveBeenCalledWith({
      findingId: "001aFinding"
    });
    const historyText = element.shadowRoot.querySelector(
      ".oi-finding-drawer-history-list"
    ).textContent;
    expect(historyText).toContain("Status");
    expect(historyText).toContain("Jordan Admin");
    expect(historyText).toContain("Open");
    expect(historyText).toContain("Acknowledged");
  });

  it("refreshes history after a successful save so the new change appears in the audit trail", async () => {
    updateFindingStatus.mockResolvedValue();
    getFindingHistory.mockResolvedValueOnce([]).mockResolvedValueOnce([
      {
        fieldLabel: "Status",
        oldValue: "Open",
        newValue: "Acknowledged",
        changedDate: "2026-08-20T09:00:00.000Z",
        changedByName: "Jordan Admin"
      }
    ]);

    const element = createElement("c-oi-health-finding-drawer", {
      is: OiHealthFindingDrawer
    });
    element.finding = SAMPLE_FINDING;
    document.body.appendChild(element);
    await flushPromises();

    element.shadowRoot.querySelector("button.oi-btn_primary").click();
    await flushPromises();

    expect(getFindingHistory).toHaveBeenCalledTimes(2);
    expect(
      element.shadowRoot.querySelector(".oi-finding-drawer-history-list")
        .textContent
    ).toContain("Acknowledged");
  });

  it('resolves and navigates to the affected component when "Open affected component" is clicked', async () => {
    getFindingComponentNavigation.mockResolvedValue({
      kind: "record",
      recordId: "001aRecord",
      objectApiName: "Ctl_Finding_Object__c"
    });
    navigateToTarget.mockReturnValue({ navigated: true, message: null });

    const element = createElement("c-oi-health-finding-drawer", {
      is: OiHealthFindingDrawer
    });
    element.finding = SAMPLE_FINDING;
    document.body.appendChild(element);
    await flushPromises();

    const openButton = Array.from(
      element.shadowRoot.querySelectorAll("button")
    ).find((btn) => btn.textContent === "Open affected component");
    openButton.click();
    await flushPromises();

    expect(getFindingComponentNavigation).toHaveBeenCalledWith({
      componentKey: "ctlFind1"
    });
    expect(navigateToTarget).toHaveBeenCalledWith(
      expect.any(OiHealthFindingDrawer),
      {
        kind: "record",
        recordId: "001aRecord",
        objectApiName: "Ctl_Finding_Object__c"
      }
    );
    expect(
      element.shadowRoot.querySelector(
        'c-oi-state-banner[data-id="navigation-error"]'
      )
    ).toBeNull();
  });

  it("shows the navigation caveat message when the component cannot be opened directly", async () => {
    getFindingComponentNavigation.mockResolvedValue({
      kind: "unsupported",
      reason: "This component type has no dedicated page."
    });
    navigateToTarget.mockReturnValue({
      navigated: false,
      message: "This component type has no dedicated page."
    });

    const element = createElement("c-oi-health-finding-drawer", {
      is: OiHealthFindingDrawer
    });
    element.finding = SAMPLE_FINDING;
    document.body.appendChild(element);
    await flushPromises();

    const openButton = Array.from(
      element.shadowRoot.querySelectorAll("button")
    ).find((btn) => btn.textContent === "Open affected component");
    openButton.click();
    await flushPromises();

    const navBanner = element.shadowRoot.querySelector(
      'c-oi-state-banner[data-id="navigation-error"]'
    );
    expect(navBanner).not.toBeNull();
    expect(navBanner.message).toBe(
      "This component type has no dedicated page."
    );
    expect(navBanner.state).toBe("error");
  });

  it("reports a finding with no component as not obtainable, so no Retry is offered for a guard that can never pass", async () => {
    const element = createElement("c-oi-health-finding-drawer", {
      is: OiHealthFindingDrawer
    });
    element.finding = { ...SAMPLE_FINDING, componentKey: null };
    document.body.appendChild(element);
    await flushPromises();

    const openButton = Array.from(
      element.shadowRoot.querySelectorAll("button")
    ).find((btn) => btn.textContent === "Open affected component");
    openButton.click();
    await flushPromises();

    const navBanner = element.shadowRoot.querySelector(
      'c-oi-state-banner[data-id="navigation-error"]'
    );
    expect(navBanner.state).toBe("not-obtainable");
    expect(getFindingComponentNavigation).not.toHaveBeenCalled();
  });
});
