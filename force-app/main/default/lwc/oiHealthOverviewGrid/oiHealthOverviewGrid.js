/**
 * Purpose: Org Health's landing grid (OrgHealthVisualDesignSpecification.md, pixel-fidelity
 *          bound view #1 per ADR-0026 §0.4) — the KPI strip plus one category card per
 *          section (excluding Org Overview itself, which the KPI strip already represents).
 * Responsibilities: Shape OI_OrgOverviewDTO into the 8 KPI tiles and OI_OrgHealthSectionSummaryDTO
 *                    rows into category cards, and emit `selectsection` when a card is
 *                    clicked. Every score/severity/topSignal value is read verbatim from the
 *                    caller-supplied DTOs — this component never computes one.
 * Dependencies: oiHealthKpiTile, oiHealthScoreRing, oiHealthSeverityBadge.
 */
import { LightningElement, api } from "lwc";

const ORG_OVERVIEW_SECTION_KEY = "OrgOverview";

/** Fixed product taxonomy (there are, and only ever will be, these named Org Health sections) — a UI-identity lookup, not business data, so it is hardcoded here rather than added to OI_Org_Health_Section_Config__mdt, matching the precedent set by oiGraphNode.js/oiSchemaObjectCard.js's own per-type color maps. */
/*
 * Normalized onto ADR-0028's --oi-color-identity-* ramp — the categorical channel, deliberately
 * separate from both accent and severity.
 *
 * This map previously bound section identity to SEVERITY colours as a fixed property of each
 * section, independent of that section's actual score — so a tile implied a status it did not
 * measure. Data Health's monogram was severity-amber while the section scored 95 and showed a Good
 * badge inches away. ADR-0028 §4 C5 forbids exactly this: severity tokens belong only to
 * severity-bearing components. Real severity for these cards is carried by their labelled severity
 * badge, never by the monogram.
 *
 * The map was also internally inconsistent before migration (MetadataHealth carried bare hex
 * literals while every sibling carried an SLDS var()), and the SLDS families it used were the
 * wrong ones by measurement: --slds-g-color-success-1 is a dark teal #056764 and
 * --slds-g-color-warning-1 a brown #8c4b02 in this org.
 *
 * These custom properties resolve because oiHealthOverviewGrid.css imports c/oiDesignTokens and
 * declares them on its own :host, and the icon element lives in this component's shadow root.
 */
const SECTION_ICON_META = {
  MetadataHealth: {
    abbreviation: "MD",
    washVar: "var(--oi-color-identity-1-wash)",
    colorVar: "var(--oi-color-identity-1)"
  },
  AutomationHealth: {
    abbreviation: "AU",
    washVar: "var(--oi-color-identity-2-wash)",
    colorVar: "var(--oi-color-identity-2)"
  },
  CodeHealth: {
    abbreviation: "CO",
    washVar: "var(--oi-color-identity-3-wash)",
    colorVar: "var(--oi-color-identity-3)"
  },
  SecurityHealth: {
    abbreviation: "SE",
    washVar: "var(--oi-color-identity-4-wash)",
    colorVar: "var(--oi-color-identity-4)"
  },
  DataHealth: {
    abbreviation: "DA",
    washVar: "var(--oi-color-identity-5-wash)",
    colorVar: "var(--oi-color-identity-5)"
  },
  Storage: {
    abbreviation: "ST",
    washVar: "var(--oi-color-identity-6-wash)",
    colorVar: "var(--oi-color-identity-6)"
  }
};
const DEFAULT_ICON_META = {
  abbreviation: "—",
  washVar: "var(--oi-color-identity-6-wash)",
  colorVar: "var(--oi-color-identity-6)"
};

export default class OiHealthOverviewGrid extends LightningElement {
  @api overview;
  @api sections = [];

  get kpiTiles() {
    const overview = this.overview || {};
    return [
      {
        key: "objects",
        label: "Objects",
        value: this.formatCount(overview.objectCount)
      },
      {
        key: "fields",
        label: "Fields",
        value: this.formatCount(overview.fieldCount)
      },
      {
        key: "apexClasses",
        label: "Apex classes",
        value: this.formatCount(overview.apexClassCount)
      },
      {
        key: "triggers",
        label: "Triggers",
        value: this.formatCount(overview.triggerCount)
      },
      {
        key: "flows",
        label: "Flows",
        value: this.formatCount(overview.flowCount)
      },
      {
        key: "permissionSets",
        label: "Permission sets",
        value: this.formatCount(overview.permissionSetCount)
      },
      {
        key: "dependencies",
        label: "Dependencies",
        value: this.formatCount(overview.dependencyCount)
      },
      {
        key: "relationships",
        label: "Relationships",
        value: this.formatCount(overview.relationshipCount)
      }
    ];
  }

  get categoryCards() {
    return (this.sections || [])
      .filter((section) => section.sectionKey !== ORG_OVERVIEW_SECTION_KEY)
      .map((section) => {
        const iconMeta =
          SECTION_ICON_META[section.sectionKey] || DEFAULT_ICON_META;
        return {
          ...section,
          iconAbbreviation: iconMeta.abbreviation,
          iconStyle: `background: ${iconMeta.washVar}; color: ${iconMeta.colorVar};`,
          cardClass: section.isImplemented
            ? "oi-health-category-card"
            : "oi-health-category-card oi-health-category-card_stub",
          showScoreRing: section.isImplemented && section.isScored,
          showFactsBadge: section.isImplemented && !section.isScored,
          hasTopSignals:
            section.isImplemented &&
            section.topSignals &&
            section.topSignals.length > 0
        };
      });
  }

  formatCount(value) {
    return value === null || value === undefined
      ? "—"
      : Number(value).toLocaleString();
  }

  handleCardClick(event) {
    const sectionKey = event.currentTarget.dataset.sectionKey;
    if (!sectionKey) {
      return;
    }
    const card = this.categoryCards.find((c) => c.sectionKey === sectionKey);
    if (!card || !card.isImplemented) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("selectsection", { detail: { sectionKey } })
    );
  }

  handleCardKeydown(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.handleCardClick(event);
    }
  }
}
