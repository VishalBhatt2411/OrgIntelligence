/**
 * Purpose: Hierarchy Search (FR-011) — find where a record sits within one already-configured
 *          Hierarchy Definition, by Record Name or Record Id, optionally narrowed to a single
 *          Hierarchy Level and/or active-only. A distinct concern from OI_RecordSearchService
 *          (Record Analysis, ADR-0021): that class finds ANY record of ONE object, anywhere in
 *          the org, for attaching to a hierarchy; this class finds records that ALREADY
 *          participate in ONE specific hierarchy, across every object type that hierarchy spans.
 * Responsibilities: Resolve which object types a definition actually uses (via its Hierarchy
 *                    Levels), run a dynamic, per-object-type Name-field LIKE query across those
 *                    types only (the same justified "arbitrary customer object" dynamic-SOQL
 *                    exception OI_RecordSearchService already establishes for Record Analysis —
 *                    a fully generic, admin-configured "any object" search does not fit the
 *                    Selector model, which assumes one fixed schema per class), then delegate the
 *                    actual OI_Hierarchy_Relationship__c match to OI_HierarchyRelationshipSelector
 *                    (CodingStandards.md §4 — that object's SOQL lives only there). A query term
 *                    that parses as a valid Id skips the Name search entirely and matches
 *                    Parent/Child_Record_Id__c directly — precise, and works even for object
 *                    types with no accessible Name field.
 * Dependencies: OI_HierarchyDefinitionSelector, OI_HierarchyRelationshipSelector,
 *               OI_RecordSchemaUtil.
 * Limitations: FR-011 also names "Account Number", "Location", and "Owner" as search facets.
 *              Those are genuine object-specific fields (e.g. Account.AccountNumber) that do not
 *              generalize across arbitrary hierarchy-participant objects (CLAUDE.md's Metadata
 *              Assumptions; ADR-0022's polymorphic any-object design) — the FRD's data model
 *              defines no per-hierarchy-type field mapping to build this against, so it is not
 *              guessed here (CLAUDE.md: never invent missing business requirements). Only Record
 *              Name, Record Id, Hierarchy Level, and Status (active/inactive) are implemented;
 *              the rest is a documented gap, not a silent omission.
 */
public with sharing class OI_HierarchySearchService {
    private static final Integer MIN_QUERY_LENGTH = 2;
    private static final Integer MAX_RESULTS = 20;

    private final OI_HierarchyDefinitionSelector definitionSelector;
    private final OI_HierarchyRelationshipSelector relationshipSelector;

    public OI_HierarchySearchService() {
        this(new OI_HierarchyDefinitionSelector(), new OI_HierarchyRelationshipSelector());
    }

    public OI_HierarchySearchService(OI_HierarchyDefinitionSelector definitionSelector, OI_HierarchyRelationshipSelector relationshipSelector) {
        this.definitionSelector = definitionSelector;
        this.relationshipSelector = relationshipSelector;
    }

    /** FR-011: relationships within definitionId where the matched record (by Name or Id) appears as Parent or Child, optionally narrowed by hierarchyLevelId and/or includeInactive. Below MIN_QUERY_LENGTH or no match returns empty, never an error. */
    public List<OI_Hierarchy_Relationship__c> search(Id definitionId, String queryTerm, Id hierarchyLevelId, Boolean includeInactive) {
        if (definitionId == null || String.isBlank(queryTerm) || queryTerm.trim().length() < MIN_QUERY_LENGTH) {
            return new List<OI_Hierarchy_Relationship__c>();
        }
        String trimmedTerm = queryTerm.trim();

        Set<String> matchingRecordIds = new Set<String>();
        Id parsedId = parseId(trimmedTerm);
        if (parsedId != null) {
            matchingRecordIds.add((String) parsedId);
        } else {
            matchingRecordIds.addAll(matchByName(definitionId, trimmedTerm));
            if (matchingRecordIds.isEmpty()) {
                return new List<OI_Hierarchy_Relationship__c>();
            }
        }

        List<OI_Hierarchy_Relationship__c> matches = relationshipSelector.selectByDefinitionAndRecordIds(definitionId, matchingRecordIds, hierarchyLevelId, includeInactive);
        return matches.size() > MAX_RESULTS ? trimTo(matches, MAX_RESULTS) : matches;
    }

    /** One dynamic Name-field LIKE query per distinct object type this definition's Levels actually use — never one query per relationship row. An object type that is unknown, inaccessible, or has no accessible Name field is silently skipped (the same skip-never-fail discipline OI_HierarchyRecordResolver already establishes), not an error. */
    private Set<String> matchByName(Id definitionId, String queryTerm) {
        Set<String> objectApiNames = new Set<String>();
        for (OI_Hierarchy_Level__c level : definitionSelector.selectLevelsByDefinitionId(definitionId)) {
            if (String.isNotBlank(level.Object_Api_Name__c)) {
                objectApiNames.add(level.Object_Api_Name__c);
            }
        }

        Set<String> recordIds = new Set<String>();
        String likeTerm = '%' + String.escapeSingleQuotes(queryTerm) + '%';
        for (String objectApiName : objectApiNames) {
            Schema.DescribeSObjectResult describe;
            try {
                describe = OI_RecordSchemaUtil.describeAccessibleObject(objectApiName);
            } catch (Exception inaccessibleOrUnknown) {
                continue;
            }
            String nameField = OI_RecordSchemaUtil.resolveNameField(describe);
            if (nameField == null) {
                continue;
            }
            Integer maxResults = MAX_RESULTS;
            String soql = 'SELECT Id FROM ' + describe.getName() + ' WHERE ' + nameField + ' LIKE :likeTerm LIMIT :maxResults';
            for (SObject record : Database.query(soql, AccessLevel.USER_MODE)) {
                recordIds.add((String) record.get('Id'));
            }
        }
        return recordIds;
    }

    private Id parseId(String value) {
        try {
            return (Id) value;
        } catch (Exception malformed) {
            return null;
        }
    }

    private List<OI_Hierarchy_Relationship__c> trimTo(List<OI_Hierarchy_Relationship__c> source, Integer size) {
        List<OI_Hierarchy_Relationship__c> trimmed = new List<OI_Hierarchy_Relationship__c>();
        for (Integer i = 0; i < size; i++) {
            trimmed.add(source[i]);
        }
        return trimmed;
    }
}
