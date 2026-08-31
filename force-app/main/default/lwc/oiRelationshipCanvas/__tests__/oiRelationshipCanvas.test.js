import { createElement } from "lwc";
import OiRelationshipCanvas from "c/oiRelationshipCanvas";

const OBJECT_TYPE_KEY = "SalesforceMetadata.CustomObject";
const FIELD_TYPE_KEY = "SalesforceMetadata.CustomField";
const HAS_FIELD = "SalesforceMetadata.HAS_FIELD";
const LOOKUP_TO = "SalesforceMetadata.LOOKUP_TO";
const MASTER_DETAIL_TO = "SalesforceMetadata.MASTER_DETAIL_TO";

function objectNode(nodeKey, label, secondaryKey) {
  return {
    nodeKey,
    typeKey: OBJECT_TYPE_KEY,
    label,
    secondaryKey,
    iconName: "standard:account",
    colorToken: "neutral",
    typeLabel: "Object"
  };
}

function fieldNode(nodeKey, label) {
  return { nodeKey, typeKey: FIELD_TYPE_KEY, label, secondaryKey: label };
}

function apexClassNode(nodeKey, label) {
  return {
    nodeKey,
    typeKey: "SalesforceMetadata.ApexClass",
    label,
    secondaryKey: label,
    iconName: "standard:apex",
    colorToken: "neutral"
  };
}

function hasFieldEdge(ownerKey, fieldKey) {
  return {
    edgeKey: ownerKey + "-hf-" + fieldKey,
    typeKey: HAS_FIELD,
    sourceNodeKey: ownerKey,
    targetNodeKey: fieldKey
  };
}

function lookupEdge(
  fieldKey,
  referencedObjectKey,
  viaFieldApiName,
  typeKey = LOOKUP_TO
) {
  return {
    edgeKey: fieldKey + "-lu-" + referencedObjectKey,
    typeKey,
    sourceNodeKey: fieldKey,
    targetNodeKey: referencedObjectKey,
    viaFieldApiName
  };
}

/** Uses a business-flavored lookup field name (not Owner/CreatedBy/LastModifiedBy) deliberately: the default relationship-visibility mode is Business-only, so a fixture meant to exercise ordinary connector/interaction behavior must not accidentally be filtered out by the System classification under test elsewhere in this suite. */
function baseFixture() {
  return {
    nodes: [
      objectNode("account", "Account", "Account"),
      objectNode("user", "User", "User"),
      objectNode("opportunity", "Opportunity", "Opportunity"),
      fieldNode("accountManagerId", "AccountManagerId"),
      fieldNode("accountId", "AccountId")
    ],
    edges: [
      hasFieldEdge("account", "accountManagerId"),
      lookupEdge("accountManagerId", "user", "AccountManagerId"),
      hasFieldEdge("opportunity", "accountId"),
      lookupEdge("accountId", "account", "AccountId", MASTER_DETAIL_TO)
    ]
  };
}

function renderCanvas({ nodes, edges, centerNodeKey, mode }) {
  const element = createElement("c-oi-relationship-canvas", {
    is: OiRelationshipCanvas
  });
  element.nodes = nodes;
  element.edges = edges;
  if (mode) {
    element.mode = mode;
  }
  element.centerNodeKey = centerNodeKey;
  document.body.appendChild(element);
  return element;
}

const RECORD_LOOKUP_TO = "SalesforceRecord.LOOKUP_TO";
const RECORD_CHILD_OF = "SalesforceRecord.CHILD_OF";

function recordKey(objectApiName, recordId) {
  return `Record::${objectApiName}::${recordId}`;
}

function recordNode(objectApiName, recordId, label) {
  return {
    nodeKey: recordKey(objectApiName, recordId),
    typeKey: `SalesforceRecord.${objectApiName}`,
    label,
    secondaryKey: objectApiName,
    iconName: "standard:record",
    colorToken: "neutral"
  };
}

function recordEdge(typeKey, sourceKey, targetKey) {
  return {
    edgeKey: `${sourceKey}-${targetKey}`,
    typeKey,
    sourceNodeKey: sourceKey,
    targetNodeKey: targetKey
  };
}

