/**
 * Purpose: The @AuraEnabled wire shape behind the Intelligence panel's Automation / Code /
 *          Security sections — the named, categorised neighbours of one node, plus the honest
 *          provenance a user needs to trust them (when the data was scanned, and what the
 *          scanners do and do not cover).
 * Responsibilities: Carry categorised related components, per-category coverage notes, and
 *                    scan freshness. Pure data; all derivation lives in
 *                    OI_NodeIntelligenceService.
 * Dependencies: None.
 *
 * Why categories rather than raw edge types: an admin does not think in `EXECUTES_ON` or
 * `GRANTS_ACCESS_TO`. They think "what automation touches this object", "what code touches it",
 * "who can see it" — and crucially those three questions have different CONSEQUENCES, which is
 * why they are separate sections rather than one undifferentiated dependency list. Which
 * category a node type belongs to is resolved from the Domain Type Registry
 * (`OI_Node_Type_Descriptor__mdt.Intelligence_Category__c`), never hardcoded here or in the
 * LWC, so adding a metadata type places it correctly with no code change (ADR-0011).
 *
 * Why freshness is part of THIS payload rather than a separate call: every number in these
 * sections comes from the persisted scan graph, not a live org read. Presenting them without
 * saying when they were scanned is the same trust failure that let a live org show 122 Apex
 * classes and zero dependencies with no warning (see OI_ScanCoverage). Freshness travels with
 * the data it qualifies so a caller cannot render one without the other.
 */
public class OI_NodeIntelligenceDTO {
    /** One named neighbour, already resolved to display-ready values. */
    public class RelatedComponent {
        @AuraEnabled
        public String nodeKey;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String typeKey;
        @AuraEnabled
        public String typeLabel;
        /** 'incoming' (it points at this node) or 'outgoing' (this node points at it) — direction is meaningful to the user: a trigger firing ON this object is incoming, a class this class CALLS is outgoing. */
        @AuraEnabled
        public String direction;

        public RelatedComponent(String nodeKey, String label, String typeKey, String typeLabel, String direction) {
            this.nodeKey = nodeKey;
            this.label = label;
            this.typeKey = typeKey;
            this.typeLabel = typeLabel;
            this.direction = direction;
        }
    }

    /** One panel section: Automation, Code, or Security. */
    public class Category {
        @AuraEnabled
        public String category;
        @AuraEnabled
        public List<RelatedComponent> items;
        /** True when more neighbours exist than were returned — surfaced rather than silently truncated (GraphUI.md's no-silent-caps rule). */
        @AuraEnabled
        public Boolean truncated;
        /** What the scanners behind this category do NOT cover, in plain language. Rendered even when items is empty, so an empty section reads as "nothing found, and here is what we can see" rather than an unexplained blank. */
        @AuraEnabled
        public String coverageNote;

        public Category(String category, List<RelatedComponent> items, Boolean truncated, String coverageNote) {
            this.category = category;
            this.items = items;
            this.truncated = truncated;
            this.coverageNote = coverageNote;
        }
    }

    @AuraEnabled
    public String nodeKey;
    @AuraEnabled
    public List<Category> categories;
    /** When the graph backing this payload was last scanned. Null when no scan has ever completed — which the UI must render as "never scanned", never as fresh data. */
    @AuraEnabled
    public Datetime lastScannedAt;
    /** True when at least one scanner reported Partial or Degraded coverage on the most recent scan — the signal that this intelligence is knowingly incomplete. */
    @AuraEnabled
    public Boolean hasCoverageLimitations;

    public OI_NodeIntelligenceDTO(String nodeKey, List<Category> categories, Datetime lastScannedAt, Boolean hasCoverageLimitations) {
        this.nodeKey = nodeKey;
        this.categories = categories == null ? new List<Category>() : categories;
        this.lastScannedAt = lastScannedAt;
        this.hasCoverageLimitations = hasCoverageLimitations == null ? false : hasCoverageLimitations;
    }
}
