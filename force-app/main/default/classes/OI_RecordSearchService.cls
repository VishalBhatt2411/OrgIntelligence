/**
 * Purpose: Live, object-scoped record search (Record Analysis, ADR-0021) — a completely
 *          separate concern from OI_SearchService's metadata search (SearchEngine.md §0):
 *          records are never scanned, never persisted as OI_Graph_Node__c rows, and this
 *          class never touches the Graph Engine.
 * Responsibilities: Given an object API name and a query term, resolve that object's Name
 *                    field dynamically (CLAUDE.md §Metadata Assumptions — never hardcode a
 *                    field like "Name" for every object, since some standard objects use a
 *                    different one), then run a single CRUD/FLS/sharing-safe dynamic query.
 * Dependencies: None (Schema global describe only).
 * Limitations: Only objects with a designated Name field are searchable; an object without
 *              one (rare) returns no results rather than guessing a display field.
 */
public with sharing class OI_RecordSearchService {
    private static final Integer MAX_RESULTS = 20;
    private static final Integer MIN_QUERY_LENGTH = 2;

    public List<OI_RecordSummaryDTO> search(String objectApiName, String queryTerm) {
        Schema.DescribeSObjectResult describe = OI_RecordSchemaUtil.describeAccessibleObject(objectApiName);
        if (String.isBlank(queryTerm) || queryTerm.trim().length() < MIN_QUERY_LENGTH) {
            return new List<OI_RecordSummaryDTO>();
        }
        String nameField = OI_RecordSchemaUtil.resolveNameField(describe);
        if (nameField == null) {
            return new List<OI_RecordSummaryDTO>();
        }

        String likeTerm = '%' + String.escapeSingleQuotes(queryTerm.trim()) + '%';
        Integer maxResults = MAX_RESULTS;
        String soql =
            'SELECT Id, ' +
            nameField +
            ' FROM ' +
            describe.getName() +
            ' WHERE ' +
            nameField +
            ' LIKE :likeTerm ORDER BY ' +
            nameField +
            ' ASC LIMIT :maxResults';

        List<OI_RecordSummaryDTO> results = new List<OI_RecordSummaryDTO>();
        for (SObject record : Database.query(soql, AccessLevel.USER_MODE)) {
            results.add(new OI_RecordSummaryDTO((String) record.get('Id'), OI_RecordSchemaUtil.labelFor(record, nameField), describe.getName()));
        }
        return results;
    }
}
