/**
 * Purpose: FRD business-rule validation for hierarchy relationship assignment (FR-015/016,
 *          Business Rules 1-10) — called only by OI_HierarchyRelationshipService, never
 *          directly by a Controller.
 * Responsibilities: Self-parent rejection, duplicate-relationship rejection, active-
 *                    definition enforcement, level-belongs-to-definition enforcement
 *                    (Business Rule 9), effective-date sanity, and bulk-safe
 *                    circular-relationship detection. The multiple-parents policy itself
 *                    (add an additional active parent vs. move/replace the existing one) is
 *                    OI_HierarchyRelationshipService's own branching logic, not a rule this
 *                    service rejects against — every case is handled gracefully, never
 *                    refused (FR-004).
 * Dependencies: None (operates entirely over an already-loaded relationship list the caller
 *               supplies — see Limitations).
 * Limitations: Circular detection and duplicate-checking both take an already-queried
 *              List<OI_Hierarchy_Relationship__c> rather than querying themselves — the
 *              caller (OI_HierarchyRelationshipService) loads a definition's current
 *              relationship set exactly once per assignment and reuses it for every check
 *              this service performs, avoiding the query-per-check pattern CLAUDE.md's
 *              bulkification rule forbids.
 */
public with sharing class OI_HierarchyValidationService {
    private static final Integer DEFAULT_MAX_LEVELS = 10;

    /**
     * Runs every structural check this service owns, in order, throwing OI_ValidationException
     * with an FRD-worded, actionable message on the first violation (§13's error catalog:
     * Invalid Parent / Circular Relationship / Duplicate Relationship / Inactive Hierarchy).
     * A root-level assignment (blank parentRecordId) skips the parent-specific checks — there
     * is no parent to validate against.
     */
    public void validateAssignment(
        OI_Hierarchy_Definition__c definition,
        List<OI_Hierarchy_Relationship__c> existingRelationships,
        String parentRecordId,
        String childRecordId
    ) {
        if (definition == null) {
            throw new OI_ValidationException('A hierarchy definition is required.');
        }
        if (definition.Status__c != 'Active') {
            throw new OI_ValidationException('Inactive Hierarchy — the selected hierarchy is currently inactive.');
        }
        if (String.isBlank(childRecordId)) {
            throw new OI_ValidationException('A child record is required.');
        }
        if (String.isNotBlank(parentRecordId) && parentRecordId == childRecordId) {
            throw new OI_ValidationException('Invalid Parent — a record cannot be its own parent.');
        }
        assertNotDuplicate(existingRelationships, parentRecordId, childRecordId);
        if (String.isNotBlank(parentRecordId)) {
            assertNoCircularRelationship(existingRelationships, parentRecordId, childRecordId, safeMaxLevels(definition));
        }
    }

    /**
     * No duplicate parent-child pair within the same hierarchy (Business Rule 10) — the
     * friendly pre-flight check that turns what would otherwise be a raw DUPLICATE_VALUE
     * DmlException (from Relationship_Key__c's own database-level Unique/External ID
     * constraint, the actual enforcement backstop) into the FRD's named error message before
     * any DML is attempted.
     */
    public void assertNotDuplicate(List<OI_Hierarchy_Relationship__c> existingRelationships, String parentRecordId, String childRecordId) {
        for (OI_Hierarchy_Relationship__c relationship : existingRelationships) {
            Boolean sameParent =
                (String.isBlank(parentRecordId) && String.isBlank(relationship.Parent_Record_Id__c)) || parentRecordId == relationship.Parent_Record_Id__c;
            if (relationship.Is_Active__c == true && sameParent && relationship.Child_Record_Id__c == childRecordId) {
                throw new OI_ValidationException('Duplicate Relationship — this hierarchy relationship already exists.');
            }
        }
    }

    /**
     * Circular Relationship Detection (FR-016): a bulk-safe, in-memory child->parent walk
     * over the definition's already-loaded relationship set — never a query inside this loop,
     * and therefore never per-row recursive SOQL (SOQL cannot do recursive traversal anyway).
     * Walks upward from the PROPOSED parent, checking whether the proposed child appears in
     * its own ancestor chain. Hard-bounded by maxLevels, mirroring Max_Hop_Depth__c's role in
     * the Graph Engine — a data integrity problem elsewhere must never turn into an unbounded
     * walk here.
     */
    public void assertNoCircularRelationship(List<OI_Hierarchy_Relationship__c> existingRelationships, String proposedParentRecordId, String proposedChildRecordId, Integer maxLevels) {
        Map<String, String> parentByChild = new Map<String, String>();
        for (OI_Hierarchy_Relationship__c relationship : existingRelationships) {
            if (relationship.Is_Active__c == true && String.isNotBlank(relationship.Parent_Record_Id__c)) {
                parentByChild.put(relationship.Child_Record_Id__c, relationship.Parent_Record_Id__c);
            }
        }

        String currentKey = proposedParentRecordId;
        Integer hops = 0;
        Integer effectiveMaxLevels = maxLevels == null ? DEFAULT_MAX_LEVELS : maxLevels;
        while (String.isNotBlank(currentKey) && hops < effectiveMaxLevels) {
            if (currentKey == proposedChildRecordId) {
                throw new OI_ValidationException('Circular Relationship — circular hierarchy relationship detected.');
            }
            currentKey = parentByChild.get(currentKey);
            hops++;
        }
    }

    /** Business Rule 9: a Hierarchy Level must belong to the Hierarchy Definition it's being assigned under — without this, a stale client-side level selection (e.g. left over after switching to a different Definition in the same UI session) could silently record a relationship under another hierarchy type's level. definitionLevels is the caller's already-queried set for this definition (OI_HierarchyDefinitionSelector.selectLevelsByDefinitionId) — never re-queried here, matching this service's existing "caller supplies the loaded set" convention. */
    public void assertLevelBelongsToDefinition(Id hierarchyLevelId, List<OI_Hierarchy_Level__c> definitionLevels) {
        if (hierarchyLevelId == null) {
            return;
        }
        for (OI_Hierarchy_Level__c level : definitionLevels) {
            if (level.Id == hierarchyLevelId) {
                return;
            }
        }
        throw new OI_ValidationException('Invalid Parent — the selected hierarchy level is not valid for this hierarchy.');
    }

    /** Business Rule 8, a minimal honest v1 check: an end date must not precede its own start date. Overlap-with-other-relationships validation is intentionally not implemented — the FRD names this as an optional, admin-configurable exception ("unless explicitly allowed") with no concrete rule to build against yet (CLAUDE.md: never invent missing business requirements). */
    public void validateEffectiveDates(Date effectiveStartDate, Date effectiveEndDate) {
        if (effectiveStartDate != null && effectiveEndDate != null && effectiveEndDate < effectiveStartDate) {
            throw new OI_ValidationException('Effective End Date cannot be before Effective Start Date.');
        }
    }

    private Integer safeMaxLevels(OI_Hierarchy_Definition__c definition) {
        return definition.Max_Levels__c == null ? DEFAULT_MAX_LEVELS : Integer.valueOf(definition.Max_Levels__c);
    }
}