describe("c-oi-relationship-canvas", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  describe("Object-only card filter", () => {
    it("renders only Object cards, never Field/ApexClass/ApexTrigger/Flow/PermissionSet cards", () => {
      const fixture = baseFixture();
      fixture.nodes.push(apexClassNode("apexClass1", "AccountHelper"));
      fixture.edges.push({
        edgeKey: "e-apex",
        typeKey: "SalesforceMetadata.EXECUTES_ON",
        sourceNodeKey: "apexClass1",
        targetNodeKey: "account"
      });
      const element = renderCanvas({ ...fixture, centerNodeKey: "account" });

      return Promise.resolve().then(() => {
        const allCardTitles = [
          ...element.shadowRoot.querySelectorAll(".oi-orc-card-title")
        ].map((el) => el.textContent);
        expect(allCardTitles).not.toContain("AccountHelper");
        expect(allCardTitles).not.toContain("AccountManagerId");
        expect(allCardTitles).not.toContain("AccountId");
        expect(
          element.shadowRoot.querySelectorAll(
            '[data-id="incoming-card"], [data-id="outgoing-card"]'
          ).length
        ).toBeGreaterThan(0);
      });
    });
  });

  describe("lane layout", () => {
    it("renders the centered object prominently in the center card", () => {
      const fixture = baseFixture();
      const element = renderCanvas({ ...fixture, centerNodeKey: "account" });

      return Promise.resolve().then(() => {
        const centerCard = element.shadowRoot.querySelector(
          '[data-id="center-card"]'
        );
        expect(centerCard).not.toBeNull();
        expect(centerCard.textContent).toContain("Account");
        expect(centerCard.textContent).toContain("Standard Object");
      });
    });

    it("places an object that references the center among the incoming cards, not the outgoing cards", () => {
      const fixture = baseFixture();
      const element = renderCanvas({ ...fixture, centerNodeKey: "account" });

      return Promise.resolve().then(() => {
        const incomingCards = [
          ...element.shadowRoot.querySelectorAll('[data-id="incoming-card"]')
        ]
          .map((el) => el.textContent)
          .join(" ");
        const outgoingCards = [
          ...element.shadowRoot.querySelectorAll('[data-id="outgoing-card"]')
        ]
          .map((el) => el.textContent)
          .join(" ");
        expect(incomingCards).toContain("Opportunity");
        expect(outgoingCards).not.toContain("Opportunity");
      });
    });

    it("places an object the center references among the outgoing cards, not the incoming cards", () => {
      const fixture = baseFixture();
      const element = renderCanvas({ ...fixture, centerNodeKey: "account" });

      return Promise.resolve().then(() => {
        const incomingCards = [
          ...element.shadowRoot.querySelectorAll('[data-id="incoming-card"]')
        ]
          .map((el) => el.textContent)
          .join(" ");
        const outgoingCards = [
          ...element.shadowRoot.querySelectorAll('[data-id="outgoing-card"]')
        ]
          .map((el) => el.textContent)
          .join(" ");
        expect(outgoingCards).toContain("User");
        expect(incomingCards).not.toContain("User");
      });
    });

    it("renders a self-referencing relationship as its own dedicated self card, not among the incoming/outgoing cards", () => {
      const nodes = [
        objectNode("account", "Account", "Account"),
        fieldNode("parentId", "ParentId")
      ];
      const edges = [
        hasFieldEdge("account", "parentId"),
        lookupEdge("parentId", "account", "ParentId")
      ];
      const element = renderCanvas({ nodes, edges, centerNodeKey: "account" });

      return Promise.resolve().then(() => {
        const selfCard = element.shadowRoot.querySelector(
          '[data-id="self-card"]'
        );
        expect(selfCard).not.toBeNull();
        expect(selfCard.textContent).toContain("Account (Self)");
        const selfConnector = element.shadowRoot.querySelector(
          '[data-id="self-connector"]'
        );
        expect(selfConnector.textContent).toContain("ParentId");
        expect(
          element.shadowRoot.querySelector('[data-id="incoming-empty"]')
        ).not.toBeNull();
        expect(
          element.shadowRoot.querySelector('[data-id="outgoing-empty"]')
        ).not.toBeNull();
      });
    });

    it("shows an honest empty-lane message when there are no incoming/outgoing relationships", () => {
      const nodes = [objectNode("lonely", "Lonely Object", "Lonely__c")];
      const element = renderCanvas({
        nodes,
        edges: [],
        centerNodeKey: "lonely"
      });

      return Promise.resolve().then(() => {
        expect(
          element.shadowRoot.querySelector('[data-id="incoming-empty"]')
            .textContent
        ).toContain("No objects reference");
        expect(
          element.shadowRoot.querySelector('[data-id="outgoing-empty"]')
            .textContent
        ).toContain("references no other objects");
      });
    });

    /**
     * Regression for a real, live-org-confirmed defect: the card-to-trunk segment used to be
     * a single fixed width regardless of what the connector's own label said, so any label
     * wider than that fixed gap (routine for aggregated connectors, e.g. "3 Lookup
     * Relationships") had its opaque background visually cut across the shared vertical
     * trunk line instead of sitting cleanly within its own segment. Asserted here by parsing
     * the incoming connector's own rounded-elbow path (buildElbowPath) for its first "H <x>"
     * segment — the approach into the trunk's corner — a longer label must push that corner
     * farther out, never the same fixed value regardless of label length.
     */
    it("gives a connector with a long label more room before the trunk than one with a short label, instead of a fixed gap regardless of label length", () => {
      const shortLabelFixture = {
        nodes: [
          objectNode("account", "Account", "Account"),
          objectNode("opp", "Opportunity", "Opportunity"),
          fieldNode("oppAcct", "AccountId")
        ],
        edges: [
          hasFieldEdge("opp", "oppAcct"),
          lookupEdge("oppAcct", "account", "AccountId")
        ]
      };
      const longLabelFixture = {
        nodes: [
          objectNode("account", "Account", "Account"),
          objectNode("opp", "Opportunity", "Opportunity"),
          fieldNode(
            "oppAcct",
            "ThisIsADeliberatelyVeryLongCustomLookupFieldApiName__c"
          )
        ],
        edges: [
          hasFieldEdge("opp", "oppAcct"),
          lookupEdge(
            "oppAcct",
            "account",
            "ThisIsADeliberatelyVeryLongCustomLookupFieldApiName__c"
          )
        ]
      };

      function trunkXFor(fixture) {
        const element = renderCanvas({ ...fixture, centerNodeKey: "account" });
        return Promise.resolve().then(() => {
          const branchPath = element.shadowRoot
            .querySelector('[data-id="incoming-card"]')
            .closest("svg")
            .querySelector("path.oi-orc-connector-line-incoming");
          const match = /H\s+([\d.]+)/.exec(branchPath.getAttribute("d"));
          return Number(match[1]);
        });
      }

      return Promise.all([
        trunkXFor(shortLabelFixture),
        trunkXFor(longLabelFixture)
      ]).then(([shortTrunkX, longTrunkX]) => {
        expect(longTrunkX).toBeGreaterThan(shortTrunkX);
      });
    });
  });

  describe("relationship connector correctness", () => {
    it("shows the field API name and relationship type on the connector", () => {
      const fixture = baseFixture();
      const element = renderCanvas({ ...fixture, centerNodeKey: "account" });

      return Promise.resolve().then(() => {
        const outgoingConnector = element.shadowRoot.querySelector(
          '[data-id="outgoing-connector"]'
        );
        expect(outgoingConnector.textContent).toContain("AccountManagerId");
        expect(outgoingConnector.textContent).toContain("Lookup");

        const incomingConnector = element.shadowRoot.querySelector(
          '[data-id="incoming-connector"]'
        );
        expect(incomingConnector.textContent).toContain("AccountId");
        expect(incomingConnector.textContent).toContain("Master-Detail");
      });
    });

    it('aggregates multiple relationship fields between the same object pair into one connector stating the count plainly, never a cryptic "+N"', () => {
      const nodes = [
        objectNode("account", "Account", "Account"),
        objectNode("user", "User", "User"),
        fieldNode("accountManagerId", "AccountManagerId"),
        fieldNode("regionalDirectorId", "RegionalDirectorId")
      ];
      const edges = [
        hasFieldEdge("account", "accountManagerId"),
        lookupEdge("accountManagerId", "user", "AccountManagerId"),
        hasFieldEdge("account", "regionalDirectorId"),
        lookupEdge("regionalDirectorId", "user", "RegionalDirectorId")
      ];
      const element = renderCanvas({ nodes, edges, centerNodeKey: "account" });

      return Promise.resolve().then(() => {
        const outgoingConnector = element.shadowRoot.querySelector(
          '[data-id="outgoing-connector"]'
        );
        expect(outgoingConnector.textContent).toContain(
          "2 Lookup Relationships"
        );
        expect(outgoingConnector.textContent).not.toContain("+");
      });
    });

    it("clicking an aggregated connector emits edgeclick with every field, so the caller can open the full detail — no separate inline expand affordance to keep in sync", () => {
      const nodes = [
        objectNode("account", "Account", "Account"),
        objectNode("user", "User", "User"),
        fieldNode("accountManagerId", "AccountManagerId"),
        fieldNode("regionalDirectorId", "RegionalDirectorId")
      ];
      const edges = [
        hasFieldEdge("account", "accountManagerId"),
        lookupEdge("accountManagerId", "user", "AccountManagerId"),
        hasFieldEdge("account", "regionalDirectorId"),
        lookupEdge("regionalDirectorId", "user", "RegionalDirectorId")
      ];
      const element = renderCanvas({ nodes, edges, centerNodeKey: "account" });
      const handler = jest.fn();
      element.addEventListener("edgeclick", handler);

      return Promise.resolve().then(() => {
        element.shadowRoot
          .querySelector('[data-id="outgoing-connector"]')
          .click();
        expect(handler).toHaveBeenCalledTimes(1);
        const fields = handler.mock.calls[0][0].detail.connector.fields
          .map((f) => f.fieldApiName)
          .sort();
        expect(fields).toEqual(["AccountManagerId", "RegionalDirectorId"]);
      });
    });
  });

  describe("system vs. business relationship visibility", () => {
    function systemAndBusinessFixture() {
      return {
        nodes: [
          objectNode("account", "Account", "Account"),
          objectNode("user", "User", "User"),
          objectNode("territory", "Territory", "Territory"),
          fieldNode("ownerId", "OwnerId"),
          fieldNode("territoryId", "TerritoryId")
        ],
        edges: [
          hasFieldEdge("account", "ownerId"),
          lookupEdge("ownerId", "user", "OwnerId"),
          hasFieldEdge("account", "territoryId"),
          lookupEdge("territoryId", "territory", "TerritoryId")
        ]
      };
    }

    function outgoingCardText(element) {
      return [
        ...element.shadowRoot.querySelectorAll('[data-id="outgoing-card"]')
      ]
        .map((el) => el.textContent)
        .join(" ");
    }

    it("defaults to Business relationships only, hiding a pure system relationship (OwnerId)", () => {
      const element = renderCanvas({
        ...systemAndBusinessFixture(),
        centerNodeKey: "account"
      });

      return Promise.resolve().then(() => {
        expect(outgoingCardText(element)).toContain("Territory");
        expect(outgoingCardText(element)).not.toContain("User");
      });
    });

    it("reveals the system relationship when the System toggle is selected", () => {
      const element = renderCanvas({
        ...systemAndBusinessFixture(),
        centerNodeKey: "account"
      });

      return Promise.resolve()
        .then(() => {
          element.shadowRoot.querySelector('[data-mode="system"]').click();
          return Promise.resolve();
        })
        .then(() => {
          expect(outgoingCardText(element)).toContain("User");
          expect(outgoingCardText(element)).not.toContain("Territory");
        });
    });

    it("shows every relationship when the All toggle is selected, never permanently hiding system relationships", () => {
      const element = renderCanvas({
        ...systemAndBusinessFixture(),
        centerNodeKey: "account"
      });

      return Promise.resolve()
        .then(() => {
          element.shadowRoot.querySelector('[data-mode="all"]').click();
          return Promise.resolve();
        })
        .then(() => {
          expect(outgoingCardText(element)).toContain("User");
          expect(outgoingCardText(element)).toContain("Territory");
        });
    });
  });

  describe("interactions", () => {
    it("emits select with the counterpart nodeKey when a neighbor card is clicked", () => {
      const fixture = baseFixture();
      const element = renderCanvas({ ...fixture, centerNodeKey: "account" });
      const handler = jest.fn();
      element.addEventListener("select", handler);

      return Promise.resolve().then(() => {
        element.shadowRoot.querySelector('[data-id="outgoing-card"]').click();
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail.nodeKey).toBe("user");
      });
    });

    it("emits open without selecting when a neighbor card open action is clicked", async () => {
      const fixture = baseFixture();
      const element = renderCanvas({ ...fixture, centerNodeKey: "account" });
      const openHandler = jest.fn();
      const selectHandler = jest.fn();
      element.addEventListener("open", openHandler);
      element.addEventListener("select", selectHandler);
      await Promise.resolve();

      element.shadowRoot.querySelector('[data-id="open-card"]').click();
      expect(openHandler).toHaveBeenCalledTimes(1);
      expect(openHandler.mock.calls[0][0].detail.nodeKey).toBeTruthy();
      expect(selectHandler).not.toHaveBeenCalled();
    });

    it('shows a contextual "Explore From Here" action only after a card is selected, never as a permanent per-card link', () => {
      const fixture = baseFixture();
      const element = renderCanvas({ ...fixture, centerNodeKey: "account" });
      const exploreHandler = jest.fn();
      element.addEventListener("explorefromhere", exploreHandler);

      return Promise.resolve()
        .then(() => {
          expect(
            element.shadowRoot.querySelector('[data-id="explore-from-here"]')
          ).toBeNull();
          element.shadowRoot.querySelector('[data-id="outgoing-card"]').click();
          return Promise.resolve();
        })
        .then(() => {
          const exploreButton = element.shadowRoot.querySelector(
            '[data-id="explore-from-here"]'
          );
          expect(exploreButton).not.toBeNull();
          exploreButton.click();
          expect(exploreHandler).toHaveBeenCalledTimes(1);
          expect(exploreHandler.mock.calls[0][0].detail.nodeKey).toBe("user");
        });
    });

    it("emits edgeclick with the full connector descriptor when a connector is clicked", () => {
      const fixture = baseFixture();
      const element = renderCanvas({ ...fixture, centerNodeKey: "account" });
      const handler = jest.fn();
      element.addEventListener("edgeclick", handler);

      return Promise.resolve().then(() => {
        element.shadowRoot
          .querySelector('[data-id="outgoing-connector"]')
          .click();
        expect(handler).toHaveBeenCalledTimes(1);
        const detail = handler.mock.calls[0][0].detail;
        expect(detail.connector.direction).toBe("outgoing");
        expect(detail.connector.counterpartObject.nodeKey).toBe("user");
        expect(detail.rootObject.nodeKey).toBe("account");
      });
    });

    it('reveals additional connectors client-side via "show more" without emitting any fetch-triggering event', () => {
      const nodes = [objectNode("account", "Account", "Account")];
      const edges = [];
      const objectLetters = ["a", "b", "c", "d", "e", "f", "g", "h"];
      for (const letter of objectLetters) {
        nodes.push(
          objectNode(
            "obj" + letter,
            "Object " + letter,
            "Object_" + letter + "__c"
          )
        );
        nodes.push(fieldNode("field" + letter, "Field" + letter + "Id"));
        edges.push(hasFieldEdge("account", "field" + letter));
        edges.push(
          lookupEdge("field" + letter, "obj" + letter, "Field" + letter + "Id")
        );
      }
      const element = renderCanvas({ nodes, edges, centerNodeKey: "account" });
      const expandHandler = jest.fn();
      element.addEventListener("expand", expandHandler);

      return Promise.resolve()
        .then(() => {
          expect(
            element.shadowRoot.querySelectorAll('[data-id="outgoing-card"]')
          ).toHaveLength(6);
          const showMore = element.shadowRoot.querySelector(
            '[data-id="show-more-outgoing"]'
          );
          expect(showMore).not.toBeNull();
          expect(showMore.textContent).toContain("2 more");
          showMore.click();
          return Promise.resolve();
        })
        .then(() => {
          expect(
            element.shadowRoot.querySelectorAll('[data-id="outgoing-card"]')
          ).toHaveLength(8);
          expect(
            element.shadowRoot.querySelector('[data-id="show-more-outgoing"]')
          ).toBeNull();
          expect(expandHandler).not.toHaveBeenCalled();
        });
    });
  });

  describe("legend", () => {
    it("shows only Lookup/Master-Detail/Self/System relationship concepts, never Executes On or Grants Access To", () => {
      const fixture = baseFixture();
      const element = renderCanvas({ ...fixture, centerNodeKey: "account" });

      return Promise.resolve().then(() => {
        const legend = element.shadowRoot.querySelector('[data-id="legend"]');
        expect(legend.textContent).toContain("Lookup");
        expect(legend.textContent).toContain("Master-Detail");
        expect(legend.textContent).toContain("Self Relationship");
        expect(legend.textContent).toContain("System Relationship");
        expect(legend.textContent).not.toContain("Executes On");
        expect(legend.textContent).not.toContain("Grants Access To");
      });
    });

    /** VisualDesignSpecification.md §3.4: legend docked lower-left and zoom controls docked lower-right, in the SAME persistent footer region — never a legend row and a separately-floating zoom widget. */
    it("docks the legend and the zoom controls inside the same persistent canvas footer", () => {
      const fixture = baseFixture();
      const element = renderCanvas({ ...fixture, centerNodeKey: "account" });

      return Promise.resolve().then(() => {
        const footer = element.shadowRoot.querySelector(
          '[data-id="canvas-footer"]'
        );
        expect(footer).not.toBeNull();
        expect(footer.querySelector('[data-id="legend"]')).not.toBeNull();
        expect(
          footer.querySelector('[data-id="zoom-controls"]')
        ).not.toBeNull();
      });
    });
  });

  describe("neighbor card contract (VisualDesignSpecification.md §5)", () => {
    it("shows a divider and a relationship field/type footer on the card itself, not only on the floating connector label", () => {
      const fixture = baseFixture();
      const element = renderCanvas({ ...fixture, centerNodeKey: "account" });

      return Promise.resolve().then(() => {
        const outgoingCard = element.shadowRoot.querySelector(
          '[data-id="outgoing-card"]'
        );
        expect(
          outgoingCard.querySelector(".oi-orc-card-divider")
        ).not.toBeNull();
        const footer = outgoingCard.querySelector(".oi-orc-card-footer");
        expect(footer).not.toBeNull();
        expect(footer.textContent).toContain("AccountManagerId");
        expect(footer.textContent).toContain("Lookup");

        const incomingCard = element.shadowRoot.querySelector(
          '[data-id="incoming-card"]'
        );
        const incomingFooter = incomingCard.querySelector(
          ".oi-orc-card-footer"
        );
        expect(incomingFooter.textContent).toContain("AccountId");
        expect(incomingFooter.textContent).toContain("Master-Detail");
      });
    });
  });

  describe("accessibility", () => {
    it("composes an aria-label from real relationship data, never a raw typeKey", () => {
      const fixture = baseFixture();
      const element = renderCanvas({ ...fixture, centerNodeKey: "account" });

      return Promise.resolve().then(() => {
        const outgoingCard = element.shadowRoot.querySelector(
          '[data-id="outgoing-card"]'
        );
        const ariaLabel = outgoingCard.getAttribute("aria-label");
        expect(ariaLabel).toContain("Account");
        expect(ariaLabel).toContain("User");
        expect(ariaLabel).toContain("AccountManagerId");
        expect(ariaLabel).toContain("Lookup");
        expect(ariaLabel).not.toContain("SalesforceMetadata");
      });
    });

    it("every neighbor card is keyboard-focusable and activatable with Enter", () => {
      const fixture = baseFixture();
      const element = renderCanvas({ ...fixture, centerNodeKey: "account" });
      const handler = jest.fn();
      element.addEventListener("select", handler);

      return Promise.resolve().then(() => {
        const card = element.shadowRoot.querySelector(
          '[data-id="outgoing-card"]'
        );
        expect(card.getAttribute("tabindex")).toBe("0");
        card.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }));
        expect(handler).toHaveBeenCalledTimes(1);
        card.dispatchEvent(new KeyboardEvent("keydown", { key: "Tab" }));
        expect(handler).toHaveBeenCalledTimes(1);
      });
    });
  });

  describe("zoom (self-relationship dead-zone regression)", () => {
    it("shrinks the SVG's own rendered width/height with zoom-out instead of a CSS transform, so the diagram-wrapper's scrollable area shrinks in lockstep and no dead space opens up around the self-relationship lane", () => {
      const nodes = [
        objectNode("account", "Account", "Account"),
        fieldNode("parentId", "ParentId")
      ];
      const edges = [
        hasFieldEdge("account", "parentId"),
        lookupEdge("parentId", "account", "ParentId")
      ];
      const element = renderCanvas({ nodes, edges, centerNodeKey: "account" });

      return Promise.resolve()
        .then(() => {
          const svg = element.shadowRoot.querySelector('[data-id="orc-svg"]');
          expect(svg.getAttribute("style")).toBeFalsy();
          const fullWidth = Number(svg.getAttribute("width"));
          const fullHeight = Number(svg.getAttribute("height"));
          expect(fullWidth).toBeGreaterThan(0);
          expect(fullHeight).toBeGreaterThan(0);

          element.shadowRoot.querySelector('[data-id="zoom-out"]').click();
          return Promise.resolve().then(() => ({ fullWidth, fullHeight }));
        })
        .then(({ fullWidth, fullHeight }) => {
          const svg = element.shadowRoot.querySelector('[data-id="orc-svg"]');
          // viewBox stays the full, unscaled coordinate space — only the rendered box shrinks.
          expect(svg.getAttribute("viewBox")).toBe(
            `0 0 ${fullWidth} ${fullHeight}`
          );
          expect(Number(svg.getAttribute("width"))).toBeLessThan(fullWidth);
          expect(Number(svg.getAttribute("height"))).toBeLessThan(fullHeight);
        });
    });
  });

  describe("Record analyze mode (ADR-0024 — shares this canvas with Object mode)", () => {
    function recordFixture() {
      return {
        nodes: [
          recordNode("Account", "001x1", "Acme Corp"),
          recordNode("Contact", "003x1", "Jane Doe"),
          recordNode("User", "005x1", "Jane Admin")
        ],
        edges: [
          recordEdge(
            RECORD_CHILD_OF,
            recordKey("Account", "001x1"),
            recordKey("Contact", "003x1")
          ),
          recordEdge(
            RECORD_LOOKUP_TO,
            recordKey("Account", "001x1"),
            recordKey("User", "005x1")
          )
        ]
      };
    }

    it("renders the centered record in the center card, labeled as a Record rather than a Standard/Custom Object", () => {
      const element = renderCanvas({
        ...recordFixture(),
        centerNodeKey: recordKey("Account", "001x1"),
        mode: "Record"
      });

      return Promise.resolve().then(() => {
        const centerCard = element.shadowRoot.querySelector(
          '[data-id="center-card"]'
        );
        expect(centerCard.textContent).toContain("Acme Corp");
        expect(centerCard.textContent).toContain("Account Record");
        expect(centerCard.textContent).not.toContain("Standard Object");
      });
    });

    it("places a child record among the incoming cards and a parent lookup among the outgoing cards, under Record-mode lane titles", () => {
      const element = renderCanvas({
        ...recordFixture(),
        centerNodeKey: recordKey("Account", "001x1"),
        mode: "Record"
      });

      return Promise.resolve().then(() => {
        expect(
          element.shadowRoot.querySelector('[data-id="incoming-card"]')
            .textContent
        ).toContain("Jane Doe");
        expect(
          element.shadowRoot.querySelector('[data-id="outgoing-card"]')
            .textContent
        ).toContain("Jane Admin");
        const laneTitles = [
          ...element.shadowRoot.querySelectorAll(".oi-orc-lane-title")
        ]
          .map((el) => el.textContent)
          .join(" ");
        expect(laneTitles).toContain("Records Referencing This Record");
        expect(laneTitles).toContain("Records This Record References");
      });
    });

    it('labels a fieldless connector plainly as "Related Record" rather than a field-shaped string with nothing to fill it', () => {
      const element = renderCanvas({
        ...recordFixture(),
        centerNodeKey: recordKey("Account", "001x1"),
        mode: "Record"
      });

      return Promise.resolve().then(() => {
        const outgoingConnector = element.shadowRoot.querySelector(
          '[data-id="outgoing-connector"]'
        );
        expect(outgoingConnector.textContent.trim()).toBe("Related Record");
        expect(outgoingConnector.textContent).not.toContain("·");
        expect(outgoingConnector.textContent).not.toContain("undefined");
      });
    });

    it("hides the Business/System/All toggle entirely — Record mode has no field-level detail to classify System vs. Business by", () => {
      const element = renderCanvas({
        ...recordFixture(),
        centerNodeKey: recordKey("Account", "001x1"),
        mode: "Record"
      });

      return Promise.resolve().then(() => {
        expect(
          element.shadowRoot.querySelector(".oi-orc-visibility-toggle-group")
        ).toBeNull();
        expect(
          element.shadowRoot.querySelector('[data-id="legend"]').textContent
        ).not.toContain("System Relationship");
      });
    });

    it("treats a same-object-type counterpart record as a dedicated self card naming the ACTUAL related record, not the center's own name", () => {
      const nodes = [
        recordNode("Account", "001x1", "Acme Corp"),
        recordNode("Account", "001x2", "Acme Corp — West")
      ];
      const edges = [
        recordEdge(
          RECORD_LOOKUP_TO,
          recordKey("Account", "001x1"),
          recordKey("Account", "001x2")
        )
      ];
      const element = renderCanvas({
        nodes,
        edges,
        centerNodeKey: recordKey("Account", "001x1"),
        mode: "Record"
      });

      return Promise.resolve().then(() => {
        const selfCard = element.shadowRoot.querySelector(
          '[data-id="self-card"]'
        );
        expect(selfCard.textContent).toContain("Acme Corp — West (Self)");
        expect(selfCard.textContent).not.toContain("Acme Corp (Self)");
        expect(
          element.shadowRoot.querySelector('[data-id="incoming-card"]')
        ).toBeNull();
        expect(
          element.shadowRoot.querySelector('[data-id="outgoing-card"]')
        ).toBeNull();
      });
    });

    it('"Explore From Here" on a related record card emits the RECORD nodeKey, for oiGraphExplorer to re-center via selectAndCenterRecord', () => {
      const element = renderCanvas({
        ...recordFixture(),
        centerNodeKey: recordKey("Account", "001x1"),
        mode: "Record"
      });
      const exploreHandler = jest.fn();
      element.addEventListener("explorefromhere", exploreHandler);

      return Promise.resolve()
        .then(() => {
          element.shadowRoot.querySelector('[data-id="outgoing-card"]').click();
          return Promise.resolve();
        })
        .then(() => {
          const exploreButton = element.shadowRoot.querySelector(
            '[data-id="explore-from-here"]'
          );
          exploreButton.click();
          expect(exploreHandler).toHaveBeenCalledTimes(1);
          expect(exploreHandler.mock.calls[0][0].detail.nodeKey).toBe(
            recordKey("User", "005x1")
          );
        });
    });
  });

  describe('re-centering resets local view state (GraphUI.md §11\'s "a fresh center is a fresh view", live-org-validated regression)', () => {
    it("resets the Business/System/All toggle and any expanded connector back to their defaults when centerNodeKey changes", () => {
      const fixture = baseFixture();
      const element = renderCanvas({ ...fixture, centerNodeKey: "account" });

      return Promise.resolve()
        .then(() => {
          element.shadowRoot.querySelector('[data-mode="all"]').click();
          return Promise.resolve();
        })
        .then(() => {
          expect(
            element.shadowRoot
              .querySelector('[data-mode="all"]')
              .getAttribute("aria-pressed")
          ).toBe("true");
          element.centerNodeKey = "user";
          element.nodes = [
            objectNode("user", "User", "User"),
            objectNode("account", "Account", "Account")
          ];
          element.edges = [];
          return Promise.resolve();
        })
        .then(() => {
          expect(
            element.shadowRoot
              .querySelector('[data-mode="business"]')
              .getAttribute("aria-pressed")
          ).toBe("true");
          expect(
            element.shadowRoot
              .querySelector('[data-mode="all"]')
              .getAttribute("aria-pressed")
          ).toBe("false");
        });
    });
  });
});
