/**
 * Purpose: One page of drill-down rows behind a count shown in the Intelligence panel — the
 *          payload that makes "Outgoing — Has Field 22" clickable and answerable.
 * Responsibilities: Carry display-ready rows plus the paging/total context the table needs.
 *                    Pure data.
 * Dependencies: None.
 *
 * Design rule this shape enforces: internal graph keys never become user-facing content. Each
 * row carries a `nodeKey` purely so the UI can navigate or re-select — every VISIBLE value
 * (label, api name, relationship, direction, via) is already resolved to human language here, so
 * no LWC has to interpret a typeKey or an edge type. That is what keeps "Lookup To" out of the
 * UI as `SalesforceMetadata.LOOKUP_TO`.
 */
public class OI_ConnectionPageDTO {
    /** One connected component, described the way an admin would describe it. */
    public class Row {
        /** Internal only — used for navigation and re-selection, never rendered. */
        @AuraEnabled
        public String nodeKey;
        @AuraEnabled
        public String label;
        /** The API name (a field's "OwnerId", an object's "Account") — genuinely useful to an admin, unlike an internal key. */
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String typeLabel;
        /** Human relationship name, e.g. "Lookup" — resolved from the Presentation Registry. */
        @AuraEnabled
        public String relationshipLabel;
        /** This row's role relative to the anchor node, e.g. "Referenced By" / "Field Of". */
        @AuraEnabled
        public String roleLabel;
        /** 'incoming' | 'outgoing' — kept for styling/sorting; roleLabel is what users read. */
        @AuraEnabled
        public String direction;
        /** For a relationship edge, the field the relationship travels through (e.g. "AccountId"). Null when not applicable — never an empty placeholder. */
        @AuraEnabled
        public String viaFieldApiName;
        /** Field-specific context, populated only for field rows. Null elsewhere rather than blank, so the table can hide empty columns honestly. */
        @AuraEnabled
        public String dataType;
        @AuraEnabled
        public String referencedObject;
        @AuraEnabled
        public Boolean isCustom;

        public Row(String nodeKey, String label, String apiName, String typeLabel) {
            this.nodeKey = nodeKey;
            this.label = label;
            this.apiName = apiName;
            this.typeLabel = typeLabel;
        }
    }

    @AuraEnabled
    public List<Row> rows;
    /**
     * The exact total for this (node, direction, edgeType) selection under the SAME scope the
     * panel's summary count uses — so the drill-down header can state "22 results" and be
     * provably the same 22 (OI_EdgeSelector.EDGE_SCOPE_PREDICATE guarantees it). When a search
     * term is active this is the FILTERED total, which the UI labels as such.
     */
    @AuraEnabled
    public Integer totalCount;
    @AuraEnabled
    public Boolean hasMore;
    /** Opaque keyset cursor for the next page. Null when there is no next page. */
    @AuraEnabled
    public String nextCursor;
    /** True when the caller supplied a search term, so the UI can say "filtered" rather than implying totalCount is the whole set. */
    @AuraEnabled
    public Boolean isFiltered;
    /** Present only when this category genuinely cannot be answered with current scanner coverage — rendered instead of an empty table, so "nothing here" is never mistaken for "nothing exists". */
    @AuraEnabled
    public String unavailableReason;

    public OI_ConnectionPageDTO(List<Row> rows, Integer totalCount, Boolean hasMore, String nextCursor, Boolean isFiltered) {
        this.rows = rows == null ? new List<Row>() : rows;
        this.totalCount = totalCount == null ? 0 : totalCount;
        this.hasMore = hasMore == null ? false : hasMore;
        this.nextCursor = nextCursor;
        this.isFiltered = isFiltered == null ? false : isFiltered;
    }

    /** An honest "we cannot answer this" page — never an empty table pretending the answer is zero. */
    public static OI_ConnectionPageDTO unavailable(String reason) {
        OI_ConnectionPageDTO page = new OI_ConnectionPageDTO(new List<Row>(), 0, false, null, false);
        page.unavailableReason = reason;
        return page;
    }
}
