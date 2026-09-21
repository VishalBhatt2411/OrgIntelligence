import { createElement } from "lwc";
import OiNodeDetailPanel from "c/oiNodeDetailPanel";
import getNodeDetail from "@salesforce/apex/OI_GraphController.getNodeDetail";
import getFieldSummaries from "@salesforce/apex/OI_GraphController.getFieldSummaries";
import getRelationshipFieldDetail from "@salesforce/apex/OI_GraphController.getRelationshipFieldDetail";
import getObjectSharingSettings from "@salesforce/apex/OI_GraphController.getObjectSharingSettings";
import getRecordFragment from "@salesforce/apex/OI_RecordHierarchyController.getRecordFragment";
import getRecordSharing from "@salesforce/apex/OI_RecordHierarchyController.getRecordSharing";
import getImpact from "@salesforce/apex/OI_DependencyController.getImpact";
import getNodeIntelligence from "@salesforce/apex/OI_GraphController.getNodeIntelligence";

jest.mock(
  "@salesforce/apex/OI_GraphController.getNodeDetail",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_GraphController.getFieldSummaries",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_GraphController.getRelationshipFieldDetail",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_GraphController.getObjectSharingSettings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_RecordHierarchyController.getRecordFragment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_RecordHierarchyController.getRecordSharing",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_DependencyController.getImpact",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_GraphController.getNodeIntelligence",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

/**
 * Fields/Automation/Code/Security/Impact all start collapsed by default (DEFAULT_COLLAPSED_SECTIONS
 * in oiNodeDetailPanel.js) — this clicks the given section's header toggle (data-section="fields" /
 * "Automation" / "Code" / "Security" / "impact") and waits for the resulting re-render, so tests that
 * only care about a section's expanded content don't have to repeat the click/flush pair inline.
 */
async function expandSection(element, section) {
  element.shadowRoot.querySelector(`[data-section="${section}"]`).click();
  await flushPromises();
}

/**
 * Every Automation/Code/Security item now sits behind two disclosures: the section itself, then
 * the per-type group ("Apex Trigger — 3") within it — a type group is a count until this click
 * opens the list behind it (the feature this rebuild adds). Opens the first type-group header
 * found inside the given category's section, which is sufficient for fixtures with exactly one
 * type in that category; tests with more than one type group open each by index instead.
 */
async function expandFirstTypeGroup(element, category) {
  const section = element.shadowRoot.querySelector(
    `[data-category="${category}"]`
  );
  section.querySelector('[data-id="intelligence-type-group-toggle"]').click();
  await flushPromises();
}

function objectDetail(overrides) {
  return {
    nodeKey: "account",
    typeKey: "SalesforceMetadata.CustomObject",
    label: "Account",
    secondaryKey: "Account",
    attributes: { custom: false },
    outgoingRelationshipCounts: { "SalesforceMetadata.HAS_FIELD": 2 },
    incomingRelationshipCounts: {},
    directConnectionCount: 2,
    ...overrides
  };
}

describe("c-oi-node-detail-panel", () => {
  beforeEach(() => {
    /** Intelligence loads automatically on selection, so every test needs it stubbed or the panel logs an unhandled rejection. Defaults to an empty-but-valid payload; tests that assert on sections override it. */
    getNodeIntelligence.mockResolvedValue({
      nodeKey: "n1",
      categories: [],
      lastScannedAt: null,
      hasCoverageLimitations: false
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    getNodeDetail.mockReset();
    getFieldSummaries.mockReset();
    getRecordFragment.mockReset();
    getRecordSharing.mockReset();
    getRelationshipFieldDetail.mockReset();
    getObjectSharingSettings.mockReset();
    getImpact.mockReset();
    getNodeIntelligence.mockReset();
  });

  describe("Intelligence sections (Automation / Code / Security) and scan provenance", () => {
    function intelligence(overrides) {
      return {
        nodeKey: "account",
        categories: [
          {
            category: "Automation",
            items: [
              {
                nodeKey: "trg1",
                label: "AccountTrigger",
                typeKey: "SalesforceMetadata.ApexTrigger",
                typeLabel: "Apex Trigger",
                direction: "incoming"
              }
            ],
            truncated: false,
            coverageNote: "Detected: the object each Apex trigger fires on."
          },
          {
            category: "Code",
            items: [],
            truncated: false,
            coverageNote:
              "Detected: Apex references matched by name. Not detected: dynamic Apex."
          },
          {
            category: "Security",
            items: [
              {
                nodeKey: "ps1",
                label: "Sales_Access",
                typeKey: "SalesforceMetadata.PermissionSet",
                typeLabel: "Permission Set",
                direction: "incoming"
              }
            ],
            truncated: false,
            coverageNote:
              "Detected: object-level grants. Not detected: field-level grants."
          }
        ],
        /** Relative to Date.now() rather than a fixed past date so this fixture never crosses STALE_THRESHOLD_MS as real-world time passes — a hardcoded past ISO string here previously bit-rotted into a false "stale" result once more than 30 days had elapsed since it was written. */
        lastScannedAt: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
        hasCoverageLimitations: false,
        ...overrides
      };
    }

    it("renders Automation, Code and Security sections with real named components and their direction", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getNodeIntelligence.mockResolvedValue(intelligence());
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "Automation");
      await expandSection(element, "Security");
      await expandFirstTypeGroup(element, "Automation");
      await expandFirstTypeGroup(element, "Security");

      const sections = element.shadowRoot.querySelectorAll(
        '[data-id="intelligence-section"]'
      );
      expect(sections).toHaveLength(3);
      expect(sections[0].textContent).toContain("Automation");
      expect(sections[0].textContent).toContain("AccountTrigger");
      expect(sections[0].textContent).toContain("Apex Trigger");
      /** 'incoming' is internal vocabulary; the user must see what it MEANS. */
      expect(sections[0].textContent).toContain("uses this");
      expect(sections[2].textContent).toContain("Sales_Access");
    });

    /** An empty section must still render, with its coverage note available — otherwise a user cannot tell "no triggers exist" from "triggers are not detected". The note itself is collapsed by default (item 15) so it never dominates the panel; opening "Coverage details" reveals it. */
    it("renders an empty section with an honest, differentiated empty state (true zero, since this fixture is recently scanned with no coverage limitations) and an on-demand coverage note", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getNodeIntelligence.mockResolvedValue(intelligence());
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "Code");

      const codeSection = element.shadowRoot.querySelector(
        '[data-category="Code"]'
      );
      expect(codeSection).not.toBeNull();
      expect(
        codeSection.querySelector('[data-id="intelligence-empty"]').textContent
      ).toContain("No code detected for this component.");
      expect(
        codeSection.querySelector('[data-id="intelligence-coverage"]')
      ).toBeNull();

      codeSection.querySelector('[data-id="coverage-details-toggle"]').click();
      await flushPromises();
      expect(
        codeSection.querySelector('[data-id="intelligence-coverage"]')
          .textContent
      ).toContain("Not detected: dynamic Apex");
    });

    it("truncates a long namespaced Permission Set name to a single line with the full name available via title, instead of word-breaking across three lines (audit #11)", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getNodeIntelligence.mockResolvedValue(
        intelligence({
          categories: [
            {
              category: "Automation",
              items: [],
              truncated: false,
              coverageNote: "n/a"
            },
            {
              category: "Code",
              items: [],
              truncated: false,
              coverageNote: "n/a"
            },
            {
              category: "Security",
              items: [
                {
                  nodeKey: "ps1",
                  label: "MuleSoftSeamlessLoginC2CPermSet",
                  typeKey: "SalesforceMetadata.PermissionSet",
                  typeLabel: "Permission Set",
                  direction: "incoming"
                }
              ],
              truncated: false,
              coverageNote: "n/a"
            }
          ]
        })
      );
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "Security");
      await expandFirstTypeGroup(element, "Security");

      const securitySection = element.shadowRoot.querySelector(
        '[data-category="Security"]'
      );
      const row = securitySection.querySelector('[data-id="intelligence-row"]');
      const labelCell = row.querySelector("td");
      expect(labelCell.getAttribute("title")).toBe(
        "MuleSoftSeamlessLoginC2CPermSet"
      );
      expect(labelCell.textContent).toBe("MuleSoftSeamlessLoginC2CPermSet");
    });

    it("never exposes a raw SalesforceMetadata.* typeKey as a user-facing label", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getNodeIntelligence.mockResolvedValue(intelligence());
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "Automation");
      await expandSection(element, "Code");
      await expandSection(element, "Security");
      await expandFirstTypeGroup(element, "Automation");
      await expandFirstTypeGroup(element, "Security");

      const sectionText = [
        ...element.shadowRoot.querySelectorAll(
          '[data-id="intelligence-section"]'
        )
      ]
        .map((s) => s.textContent)
        .join(" ");
      expect(sectionText).not.toContain("SalesforceMetadata.");
    });

    it("shows when the intelligence was last scanned, since every number here comes from the persisted scan graph", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getNodeIntelligence.mockResolvedValue(intelligence());
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();

      const freshness = element.shadowRoot.querySelector(
        '[data-id="scan-freshness"]'
      );
      expect(freshness).not.toBeNull();
      expect(freshness.textContent).toContain("last scanned");
      expect(
        element.shadowRoot.querySelector('[data-id="coverage-limitations"]')
      ).toBeNull();
    });

    /** Never-scanned must be stated explicitly — omitting the line would read as freshness. */
    it("states explicitly when the org has never been scanned rather than implying fresh data", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getNodeIntelligence.mockResolvedValue(
        intelligence({ lastScannedAt: null })
      );
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-id="scan-freshness"]')
          .textContent
      ).toContain("Never scanned");
    });

    it("warns when the last scan left dependency coverage incomplete", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getNodeIntelligence.mockResolvedValue(
        intelligence({ hasCoverageLimitations: true })
      );
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-id="coverage-limitations"]')
          .textContent
      ).toContain("not fully scanned");
    });

    it("surfaces a truncation notice rather than silently showing a partial list", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      const payload = intelligence();
      payload.categories[0].truncated = true;
      getNodeIntelligence.mockResolvedValue(payload);
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "Automation");

      expect(
        element.shadowRoot.querySelector('[data-id="intelligence-truncated"]')
      ).not.toBeNull();
    });

    describe('empty-state differentiation (GraphUI.md §42, item 22) — never one undifferentiated "nothing found"', () => {
      it("an empty section on a never-scanned node reads as Unscanned, not a zero result", async () => {
        getNodeDetail.mockResolvedValue(objectDetail());
        const payload = intelligence({ lastScannedAt: null });
        payload.categories[1].items = [];
        getNodeIntelligence.mockResolvedValue(payload);
        const element = createElement("c-oi-node-detail-panel", {
          is: OiNodeDetailPanel
        });
        document.body.appendChild(element);
        element.nodeKey = "account";
        await flushPromises();
        await expandSection(element, "Code");

        const codeSection = element.shadowRoot.querySelector(
          '[data-category="Code"]'
        );
        const empty = codeSection.querySelector(
          '[data-id="intelligence-empty"]'
        );
        expect(empty.textContent).toContain("has not been scanned yet");
        expect(empty.dataset.state).toBe("coverage-incomplete");
        expect(empty.className).toContain(
          "oi-node-detail-panel-empty-state_coverage-incomplete"
        );
      });

      it("an empty section whose scan is older than 30 days reads as Stale, not a fresh zero result", async () => {
        getNodeDetail.mockResolvedValue(objectDetail());
        const payload = intelligence({
          lastScannedAt: "2026-06-01T00:00:00.000Z"
        });
        payload.categories[1].items = [];
        getNodeIntelligence.mockResolvedValue(payload);
        const element = createElement("c-oi-node-detail-panel", {
          is: OiNodeDetailPanel
        });
        document.body.appendChild(element);
        element.nodeKey = "account";
        await flushPromises();
        await expandSection(element, "Code");

        const codeSection = element.shadowRoot.querySelector(
          '[data-category="Code"]'
        );
        const empty = codeSection.querySelector(
          '[data-id="intelligence-empty"]'
        );
        expect(empty.textContent).toContain("older scan");
        expect(empty.dataset.state).toBe("coverage-incomplete");
        expect(empty.className).toContain(
          "oi-node-detail-panel-empty-state_coverage-incomplete"
        );
      });

      it("an empty section on a recently-scanned node with no coverage limitations reads as a plain true zero", async () => {
        getNodeDetail.mockResolvedValue(objectDetail());
        getNodeIntelligence.mockResolvedValue(intelligence());
        const element = createElement("c-oi-node-detail-panel", {
          is: OiNodeDetailPanel
        });
        document.body.appendChild(element);
        element.nodeKey = "account";
        await flushPromises();
        await expandSection(element, "Code");

        const codeSection = element.shadowRoot.querySelector(
          '[data-category="Code"]'
        );
        const empty = codeSection.querySelector(
          '[data-id="intelligence-empty"]'
        );
        expect(empty.dataset.state).toBe("true-zero");
        expect(empty.className).toContain(
          "oi-node-detail-panel-empty-state_true-zero"
        );
        expect(empty.textContent).not.toContain("scanned yet");
        expect(empty.textContent).not.toContain("older scan");
      });

      it("an empty section flagged with coverage limitations reads as possibly incomplete, even on a fresh scan", async () => {
        getNodeDetail.mockResolvedValue(objectDetail());
        getNodeIntelligence.mockResolvedValue(
          intelligence({ hasCoverageLimitations: true })
        );
        const element = createElement("c-oi-node-detail-panel", {
          is: OiNodeDetailPanel
        });
        document.body.appendChild(element);
        element.nodeKey = "account";
        await flushPromises();
        await expandSection(element, "Code");

        const codeSection = element.shadowRoot.querySelector(
          '[data-category="Code"]'
        );
        const empty = codeSection.querySelector(
          '[data-id="intelligence-empty"]'
        );
        expect(empty.dataset.state).toBe("coverage-incomplete");
        expect(empty.className).toContain(
          "oi-node-detail-panel-empty-state_coverage-incomplete"
        );
        expect(empty.textContent).toContain("may be incomplete");
      });
    });

    it("collapses and re-expands an intelligence section on header click, without discarding its already-loaded data", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getNodeIntelligence.mockResolvedValue(intelligence());
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();

      const automationSection = element.shadowRoot.querySelector(
        '[data-category="Automation"]'
      );
      expect(automationSection.textContent).not.toContain("AccountTrigger");
      const toggle = automationSection.querySelector(
        '[data-id="intelligence-section-toggle"]'
      );
      expect(toggle.getAttribute("aria-expanded")).toBe("false");

      toggle.click();
      await flushPromises();
      expect(toggle.getAttribute("aria-expanded")).toBe("true");
      await expandFirstTypeGroup(element, "Automation");
      expect(automationSection.textContent).toContain("AccountTrigger");

      toggle.click();
      await flushPromises();
      expect(automationSection.textContent).not.toContain("AccountTrigger");
      expect(toggle.getAttribute("aria-expanded")).toBe("false");
    });

    it("selecting a related component dispatches select so the user can navigate to it", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getNodeIntelligence.mockResolvedValue(intelligence());
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "Automation");
      await expandFirstTypeGroup(element, "Automation");
      const handler = jest.fn();
      element.addEventListener("select", handler);

      element.shadowRoot.querySelector('[data-id="intelligence-row"]').click();

      expect(handler).toHaveBeenCalledTimes(1);
      expect(handler.mock.calls[0][0].detail.nodeKey).toBe("trg1");
    });

    describe("Type groups (component type — count, opened on click) and Flow status badges", () => {
      function automationWithFlows() {
        return intelligence({
          categories: [
            {
              category: "Automation",
              items: [
                {
                  nodeKey: "trg1",
                  label: "AccountTrigger",
                  typeKey: "SalesforceMetadata.ApexTrigger",
                  typeLabel: "Apex Trigger",
                  direction: "incoming"
                },
                {
                  nodeKey: "flow1",
                  label: "Account_After_Save",
                  typeKey: "SalesforceMetadata.Flow",
                  typeLabel: "Flow",
                  direction: "incoming",
                  status: "Active",
                  subTypeKey: "SalesforceMetadata.Flow",
                  subTypeLabel: "Flow"
                },
                {
                  nodeKey: "flow2",
                  label: "Old_Discount_Process",
                  typeKey: "SalesforceMetadata.Flow",
                  typeLabel: "Flow",
                  direction: "incoming",
                  status: "Inactive",
                  subTypeKey: "ProcessBuilder",
                  subTypeLabel: "Process Builder"
                }
              ],
              truncated: false,
              coverageNote: "n/a"
            },
            {
              category: "Code",
              items: [],
              truncated: false,
              coverageNote: "n/a"
            },
            {
              category: "Security",
              items: [],
              truncated: false,
              coverageNote: "n/a"
            }
          ]
        });
      }

      it("groups Automation items by type — Apex Trigger, Flow, and Process Builder each their own count — collapsed until clicked", async () => {
        getNodeDetail.mockResolvedValue(objectDetail());
        getNodeIntelligence.mockResolvedValue(automationWithFlows());
        const element = createElement("c-oi-node-detail-panel", {
          is: OiNodeDetailPanel
        });
        document.body.appendChild(element);
        element.nodeKey = "account";
        await flushPromises();
        await expandSection(element, "Automation");

        const automationSection = element.shadowRoot.querySelector(
          '[data-category="Automation"]'
        );
        const groups = automationSection.querySelectorAll(
          '[data-id="intelligence-type-group"]'
        );
        expect(groups).toHaveLength(3);
        /** Collapsed by default — the whole point of "a number until you click it." */
        expect(automationSection.textContent).not.toContain("AccountTrigger");
        expect(automationSection.textContent).not.toContain(
          "Account_After_Save"
        );

        const counts = [
          ...automationSection.querySelectorAll(
            '[data-id="intelligence-type-group-count"]'
          )
        ].map((el) => el.textContent);
        expect(counts).toEqual(["1", "1", "1"]);

        const flowToggle = [...groups]
          .find((group) => group.textContent.includes("Process Builder"))
          .querySelector('[data-id="intelligence-type-group-toggle"]');
        flowToggle.click();
        await flushPromises();
        expect(automationSection.textContent).toContain("Old_Discount_Process");
        expect(automationSection.textContent).not.toContain(
          "Account_After_Save"
        );
      });

      it("shows an Active/Inactive status badge on a Flow item, colored differently per status", async () => {
        getNodeDetail.mockResolvedValue(objectDetail());
        getNodeIntelligence.mockResolvedValue(automationWithFlows());
        const element = createElement("c-oi-node-detail-panel", {
          is: OiNodeDetailPanel
        });
        document.body.appendChild(element);
        element.nodeKey = "account";
        await flushPromises();
        await expandSection(element, "Automation");

        const automationSection = element.shadowRoot.querySelector(
          '[data-category="Automation"]'
        );
        const flowGroupToggle = [
          ...automationSection.querySelectorAll(
            '[data-id="intelligence-type-group-toggle"]'
          )
        ].find(
          (toggle) =>
            toggle.textContent.includes("Flow") &&
            !toggle.textContent.includes("Process")
        );
        flowGroupToggle.click();
        await flushPromises();

        const badge = automationSection.querySelector(
          '[data-id="intelligence-status-badge"]'
        );
        expect(badge).not.toBeNull();
        expect(badge.textContent).toBe("Active");
        expect(badge.className).toContain("is-active");
      });

      it("never shows a status badge for a component type with no status concept (Apex Trigger)", async () => {
        getNodeDetail.mockResolvedValue(objectDetail());
        getNodeIntelligence.mockResolvedValue(automationWithFlows());
        const element = createElement("c-oi-node-detail-panel", {
          is: OiNodeDetailPanel
        });
        document.body.appendChild(element);
        element.nodeKey = "account";
        await flushPromises();
        await expandSection(element, "Automation");

        const automationSection = element.shadowRoot.querySelector(
          '[data-category="Automation"]'
        );
        const triggerGroupToggle = [
          ...automationSection.querySelectorAll(
            '[data-id="intelligence-type-group-toggle"]'
          )
        ].find((toggle) => toggle.textContent.includes("Apex Trigger"));
        triggerGroupToggle.click();
        await flushPromises();

        expect(
          automationSection.querySelector(
            '[data-id="intelligence-status-badge"]'
          )
        ).toBeNull();
      });
    });

    it("lists an Apex Trigger under both Automation and Code when the registry registers it for both (dual-category)", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getNodeIntelligence.mockResolvedValue(
        intelligence({
          categories: [
            {
              category: "Automation",
              items: [
                {
                  nodeKey: "trg1",
                  label: "AccountTrigger",
                  typeKey: "SalesforceMetadata.ApexTrigger",
                  typeLabel: "Apex Trigger",
                  direction: "incoming"
                }
              ],
              truncated: false,
              coverageNote: "n/a"
            },
            {
              category: "Code",
              items: [
                {
                  nodeKey: "trg1",
                  label: "AccountTrigger",
                  typeKey: "SalesforceMetadata.ApexTrigger",
                  typeLabel: "Apex Trigger",
                  direction: "incoming"
                }
              ],
              truncated: false,
              coverageNote: "n/a"
            },
            {
              category: "Security",
              items: [],
              truncated: false,
              coverageNote: "n/a"
            }
          ]
        })
      );
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "Automation");
      await expandSection(element, "Code");
      await expandFirstTypeGroup(element, "Automation");
      await expandFirstTypeGroup(element, "Code");

      const automationSection = element.shadowRoot.querySelector(
        '[data-category="Automation"]'
      );
      const codeSection = element.shadowRoot.querySelector(
        '[data-category="Code"]'
      );
      expect(automationSection.textContent).toContain("AccountTrigger");
      expect(codeSection.textContent).toContain("AccountTrigger");
    });

    it("renders a sanitized error when intelligence fails, without breaking the rest of the panel", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getNodeIntelligence.mockRejectedValue({
        body: { message: "You do not have permission to view org graph data." }
      });
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();

      const intelligenceBanner = element.shadowRoot.querySelector(
        '[data-id="intelligence-error"]'
      );
      expect(intelligenceBanner.state).toBe("error");
      expect(intelligenceBanner.message).toContain("permission");
      /** The rest of the panel must survive an intelligence failure — a failed section is not a failed panel. */
      expect(
        element.shadowRoot.querySelector('[data-id="detail-content"]')
      ).not.toBeNull();
    });
  });

  describe("Technical Details (raw attributes moved out of the default experience)", () => {
    /** The exact raw keys that used to be dumped at users unprompted — the concrete thing this change moves out of the default view. */
    function detailWithRawAttributes() {
      return objectDetail({
        attributes: {
          custom: false,
          keyPrefix: "001",
          queryable: true,
          feedEnabled: false
        }
      });
    }

    it("collapses raw technical attributes by default so they no longer dominate the panel", async () => {
      getNodeDetail.mockResolvedValue(detailWithRawAttributes());
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-id="technical-details"]')
      ).not.toBeNull();
      expect(
        element.shadowRoot.querySelector('[data-id="technical-details-table"]')
      ).toBeNull();
      expect(
        element.shadowRoot.querySelector('[data-id="technical-details-toggle"]')
          .textContent
      ).toContain("Show technical details");
      /** The raw keys must not be visible anywhere in the panel until asked for. */
      expect(element.shadowRoot.textContent).not.toContain("keyPrefix");
    });

    /** The data must still be reachable — this was a presentation fix, never a deletion. */
    it("reveals the raw attributes on demand without losing any of them", async () => {
      getNodeDetail.mockResolvedValue(detailWithRawAttributes());
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();

      element.shadowRoot
        .querySelector('[data-id="technical-details-toggle"]')
        .click();
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-id="technical-details-table"]'
      );
      expect(table).not.toBeNull();
      expect(table.textContent).toContain("keyPrefix");
      expect(table.textContent).toContain("queryable");
      expect(
        element.shadowRoot.querySelector('[data-id="technical-details-toggle"]')
          .textContent
      ).toContain("Hide technical details");
    });
  });

  it("shows the placeholder state when no node is selected", () => {
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);
    return Promise.resolve().then(() => {
      expect(
        element.shadowRoot.querySelector('[data-id="detail-placeholder"]')
      ).not.toBeNull();
    });
  });

  it("re-fetches detail whenever nodeKey changes and renders the result generically", async () => {
    getNodeDetail.mockResolvedValue({
      nodeKey: "n1",
      typeKey: "SalesforceMetadata.CustomObject",
      label: "Account",
      secondaryKey: "Account",
      attributes: { custom: false, sharingModel: "ReadWrite" }
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);

    element.nodeKey = "n1";
    await flushPromises();

    expect(getNodeDetail).toHaveBeenCalledWith({ nodeKey: "n1" });
    const content = element.shadowRoot.querySelector(
      '[data-id="detail-content"]'
    );
    expect(content).not.toBeNull();
    expect(content.textContent).toContain("Account");
  });

  it('a Record Analysis node key (ADR-0021) resolves via getRecordFragment instead of the metadata getNodeDetail, and renders a structured Record Overview (object + Record Id, never a metadata "API Name" row)', async () => {
    getRecordFragment.mockResolvedValue({
      centerNodeKey: "Record::Account::001x1",
      nodes: [
        {
          nodeKey: "Record::Account::001x1",
          typeKey: "SalesforceRecord.Account",
          label: "Acme Corp",
          secondaryKey: "Account 001x1",
          state: "Active"
        }
      ],
      edges: [],
      hasMore: false,
      recordOverview: {
        ownerName: "Jane Admin",
        createdDate: "2026-08-10T08:15:00.000Z",
        lastModifiedDate: "2026-09-12T14:30:00.000Z"
      }
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);

    element.nodeKey = "Record::Account::001x1";
    await flushPromises();

    expect(getRecordFragment).toHaveBeenCalledWith({
      objectApiName: "Account",
      recordId: "001x1"
    });
    expect(getNodeDetail).not.toHaveBeenCalled();
    const content = element.shadowRoot.querySelector(
      '[data-id="detail-content"]'
    );
    expect(content).not.toBeNull();
    expect(content.textContent).toContain("Acme Corp");
    expect(content.textContent).toContain("Account");
    expect(content.textContent).toContain("001x1");
    expect(content.textContent).toContain("Jane Admin");
    expect(content.textContent).toContain("Created");
    expect(content.textContent).toContain("Last Modified");
    expect(content.textContent).not.toContain("API Name");
    expect(getNodeIntelligence).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector('[data-id="impact-analysis-section"]')
    ).toBeNull();
  });

  it("derives a real Record Hierarchy section — parent lookups and child records grouped by object — directly from the SAME fragment's own edges, never a second query or fabricated data", async () => {
    getRecordFragment.mockResolvedValue({
      centerNodeKey: "Record::Account::001x1",
      nodes: [
        {
          nodeKey: "Record::Account::001x1",
          typeKey: "SalesforceRecord.Account",
          label: "Acme Corp",
          secondaryKey: "Account 001x1",
          state: "Active"
        },
        {
          nodeKey: "Record::User::005x1",
          typeKey: "SalesforceRecord.User",
          label: "Jane Admin",
          secondaryKey: "User 005x1",
          state: "Active"
        },
        {
          nodeKey: "Record::Contact::003x1",
          typeKey: "SalesforceRecord.Contact",
          label: "John Doe",
          secondaryKey: "Contact 003x1",
          state: "Active"
        },
        {
          nodeKey: "Record::Contact::003x2",
          typeKey: "SalesforceRecord.Contact",
          label: "Jane Roe",
          secondaryKey: "Contact 003x2",
          state: "Active"
        },
        {
          nodeKey: "Record::Opportunity::006x1",
          typeKey: "SalesforceRecord.Opportunity",
          label: "Big Deal",
          secondaryKey: "Opportunity 006x1",
          state: "Active"
        }
      ],
      edges: [
        {
          edgeKey: "e1",
          typeKey: "SalesforceRecord.LOOKUP_TO",
          sourceNodeKey: "Record::Account::001x1",
          targetNodeKey: "Record::User::005x1",
          viaFieldApiName: "Manager__c"
        },
        {
          edgeKey: "e2",
          typeKey: "SalesforceRecord.CHILD_OF",
          sourceNodeKey: "Record::Account::001x1",
          targetNodeKey: "Record::Contact::003x1",
          viaFieldApiName: "AccountId"
        },
        {
          edgeKey: "e3",
          typeKey: "SalesforceRecord.CHILD_OF",
          sourceNodeKey: "Record::Account::001x1",
          targetNodeKey: "Record::Contact::003x2",
          viaFieldApiName: "AccountId"
        },
        {
          edgeKey: "e4",
          typeKey: "SalesforceRecord.CHILD_OF",
          sourceNodeKey: "Record::Account::001x1",
          targetNodeKey: "Record::Opportunity::006x1",
          viaFieldApiName: "AccountId"
        }
      ],
      hasMore: true
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);

    element.nodeKey = "Record::Account::001x1";
    await flushPromises();

    const hierarchy = element.shadowRoot.querySelector(
      '[data-id="record-hierarchy-section"]'
    );
    expect(hierarchy).not.toBeNull();
    expect(hierarchy.textContent).toContain("User");
    expect(hierarchy.textContent).toContain("Jane Admin");
    expect(hierarchy.textContent).toContain("Manager__c");
    expect(hierarchy.textContent).toContain("Contact");
    expect(hierarchy.textContent).toContain("Opportunity");
    // Two Contact children collapse into one grouped row with count 2 — not two flat rows.
    const contactRow = Array.from(hierarchy.querySelectorAll("tr")).find(
      (tr) =>
        tr.textContent.includes("Contact") &&
        !tr.textContent.includes("Jane") &&
        !tr.textContent.includes("John")
    );
    expect(contactRow.textContent).toContain("2");
    expect(
      element.shadowRoot.querySelector('[data-id="record-has-more-note"]')
    ).not.toBeNull();
    // Header count and default-expanded state mirror Relationships' own convention for Object mode — 1 parent + 2 grouped Contact children + 1 Opportunity child = 4, expanded without any click needed.
    const hierarchyToggle = element.shadowRoot.querySelector(
      '[data-id="hierarchy-section-toggle"]'
    );
    expect(hierarchyToggle.getAttribute("aria-expanded")).toBe("true");
    expect(hierarchyToggle.textContent).toContain("4");
  });

  it("Sharing starts collapsed by default, exactly like Object mode's Sharing Settings, while Hierarchy starts expanded like Relationships", async () => {
    getRecordFragment.mockResolvedValue({
      centerNodeKey: "Record::Account::001x1",
      nodes: [
        {
          nodeKey: "Record::Account::001x1",
          typeKey: "SalesforceRecord.Account",
          label: "Acme Corp",
          secondaryKey: "Account 001x1",
          state: "Active"
        }
      ],
      edges: [],
      hasMore: false
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);

    element.nodeKey = "Record::Account::001x1";
    await flushPromises();

    expect(
      element.shadowRoot
        .querySelector('[data-id="hierarchy-section-toggle"]')
        .getAttribute("aria-expanded")
    ).toBe("true");
    expect(
      element.shadowRoot
        .querySelector('[data-id="sharing-section-toggle"]')
        .getAttribute("aria-expanded")
    ).toBe("false");
  });

  it("still renders the Hierarchy section with an honest empty state for a record with no parent lookups or children (an isolated/root record) — never hides the section entirely", async () => {
    getRecordFragment.mockResolvedValue({
      centerNodeKey: "Record::Account::001x1",
      nodes: [
        {
          nodeKey: "Record::Account::001x1",
          typeKey: "SalesforceRecord.Account",
          label: "Acme Corp",
          secondaryKey: "Account 001x1",
          state: "Active"
        }
      ],
      edges: [],
      hasMore: false
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);

    element.nodeKey = "Record::Account::001x1";
    await flushPromises();

    expect(
      element.shadowRoot.querySelector('[data-id="record-hierarchy-section"]')
    ).not.toBeNull();
    const emptyState = element.shadowRoot.querySelector(
      '[data-id="record-hierarchy-empty"]'
    );
    expect(emptyState).not.toBeNull();
    expect(emptyState.title).toBe("No related records");
  });

  it("a Record Analysis node no longer present in its own fragment renders an honest error, not a crash", async () => {
    getRecordFragment.mockResolvedValue({
      centerNodeKey: null,
      nodes: [],
      edges: [],
      hasMore: false
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);

    element.nodeKey = "Record::Account::001x1";
    await flushPromises();

    const errorEl = element.shadowRoot.querySelector(
      '[data-id="detail-error"]'
    );
    expect(errorEl).not.toBeNull();
    expect(errorEl.state).toBe("error");
    expect(errorEl.message).toContain("No record found");
  });

  it("does not call getRecordSharing until the Sharing section is explicitly expanded — a live, non-cacheable read stays opt-in like Fields, never automatic on selection", async () => {
    getRecordFragment.mockResolvedValue({
      centerNodeKey: "Record::Account::001x1",
      nodes: [
        {
          nodeKey: "Record::Account::001x1",
          typeKey: "SalesforceRecord.Account",
          label: "Acme Corp",
          secondaryKey: "Account 001x1",
          state: "Active"
        }
      ],
      edges: [],
      hasMore: false
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);

    element.nodeKey = "Record::Account::001x1";
    await flushPromises();

    expect(getRecordSharing).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector('[data-id="sharing-section-toggle"]')
    ).not.toBeNull();
  });

  it("loads and renders share rows once Show Sharing is clicked, keyed to the selected record", async () => {
    getRecordFragment.mockResolvedValue({
      centerNodeKey: "Record::Account::001x1",
      nodes: [
        {
          nodeKey: "Record::Account::001x1",
          typeKey: "SalesforceRecord.Account",
          label: "Acme Corp",
          secondaryKey: "Account 001x1",
          state: "Active"
        }
      ],
      edges: [],
      hasMore: false
    });
    getRecordSharing.mockResolvedValue({
      supportsSharing: true,
      coverageNote: null,
      shareRows: [
        {
          userOrGroupId: "005000000000001",
          userOrGroupLabel: "Jane Admin",
          accessLevel: "Owner",
          rowCause: "Owner"
        }
      ],
      truncated: false,
      isLockedByApproval: false,
      pendingApprovalDetail: null,
      orgWideDefault: {
        supported: true,
        unavailableReason: null,
        internalSharingModel: "ReadWrite",
        externalSharingModel: "Private"
      }
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);

    element.nodeKey = "Record::Account::001x1";
    await flushPromises();
    element.shadowRoot
      .querySelector('[data-id="sharing-section-toggle"]')
      .click();
    await flushPromises();

    expect(getRecordSharing).toHaveBeenCalledWith({
      objectApiName: "Account",
      recordId: "001x1"
    });
    const table = element.shadowRoot.querySelector('[data-id="sharing-table"]');
    expect(table).not.toBeNull();
    expect(table.textContent).toContain("Jane Admin");
    expect(table.textContent).toContain("Owner");

    const owdGrid = element.shadowRoot.querySelector(
      '[data-id="sharing-org-wide-default-grid"]'
    );
    expect(owdGrid).not.toBeNull();
    expect(owdGrid.textContent).toContain("ReadWrite");
    expect(owdGrid.textContent).toContain("Private");
  });

  it("reports the Org-Wide Default as unavailable, distinct from the record's own share rows, when the Tooling API cannot resolve it", async () => {
    getRecordFragment.mockResolvedValue({
      centerNodeKey: "Record::Account::001x1",
      nodes: [
        {
          nodeKey: "Record::Account::001x1",
          typeKey: "SalesforceRecord.Account",
          label: "Acme Corp",
          secondaryKey: "Account 001x1",
          state: "Active"
        }
      ],
      edges: [],
      hasMore: false
    });
    getRecordSharing.mockResolvedValue({
      supportsSharing: true,
      coverageNote: null,
      shareRows: [
        {
          userOrGroupId: "005000000000001",
          userOrGroupLabel: "Jane Admin",
          accessLevel: "Owner",
          rowCause: "Owner"
        }
      ],
      truncated: false,
      isLockedByApproval: false,
      pendingApprovalDetail: null,
      orgWideDefault: {
        supported: false,
        unavailableReason:
          "Sharing settings could not be retrieved for this object.",
        internalSharingModel: null,
        externalSharingModel: null
      }
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);

    element.nodeKey = "Record::Account::001x1";
    await flushPromises();
    element.shadowRoot
      .querySelector('[data-id="sharing-section-toggle"]')
      .click();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(
        '[data-id="sharing-org-wide-default-grid"]'
      )
    ).toBeNull();
    const unavailable = element.shadowRoot.querySelector(
      '[data-id="sharing-org-wide-default-unavailable"]'
    );
    expect(unavailable).not.toBeNull();
    expect(unavailable.textContent).toContain("could not be retrieved");
    expect(
      element.shadowRoot.querySelector('[data-id="sharing-table"]')
    ).not.toBeNull();
  });

  it("renders a Not Applicable state, never an empty table, when the object has no share table", async () => {
    getRecordFragment.mockResolvedValue({
      centerNodeKey: "Record::CampaignMember::00v1",
      nodes: [
        {
          nodeKey: "Record::CampaignMember::00v1",
          typeKey: "SalesforceRecord.CampaignMember",
          label: "CampaignMember 00v1",
          secondaryKey: "CampaignMember 00v1",
          state: "Active"
        }
      ],
      edges: [],
      hasMore: false
    });
    getRecordSharing.mockResolvedValue({
      supportsSharing: false,
      coverageNote:
        "This object has no independent sharing table — its access is controlled entirely by its parent record or by the object's org-wide default.",
      shareRows: [],
      truncated: false,
      isLockedByApproval: false,
      pendingApprovalDetail: null
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);

    element.nodeKey = "Record::CampaignMember::00v1";
    await flushPromises();
    element.shadowRoot
      .querySelector('[data-id="sharing-section-toggle"]')
      .click();
    await flushPromises();

    const unsupported = element.shadowRoot.querySelector(
      '[data-id="sharing-unsupported"]'
    );
    expect(unsupported).not.toBeNull();
    expect(unsupported.message).toContain("no independent sharing table");
    expect(
      element.shadowRoot.querySelector('[data-id="sharing-table"]')
    ).toBeNull();
  });

  it("surfaces an approval lock banner above the share rows without hiding them", async () => {
    getRecordFragment.mockResolvedValue({
      centerNodeKey: "Record::Account::001x1",
      nodes: [
        {
          nodeKey: "Record::Account::001x1",
          typeKey: "SalesforceRecord.Account",
          label: "Acme Corp",
          secondaryKey: "Account 001x1",
          state: "Active"
        }
      ],
      edges: [],
      hasMore: false
    });
    getRecordSharing.mockResolvedValue({
      supportsSharing: true,
      coverageNote: null,
      shareRows: [
        {
          userOrGroupId: "005000000000001",
          userOrGroupLabel: "Jane Admin",
          accessLevel: "Owner",
          rowCause: "Owner"
        }
      ],
      truncated: false,
      isLockedByApproval: true,
      pendingApprovalDetail:
        "Submitted by Jane Admin, awaiting the next approver."
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);

    element.nodeKey = "Record::Account::001x1";
    await flushPromises();
    element.shadowRoot
      .querySelector('[data-id="sharing-section-toggle"]')
      .click();
    await flushPromises();

    const lockBanner = element.shadowRoot.querySelector(
      '[data-id="sharing-approval-lock"]'
    );
    expect(lockBanner).not.toBeNull();
    expect(lockBanner.message).toContain("Submitted by Jane Admin");
    expect(
      element.shadowRoot.querySelector('[data-id="sharing-table"]')
    ).not.toBeNull();
  });

  it("clears sharing state when the selected record changes, so a previous record's share rows never bleed into the newly-selected one", async () => {
    getRecordFragment.mockResolvedValue({
      centerNodeKey: "Record::Account::001x1",
      nodes: [
        {
          nodeKey: "Record::Account::001x1",
          typeKey: "SalesforceRecord.Account",
          label: "Acme Corp",
          secondaryKey: "Account 001x1",
          state: "Active"
        }
      ],
      edges: [],
      hasMore: false
    });
    getRecordSharing.mockResolvedValue({
      supportsSharing: true,
      coverageNote: null,
      shareRows: [
        {
          userOrGroupId: "005000000000001",
          userOrGroupLabel: "Jane Admin",
          accessLevel: "Owner",
          rowCause: "Owner"
        }
      ],
      truncated: false,
      isLockedByApproval: false,
      pendingApprovalDetail: null
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);

    element.nodeKey = "Record::Account::001x1";
    await flushPromises();
    element.shadowRoot
      .querySelector('[data-id="sharing-section-toggle"]')
      .click();
    await flushPromises();
    expect(
      element.shadowRoot.querySelector('[data-id="sharing-table"]')
    ).not.toBeNull();

    getRecordFragment.mockResolvedValue({
      centerNodeKey: "Record::Account::001x2",
      nodes: [
        {
          nodeKey: "Record::Account::001x2",
          typeKey: "SalesforceRecord.Account",
          label: "Beta Corp",
          secondaryKey: "Account 001x2",
          state: "Active"
        }
      ],
      edges: [],
      hasMore: false
    });
    element.nodeKey = "Record::Account::001x2";
    await flushPromises();

    expect(
      element.shadowRoot.querySelector('[data-id="sharing-table"]')
    ).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="sharing-section-toggle"]')
    ).not.toBeNull();
  });

  it("renders curated Object fields — Namespace, Custom/Standard — and keeps the structural-connections summary scoped to schema relationships only (G6/G7)", async () => {
    getNodeDetail.mockResolvedValue({
      nodeKey: "acct",
      typeKey: "SalesforceMetadata.CustomObject",
      label: "Account",
      secondaryKey: "Account",
      attributes: {
        custom: false,
        namespace: null,
        label: "Account",
        pluralLabel: "Accounts"
      },
      outgoingRelationshipCounts: { "SalesforceMetadata.HAS_FIELD": 5 },
      incomingRelationshipCounts: { "SalesforceMetadata.LOOKUP_TO": 2 },
      directConnectionCount: 7
    });
    getRelationshipFieldDetail.mockResolvedValue({
      fields: [
        {
          fieldNodeKey: "acctField.OwnerId",
          label: "Owner",
          apiName: "Account.OwnerId",
          relationshipType: "Lookup",
          isRequired: false,
          cascadeDeleteBehavior: null,
          targetObjects: [{ objectApiName: "User", recordCount: 42 }]
        }
      ],
      cardinalityTruncated: false
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    element.registry = {
      nodeTypes: new Map([
        ["SalesforceMetadata.CustomObject", { displayLabel: "Object" }]
      ]),
      edgeTypes: new Map([
        ["SalesforceMetadata.HAS_FIELD", { displayLabel: "Has Field" }],
        ["SalesforceMetadata.LOOKUP_TO", { displayLabel: "Lookup To" }]
      ])
    };
    document.body.appendChild(element);

    element.nodeKey = "acct";
    await flushPromises();

    const content = element.shadowRoot.querySelector(
      '[data-id="detail-content"]'
    );
    expect(content.textContent).toContain("Object");
    expect(content.textContent).toContain("Standard");
    expect(content.textContent).toContain("—");

    /**
     * Object mode gets the curated relationship breakdown (GraphUI.md §42, item 14): HAS_FIELD
     * is schema-membership information, not an object-to-object relationship, so it must never
     * appear here — it already powers the Fields section's own count instead. Only genuine
     * Incoming Lookup/Incoming Master-Detail counts remain as counts (a real number from the
     * same getNodeDetail response, never fabricated); the outgoing side was reworked to show the
     * actual fields behind it instead of a flat count (see the relationship-field-table
     * assertions below).
     */
    const structural = element.shadowRoot.querySelector(
      '[data-id="structural-connections"]'
    );
    expect(structural).not.toBeNull();
    expect(structural.textContent).not.toContain("Has Field");
    expect(structural.textContent).not.toContain("Impact Analysis");
    expect(structural.textContent).toContain("Incoming Lookups");
    const incomingLookupsCount = structural.querySelector(
      '[data-row-key="in-lookup"]'
    );
    expect(incomingLookupsCount.textContent).toBe("2");
    expect(structural.textContent).not.toContain("Outgoing Master-Detail");
    expect(getRelationshipFieldDetail).toHaveBeenCalledWith({
      objectNodeKey: "acct"
    });
    const relationshipFieldTable = structural.querySelector(
      '[data-id="relationship-field-table"]'
    );
    expect(relationshipFieldTable).not.toBeNull();
    expect(relationshipFieldTable.textContent).toContain("Owner");
    expect(relationshipFieldTable.textContent).toContain("Lookup");
    expect(relationshipFieldTable.textContent).toContain("User (42 records)");

    /** Raw attributes now live behind Technical Details, collapsed by default — the data is preserved, only its prominence changed. */
    const technicalDetails = element.shadowRoot.querySelector(
      '[data-id="technical-details"]'
    );
    expect(technicalDetails).not.toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="technical-details-table"]')
    ).toBeNull();

    element.shadowRoot
      .querySelector('[data-id="technical-details-toggle"]')
      .click();
    await flushPromises();

    const revealed = element.shadowRoot.querySelector(
      '[data-id="technical-details-table"]'
    );
    expect(revealed.textContent).toContain("pluralLabel");
    expect(revealed.textContent).not.toContain("custom");
  });

  it("shows a loading skeleton for the outgoing relationships table while getRelationshipFieldDetail is in flight", async () => {
    getNodeDetail.mockResolvedValue({
      nodeKey: "acct",
      typeKey: "SalesforceMetadata.CustomObject",
      label: "Account",
      secondaryKey: "Account",
      attributes: { custom: false },
      outgoingRelationshipCounts: {},
      incomingRelationshipCounts: {},
      directConnectionCount: 0
    });
    let resolveDetail;
    getRelationshipFieldDetail.mockReturnValue(
      new Promise((resolve) => {
        resolveDetail = resolve;
      })
    );
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);

    element.nodeKey = "acct";
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(
        '[data-id="structural-connections"] c-oi-skeleton'
      )
    ).not.toBeNull();

    resolveDetail({ fields: [], cardinalityTruncated: false });
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(
        '[data-id="structural-connections"] c-oi-skeleton'
      )
    ).toBeNull();
  });

  it("renders a retryable error banner when getRelationshipFieldDetail fails, without breaking the rest of the Relationships section", async () => {
    getNodeDetail.mockResolvedValue({
      nodeKey: "acct",
      typeKey: "SalesforceMetadata.CustomObject",
      label: "Account",
      secondaryKey: "Account",
      attributes: { custom: false },
      outgoingRelationshipCounts: {},
      incomingRelationshipCounts: { "SalesforceMetadata.LOOKUP_TO": 1 },
      directConnectionCount: 1
    });
    getRelationshipFieldDetail.mockRejectedValue({
      body: { message: "Something went wrong retrieving the graph." }
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);

    element.nodeKey = "acct";
    await flushPromises();

    const errorBanner = element.shadowRoot.querySelector(
      '[data-id="relationship-field-detail-error"]'
    );
    expect(errorBanner).not.toBeNull();
    expect(errorBanner.message).toBe(
      "Something went wrong retrieving the graph."
    );
    expect(
      element.shadowRoot.querySelector(
        '[data-id="curated-relationships-table"]'
      )
    ).not.toBeNull();

    getRelationshipFieldDetail.mockResolvedValue({
      fields: [],
      cardinalityTruncated: false
    });
    errorBanner.dispatchEvent(new CustomEvent("retry"));
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(
        '[data-id="relationship-field-detail-error"]'
      )
    ).toBeNull();
    expect(
      element.shadowRoot.querySelector(
        '[data-id="relationship-field-detail-empty"]'
      )
    ).not.toBeNull();
  });

  it("shows a truncated note when cardinalityTruncated is true, without dropping the rows that were returned", async () => {
    getNodeDetail.mockResolvedValue({
      nodeKey: "taskObj",
      typeKey: "SalesforceMetadata.CustomObject",
      label: "Task",
      secondaryKey: "Task",
      attributes: { custom: false },
      outgoingRelationshipCounts: {},
      incomingRelationshipCounts: {},
      directConnectionCount: 0
    });
    getRelationshipFieldDetail.mockResolvedValue({
      fields: [
        {
          fieldNodeKey: "taskObj.WhatId",
          label: "What Id",
          apiName: "Task.WhatId",
          relationshipType: "Lookup",
          isRequired: false,
          cascadeDeleteBehavior: null,
          targetObjects: [
            { objectApiName: "Account", recordCount: 10 },
            { objectApiName: "Opportunity", recordCount: null }
          ]
        }
      ],
      cardinalityTruncated: true
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);

    element.nodeKey = "taskObj";
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(
        '[data-id="relationship-cardinality-truncated-note"]'
      )
    ).not.toBeNull();
    const table = element.shadowRoot.querySelector(
      '[data-id="relationship-field-table"]'
    );
    expect(table.textContent).toContain("Account (10 records)");
    expect(table.textContent).toContain("Opportunity (count unavailable)");
  });

  it("clears relationship field detail when the selected object changes, so a previous object's fields never bleed into the newly-selected one", async () => {
    getNodeDetail.mockResolvedValueOnce({
      nodeKey: "objA",
      typeKey: "SalesforceMetadata.CustomObject",
      label: "Object A",
      secondaryKey: "ObjA",
      attributes: { custom: false },
      outgoingRelationshipCounts: {},
      incomingRelationshipCounts: {},
      directConnectionCount: 0
    });
    getRelationshipFieldDetail.mockResolvedValueOnce({
      fields: [
        {
          fieldNodeKey: "objA.Ref",
          label: "Ref",
          apiName: "ObjA.Ref__c",
          relationshipType: "Lookup",
          isRequired: false,
          cascadeDeleteBehavior: null,
          targetObjects: [{ objectApiName: "Account", recordCount: 5 }]
        }
      ],
      cardinalityTruncated: false
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);

    element.nodeKey = "objA";
    await flushPromises();
    expect(
      element.shadowRoot.querySelector('[data-id="relationship-field-table"]')
        .textContent
    ).toContain("Ref");

    getNodeDetail.mockResolvedValueOnce({
      nodeKey: "objB",
      typeKey: "SalesforceMetadata.CustomObject",
      label: "Object B",
      secondaryKey: "ObjB",
      attributes: { custom: false },
      outgoingRelationshipCounts: {},
      incomingRelationshipCounts: {},
      directConnectionCount: 0
    });
    getRelationshipFieldDetail.mockResolvedValueOnce({
      fields: [],
      cardinalityTruncated: false
    });
    element.nodeKey = "objB";
    await flushPromises();

    expect(
      element.shadowRoot.querySelector('[data-id="relationship-field-table"]')
    ).toBeNull();
    expect(getRelationshipFieldDetail).toHaveBeenCalledWith({
      objectNodeKey: "objB"
    });
  });

  it("renders Self Relationships/Referenced Objects/Referencing Objects only when objectRelationshipSummary is supplied (Object mode, from oiGraphExplorer), as plain non-drilldown counts", async () => {
    getNodeDetail.mockResolvedValue(objectDetail());
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    element.objectRelationshipSummary = {
      selfRelationships: 1,
      referencedObjects: 5,
      referencingObjects: 71
    };
    document.body.appendChild(element);
    element.nodeKey = "account";
    await flushPromises();

    const structural = element.shadowRoot.querySelector(
      '[data-id="structural-connections"]'
    );
    expect(structural.textContent).toContain("Self Relationships");
    expect(structural.textContent).toContain("Referenced Objects");
    expect(structural.textContent).toContain("Referencing Objects");
    expect(structural.textContent).toContain("71");
    expect(
      structural.querySelectorAll('[data-id="curated-relationship-count"]')
        .length
    ).toBe(3);
  });

  it("omits Self Relationships/Referenced Objects/Referencing Objects rows (rather than fabricating zeros) when objectRelationshipSummary has not been supplied yet", async () => {
    getNodeDetail.mockResolvedValue(objectDetail());
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);
    element.nodeKey = "account";
    await flushPromises();

    const structural = element.shadowRoot.querySelector(
      '[data-id="structural-connections"]'
    );
    expect(structural.textContent).not.toContain("Self Relationships");
    expect(structural.textContent).not.toContain("Referenced Objects");
    expect(structural.textContent).not.toContain("Referencing Objects");
  });

  it("collapses and re-expands the Relationships section on header click", async () => {
    getNodeDetail.mockResolvedValue(
      objectDetail({
        directConnectionCount: 7,
        outgoingRelationshipCounts: { "SalesforceMetadata.HAS_FIELD": 5 },
        incomingRelationshipCounts: { "SalesforceMetadata.LOOKUP_TO": 2 }
      })
    );
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);
    element.nodeKey = "account";
    await flushPromises();

    const structural = element.shadowRoot.querySelector(
      '[data-id="structural-connections"]'
    );
    expect(structural.textContent).toContain("Incoming Lookups");
    const toggle = structural.querySelector(
      '[data-id="relationships-section-toggle"]'
    );
    expect(toggle.getAttribute("aria-expanded")).toBe("true");

    toggle.click();
    await flushPromises();
    expect(structural.textContent).not.toContain("Incoming Lookups");
    expect(
      structural.querySelector('[data-id="curated-relationship-count-button"]')
    ).toBeNull();

    toggle.click();
    await flushPromises();
    expect(structural.textContent).toContain("Incoming Lookups");
  });

  it("renders curated Field fields — Data Type, Parent Object, Relationship Type derived from real outgoing edges — never guessed from attributes (G6)", async () => {
    getNodeDetail.mockResolvedValue({
      nodeKey: "ownerIdField",
      typeKey: "SalesforceMetadata.CustomField",
      label: "Owner ID",
      secondaryKey: "Account.OwnerId",
      attributes: {
        type: "REFERENCE",
        referenceTo: ["User"],
        relationshipName: "Owner",
        custom: false
      },
      outgoingRelationshipCounts: { "SalesforceMetadata.LOOKUP_TO": 1 },
      incomingRelationshipCounts: { "SalesforceMetadata.HAS_FIELD": 1 },
      directConnectionCount: 2
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    element.registry = {
      nodeTypes: new Map(),
      edgeTypes: new Map([
        ["SalesforceMetadata.LOOKUP_TO", { displayLabel: "Lookup To" }]
      ])
    };
    document.body.appendChild(element);

    element.nodeKey = "ownerIdField";
    await flushPromises();

    const content = element.shadowRoot.querySelector(
      '[data-id="detail-content"]'
    );
    expect(content.textContent).toContain("REFERENCE");
    expect(content.textContent).toContain("Account");
    expect(content.textContent).toContain("Lookup To");
    expect(content.textContent).toContain("User");
    expect(content.textContent).toContain("Owner");
    expect(
      element.shadowRoot.querySelector('[data-id="field-relationship-section"]')
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="structural-connections"]')
    ).toBeNull();
  });

  it("renders a sanitized error state when the Apex call fails", async () => {
    getNodeDetail.mockRejectedValue({
      body: { message: "You don't have permission to view org graph data." }
    });
    const element = createElement("c-oi-node-detail-panel", {
      is: OiNodeDetailPanel
    });
    document.body.appendChild(element);

    element.nodeKey = "n1";
    await flushPromises();

    const errorEl = element.shadowRoot.querySelector(
      '[data-id="detail-error"]'
    );
    expect(errorEl).not.toBeNull();
    expect(errorEl.state).toBe("error");
    expect(errorEl.message).toContain("permission");

    /** Retry must re-issue the fetch that failed, not merely clear the message. */
    getNodeDetail.mockResolvedValueOnce({
      nodeKey: "n1",
      typeKey: "SalesforceMetadata.CustomObject",
      label: "Account",
      secondaryKey: "Account",
      attributes: {}
    });
    errorEl.dispatchEvent(new CustomEvent("retry"));
    await flushPromises();

    expect(getNodeDetail).toHaveBeenCalledTimes(2);
    expect(
      element.shadowRoot.querySelector('[data-id="detail-error"]')
    ).toBeNull();
  });

  describe("Fields section (Show All / Standard / Custom field browser)", () => {
    function fieldSummary(overrides) {
      return {
        nodeKey: "f0",
        label: "Field",
        apiName: "Account.Field",
        dataType: "STRING",
        isCustom: false,
        isRequired: false,
        referenceTo: null,
        ...overrides
      };
    }

    it('shows the free field count from relationship counts and a "Show Fields" trigger, without calling getFieldSummaries until asked', async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);

      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "fields");

      const fieldsSection = element.shadowRoot.querySelector(
        '[data-id="fields-section"]'
      );
      expect(fieldsSection.textContent).toContain("Fields");
      expect(
        fieldsSection.querySelector(
          '[data-id="fields-section-toggle"] .oi-node-detail-panel-section-count'
        ).textContent
      ).toBe("2");
      expect(
        element.shadowRoot.querySelector('[data-id="show-fields-button"]')
      ).not.toBeNull();
      expect(getFieldSummaries).not.toHaveBeenCalled();
      expect(
        element.shadowRoot.querySelector('[data-id="field-metrics"]')
          .textContent
      ).toContain("—");
    });

    it("collapsing the Fields section header hides the Show Fields trigger, and re-expanding restores it", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();

      const toggle = element.shadowRoot.querySelector(
        '[data-id="fields-section-toggle"]'
      );
      expect(toggle.getAttribute("aria-expanded")).toBe("false");
      expect(
        element.shadowRoot.querySelector('[data-id="show-fields-button"]')
      ).toBeNull();

      toggle.click();
      await flushPromises();
      expect(toggle.getAttribute("aria-expanded")).toBe("true");
      expect(
        element.shadowRoot.querySelector('[data-id="show-fields-button"]')
      ).not.toBeNull();

      toggle.click();
      await flushPromises();
      expect(toggle.getAttribute("aria-expanded")).toBe("false");
      expect(
        element.shadowRoot.querySelector('[data-id="show-fields-button"]')
      ).toBeNull();
    });

    it("does not render a Fields section at all for a non-Object node", async () => {
      getNodeDetail.mockResolvedValue({
        nodeKey: "f1",
        typeKey: "SalesforceMetadata.CustomField",
        label: "Some Field",
        secondaryKey: "Account.Some_Field__c",
        attributes: {}
      });
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);

      element.nodeKey = "f1";
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-id="fields-section"]')
      ).toBeNull();
    });

    it('clicking "Show Fields" loads the full list and renders label/API name/type/Custom-or-Standard badge for each', async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getFieldSummaries.mockResolvedValue([
        fieldSummary({
          nodeKey: "f1",
          label: "Account Name",
          apiName: "Account.Name",
          dataType: "STRING",
          isCustom: false
        }),
        fieldSummary({
          nodeKey: "f2",
          label: "Favorite Color",
          apiName: "Account.Favorite_Color__c",
          dataType: "PICKLIST",
          isCustom: true
        })
      ]);
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "fields");

      element.shadowRoot
        .querySelector('[data-id="show-fields-button"]')
        .click();
      await flushPromises();

      expect(getFieldSummaries).toHaveBeenCalledWith({
        objectNodeKey: "account"
      });
      const rows = element.shadowRoot.querySelectorAll('[data-id="field-row"]');
      expect(rows).toHaveLength(2);
      expect(
        element.shadowRoot.querySelector('[data-id="fields-table"]').textContent
      ).toContain("Favorite Color");
      expect(
        element.shadowRoot.querySelector('[data-id="fields-table"]').textContent
      ).toContain("PICKLIST");
      const badges = element.shadowRoot.querySelectorAll(
        '[data-id="field-badge"]'
      );
      const badgeLabels = Array.from(badges).map((b) => b.textContent);
      expect(badgeLabels).toContain("Custom");
      expect(badgeLabels).toContain("Standard");
    });

    it('clicking "Hide Fields" collapses the section without discarding the already-loaded list, and Show Fields reopens it instantly with no new Apex call', async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getFieldSummaries.mockResolvedValue([
        fieldSummary({
          nodeKey: "f1",
          label: "Account Name",
          apiName: "Account.Name",
          dataType: "STRING",
          isCustom: false
        })
      ]);
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "fields");

      element.shadowRoot
        .querySelector('[data-id="show-fields-button"]')
        .click();
      await flushPromises();
      expect(
        element.shadowRoot.querySelector('[data-id="fields-table"]')
      ).not.toBeNull();
      expect(
        element.shadowRoot.querySelector('[data-id="hide-fields-button"]')
      ).not.toBeNull();

      element.shadowRoot
        .querySelector('[data-id="hide-fields-button"]')
        .click();
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-id="fields-table"]')
      ).toBeNull();
      expect(
        element.shadowRoot.querySelector('[data-id="hide-fields-button"]')
      ).toBeNull();
      expect(
        element.shadowRoot.querySelector('[data-id="show-fields-button"]')
      ).not.toBeNull();

      element.shadowRoot
        .querySelector('[data-id="show-fields-button"]')
        .click();
      await flushPromises();

      expect(getFieldSummaries).toHaveBeenCalledTimes(1);
      expect(
        element.shadowRoot.querySelector('[data-id="fields-table"]')
      ).not.toBeNull();
    });

    it("the Standard/Custom filter buttons narrow the already-loaded list without calling getFieldSummaries again", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getFieldSummaries.mockResolvedValue([
        fieldSummary({ nodeKey: "f1", label: "Account Name", isCustom: false }),
        fieldSummary({ nodeKey: "f2", label: "Favorite Color", isCustom: true })
      ]);
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "fields");
      element.shadowRoot
        .querySelector('[data-id="show-fields-button"]')
        .click();
      await flushPromises();

      const customButton = Array.from(
        element.shadowRoot.querySelectorAll('[data-id="field-filter-button"]')
      ).find((b) => b.dataset.filter === "Custom");
      customButton.click();
      await flushPromises();

      expect(getFieldSummaries).toHaveBeenCalledTimes(1);
      const rows = element.shadowRoot.querySelectorAll('[data-id="field-row"]');
      expect(rows).toHaveLength(1);
      expect(rows[0].textContent).toContain("Favorite Color");
    });

    it("the search box filters by label or API name, client-side", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getFieldSummaries.mockResolvedValue([
        fieldSummary({
          nodeKey: "f1",
          label: "Account Name",
          apiName: "Account.Name"
        }),
        fieldSummary({
          nodeKey: "f2",
          label: "Billing City",
          apiName: "Account.BillingCity"
        })
      ]);
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "fields");
      element.shadowRoot
        .querySelector('[data-id="show-fields-button"]')
        .click();
      await flushPromises();

      const searchInput = element.shadowRoot.querySelector(
        '[data-id="field-search-input"]'
      );
      searchInput.value = "billing";
      searchInput.dispatchEvent(new CustomEvent("input"));
      await flushPromises();

      const rows = element.shadowRoot.querySelectorAll('[data-id="field-row"]');
      expect(rows).toHaveLength(1);
      expect(rows[0].textContent).toContain("Billing City");
    });

    it("clicking a field row dispatches select with that field's nodeKey", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getFieldSummaries.mockResolvedValue([
        fieldSummary({ nodeKey: "f1", label: "Account Name" })
      ]);
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "fields");
      element.shadowRoot
        .querySelector('[data-id="show-fields-button"]')
        .click();
      await flushPromises();

      const handler = jest.fn();
      element.addEventListener("select", handler);
      element.shadowRoot.querySelector('[data-id="field-row"]').click();
      await flushPromises();

      expect(handler).toHaveBeenCalledTimes(1);
      expect(handler.mock.calls[0][0].detail.nodeKey).toBe("f1");
    });

    it("selecting a new node resets the field browser back to its unloaded, unfiltered state", async () => {
      getNodeDetail.mockResolvedValueOnce(objectDetail()).mockResolvedValueOnce(
        objectDetail({
          nodeKey: "contact",
          label: "Contact",
          secondaryKey: "Contact"
        })
      );
      getFieldSummaries.mockResolvedValue([
        fieldSummary({ nodeKey: "f1", label: "Account Name" })
      ]);
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "fields");
      element.shadowRoot
        .querySelector('[data-id="show-fields-button"]')
        .click();
      await flushPromises();
      expect(
        element.shadowRoot.querySelector('[data-id="fields-table"]')
      ).not.toBeNull();

      element.nodeKey = "contact";
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-id="fields-table"]')
      ).toBeNull();
      await expandSection(element, "fields");
      expect(
        element.shadowRoot.querySelector('[data-id="show-fields-button"]')
      ).not.toBeNull();
    });

    it("renders a sanitized error when getFieldSummaries fails", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getFieldSummaries.mockRejectedValue({
        body: { message: "You don't have permission to view org graph data." }
      });
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "fields");

      element.shadowRoot
        .querySelector('[data-id="show-fields-button"]')
        .click();
      await flushPromises();

      const fieldsError = element.shadowRoot.querySelector(
        '[data-id="fields-error"]'
      );
      expect(fieldsError).not.toBeNull();
      expect(fieldsError.state).toBe("error");
      expect(fieldsError.message).toContain("permission");
    });

    it('an object with zero scanned fields shows an honest empty state, never a "Show Fields" button with nothing behind it', async () => {
      getNodeDetail.mockResolvedValue(
        objectDetail({ outgoingRelationshipCounts: {} })
      );
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "fields");

      expect(
        element.shadowRoot.querySelector('[data-id="show-fields-button"]')
      ).toBeNull();
      const noFields = element.shadowRoot.querySelector(
        '[data-id="fields-none"]'
      );
      expect(noFields.state).toBe("true-zero");
      expect(noFields.message).toContain("no scanned fields");
    });
  });

  describe('Impact Analysis (forward/reverse, "Highlight on Graph")', () => {
    function impactResult(overrides) {
      return {
        rootNodeKey: "acct",
        direction: "forward",
        depth: 3,
        subgraph: {
          centerNodeKey: "acct",
          nodes: [
            {
              nodeKey: "acct",
              typeKey: "SalesforceMetadata.CustomObject",
              label: "Account",
              secondaryKey: "Account",
              state: "Active"
            }
          ],
          edges: [],
          frontier: [],
          hasMore: false,
          nextCursor: null
        },
        affectedComponents: [
          {
            nodeKey: "util",
            typeKey: "SalesforceMetadata.ApexClass",
            label: "Utils",
            hopDistance: 1,
            isInCycle: false
          }
        ],
        truncated: false,
        coverageCaveat:
          "Impact Analysis currently covers Apex class-to-class references only.",
        ...overrides
      };
    }

    it("collapsing the Impact section header hides its actions, and re-expanding restores them", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();

      const toggle = element.shadowRoot.querySelector(
        '[data-id="impact-section-toggle"]'
      );
      expect(toggle.getAttribute("aria-expanded")).toBe("false");
      expect(
        element.shadowRoot.querySelector('[data-id="impact-forward-button"]')
      ).toBeNull();

      toggle.click();
      await flushPromises();
      expect(toggle.getAttribute("aria-expanded")).toBe("true");
      expect(
        element.shadowRoot.querySelector('[data-id="impact-forward-button"]')
      ).not.toBeNull();

      toggle.click();
      await flushPromises();
      expect(toggle.getAttribute("aria-expanded")).toBe("false");
      expect(
        element.shadowRoot.querySelector('[data-id="impact-forward-button"]')
      ).toBeNull();
    });

    it("shows both Impact Analysis actions for a non-Apex node too — the feature is generic, never gated to a hardcoded node type", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "impact");

      expect(
        element.shadowRoot.querySelector('[data-id="impact-forward-button"]')
      ).not.toBeNull();
      expect(
        element.shadowRoot.querySelector('[data-id="impact-reverse-button"]')
      ).not.toBeNull();
      expect(getImpact).not.toHaveBeenCalled();
    });

    it('clicking "What does this depend on?" calls getImpact with direction forward and renders the coverage caveat plus affected components', async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getImpact.mockResolvedValue(impactResult());
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "impact");

      element.shadowRoot
        .querySelector('[data-id="impact-forward-button"]')
        .click();
      await flushPromises();

      expect(getImpact).toHaveBeenCalledWith({
        nodeKey: "account",
        direction: "forward",
        depth: null
      });
      expect(
        element.shadowRoot.querySelector('[data-id="impact-coverage-caveat"]')
          .textContent
      ).toContain("Impact Analysis currently covers");
      const rows = element.shadowRoot.querySelectorAll(
        '[data-id="impact-row"]'
      );
      expect(rows).toHaveLength(1);
      expect(rows[0].textContent).toContain("Utils");
    });

    /**
     * DE-14: an impact result can now legitimately mix metadata kinds (Apex classes,
     * triggers, Flows, permission sets — DE-8/DE-9/DE-11), whose consequences differ in
     * kind: an Apex class means code may break, a permission set means someone loses
     * ACCESS. The panel must lead with that composition and must never print a raw internal
     * typeKey at the user.
     */
    it("summarizes a mixed-metadata-type impact result by type and renders registry labels, never raw typeKeys (DE-14)", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getImpact.mockResolvedValue(
        impactResult({
          affectedComponents: [
            {
              nodeKey: "u1",
              typeKey: "SalesforceMetadata.ApexClass",
              label: "Utils",
              hopDistance: 1,
              isInCycle: false
            },
            {
              nodeKey: "u2",
              typeKey: "SalesforceMetadata.ApexClass",
              label: "Helper",
              hopDistance: 1,
              isInCycle: false
            },
            {
              nodeKey: "t1",
              typeKey: "SalesforceMetadata.ApexTrigger",
              label: "AccountTrigger",
              hopDistance: 1,
              isInCycle: false
            },
            {
              nodeKey: "p1",
              typeKey: "SalesforceMetadata.PermissionSet",
              label: "Sales_Access",
              hopDistance: 2,
              isInCycle: false
            }
          ]
        })
      );
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      element.registry = {
        nodeTypes: new Map([
          ["SalesforceMetadata.ApexClass", { displayLabel: "Apex Class" }],
          ["SalesforceMetadata.ApexTrigger", { displayLabel: "Apex Trigger" }],
          [
            "SalesforceMetadata.PermissionSet",
            { displayLabel: "Permission Set" }
          ]
        ]),
        edgeTypes: new Map()
      };
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "impact");

      element.shadowRoot
        .querySelector('[data-id="impact-forward-button"]')
        .click();
      await flushPromises();

      const breakdown = element.shadowRoot.querySelector(
        '[data-id="impact-type-breakdown"]'
      );
      expect(breakdown).not.toBeNull();
      expect(breakdown.textContent).toContain("2 Apex Classes");
      expect(breakdown.textContent).toContain("1 Apex Trigger");
      expect(breakdown.textContent).toContain("1 Permission Set");

      const tableText = element.shadowRoot.querySelector(
        '[data-id="impact-table"]'
      ).textContent;
      expect(tableText).toContain("Permission Set");
      expect(tableText).not.toContain("SalesforceMetadata.");
    });

    /** With only one type present the breakdown would merely restate the table's uniform Type column — suppressed rather than shown as a single redundant chip. */
    it("suppresses the type breakdown when every affected component is the same metadata type", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getImpact.mockResolvedValue(impactResult());
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "impact");

      element.shadowRoot
        .querySelector('[data-id="impact-forward-button"]')
        .click();
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-id="impact-type-breakdown"]')
      ).toBeNull();
      expect(
        element.shadowRoot.querySelectorAll('[data-id="impact-row"]')
      ).toHaveLength(1);
    });

    it('clicking "What depends on this?" calls getImpact with direction reverse', async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getImpact.mockResolvedValue(impactResult({ direction: "reverse" }));
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "impact");

      element.shadowRoot
        .querySelector('[data-id="impact-reverse-button"]')
        .click();
      await flushPromises();

      expect(getImpact).toHaveBeenCalledWith({
        nodeKey: "account",
        direction: "reverse",
        depth: null
      });
    });

    it("a component flagged isInCycle renders a Cycle badge", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getImpact.mockResolvedValue(
        impactResult({
          affectedComponents: [
            {
              nodeKey: "a",
              typeKey: "SalesforceMetadata.ApexClass",
              label: "A",
              hopDistance: 1,
              isInCycle: true
            }
          ]
        })
      );
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "impact");

      element.shadowRoot
        .querySelector('[data-id="impact-forward-button"]')
        .click();
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-id="impact-cycle-badge"]')
      ).not.toBeNull();
    });

    it("an empty affectedComponents list renders an honest empty state, not a blank table", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getImpact.mockResolvedValue(impactResult({ affectedComponents: [] }));
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "impact");

      element.shadowRoot
        .querySelector('[data-id="impact-forward-button"]')
        .click();
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-id="impact-empty"]').state
      ).toBe("true-zero");
      expect(
        element.shadowRoot.querySelector('[data-id="impact-table"]')
      ).toBeNull();
    });

    it("renders a sanitized error when getImpact fails", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getImpact.mockRejectedValue({
        body: { message: "You don't have permission to view org graph data." }
      });
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "impact");

      element.shadowRoot
        .querySelector('[data-id="impact-forward-button"]')
        .click();
      await flushPromises();

      const impactBanner = element.shadowRoot.querySelector(
        '[data-id="impact-error"]'
      );
      expect(impactBanner.state).toBe("error");
      expect(impactBanner.message).toContain("permission");
    });

    it('clicking "Highlight on Graph" dispatches highlightimpact with the root nodeKey and the fetched subgraph, unchanged', async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      const result = impactResult();
      getImpact.mockResolvedValue(result);
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "impact");
      element.shadowRoot
        .querySelector('[data-id="impact-forward-button"]')
        .click();
      await flushPromises();

      const handler = jest.fn();
      element.addEventListener("highlightimpact", handler);
      element.shadowRoot
        .querySelector('[data-id="impact-highlight-button"]')
        .click();

      expect(handler).toHaveBeenCalledTimes(1);
      expect(handler.mock.calls[0][0].detail.nodeKey).toBe("acct");
      expect(handler.mock.calls[0][0].detail.fragment).toBe(result.subgraph);
    });

    it("clicking an affected-component row dispatches select with that component's nodeKey, exactly like a field row", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getImpact.mockResolvedValue(impactResult());
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "impact");
      element.shadowRoot
        .querySelector('[data-id="impact-forward-button"]')
        .click();
      await flushPromises();

      const handler = jest.fn();
      element.addEventListener("select", handler);
      element.shadowRoot.querySelector('[data-id="impact-row"]').click();

      expect(handler).toHaveBeenCalledTimes(1);
      expect(handler.mock.calls[0][0].detail.nodeKey).toBe("util");
    });

    it("selecting a new node resets the Impact Analysis section back to its unloaded state", async () => {
      getNodeDetail.mockResolvedValueOnce(objectDetail()).mockResolvedValueOnce(
        objectDetail({
          nodeKey: "contact",
          label: "Contact",
          secondaryKey: "Contact"
        })
      );
      getImpact.mockResolvedValue(impactResult());
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "impact");
      element.shadowRoot
        .querySelector('[data-id="impact-forward-button"]')
        .click();
      await flushPromises();
      expect(
        element.shadowRoot.querySelector('[data-id="impact-coverage-caveat"]')
      ).not.toBeNull();

      element.nodeKey = "contact";
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-id="impact-coverage-caveat"]')
      ).toBeNull();
    });
  });

  describe("Sharing Settings section (Object mode, Tooling-API-sourced OWD)", () => {
    it("does not call getObjectSharingSettings on selection — it is collapsed by default and loads only when explicitly expanded", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();

      expect(getObjectSharingSettings).not.toHaveBeenCalled();
      expect(
        element.shadowRoot.querySelector('[data-id="sharing-settings-grid"]')
      ).toBeNull();
    });

    it("renders the internal and external sharing model once the section is expanded", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getObjectSharingSettings.mockResolvedValue({
        supported: true,
        unavailableReason: null,
        internalSharingModel: "ReadWrite",
        externalSharingModel: null
      });
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();

      await expandSection(element, "sharingSettings");

      expect(getObjectSharingSettings).toHaveBeenCalledWith({
        objectApiName: "Account"
      });
      const grid = element.shadowRoot.querySelector(
        '[data-id="sharing-settings-grid"]'
      );
      expect(grid.textContent).toContain("ReadWrite");
      expect(grid.textContent).toContain("Not enabled");
    });

    it("shows a loading skeleton while getObjectSharingSettings is in flight", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getObjectSharingSettings.mockReturnValue(new Promise(() => {}));
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();

      element.shadowRoot
        .querySelector('[data-section="sharingSettings"]')
        .click();
      await flushPromises();

      expect(
        element.shadowRoot.querySelector(
          '[data-id="sharing-settings-section"] c-oi-skeleton'
        )
      ).not.toBeNull();
    });

    it("renders a retryable error banner when getObjectSharingSettings fails", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getObjectSharingSettings.mockRejectedValue({
        body: { message: "Something went wrong loading sharing settings." }
      });
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "sharingSettings");

      const banner = element.shadowRoot.querySelector(
        '[data-id="object-sharing-settings-error"]'
      );
      expect(banner).not.toBeNull();

      getObjectSharingSettings.mockResolvedValue({
        supported: true,
        unavailableReason: null,
        internalSharingModel: "Private",
        externalSharingModel: "Private"
      });
      banner.dispatchEvent(new CustomEvent("retry"));
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-id="sharing-settings-grid"]')
          .textContent
      ).toContain("Private");
    });

    it("renders an honest unsupported state when the Tooling API could not resolve a sharing model", async () => {
      getNodeDetail.mockResolvedValue(objectDetail());
      getObjectSharingSettings.mockResolvedValue({
        supported: false,
        unavailableReason:
          "No sharing model information was found for this object.",
        internalSharingModel: null,
        externalSharingModel: null
      });
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "sharingSettings");

      expect(
        element.shadowRoot.querySelector('[data-id="sharing-settings-grid"]')
      ).toBeNull();
      expect(
        element.shadowRoot.querySelector(
          '[data-id="object-sharing-settings-unsupported"]'
        ).message
      ).toBe("No sharing model information was found for this object.");
    });

    it("clears sharing settings when the selected object changes, so a previous object's OWD never bleeds into the newly-selected one", async () => {
      getNodeDetail
        .mockResolvedValueOnce(objectDetail())
        .mockResolvedValueOnce(
          objectDetail({
            nodeKey: "contact",
            label: "Contact",
            secondaryKey: "Contact"
          })
        );
      getObjectSharingSettings.mockResolvedValueOnce({
        supported: true,
        unavailableReason: null,
        internalSharingModel: "ReadWrite",
        externalSharingModel: null
      });
      const element = createElement("c-oi-node-detail-panel", {
        is: OiNodeDetailPanel
      });
      document.body.appendChild(element);
      element.nodeKey = "account";
      await flushPromises();
      await expandSection(element, "sharingSettings");
      expect(
        element.shadowRoot.querySelector('[data-id="sharing-settings-grid"]')
      ).not.toBeNull();

      element.nodeKey = "contact";
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-id="sharing-settings-grid"]')
      ).toBeNull();
    });
  });
});
