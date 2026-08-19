/**
 * Purpose: Orchestrates hierarchy relationship assignment (FR-003/004/005/017/018) —
 *          validate, then commit the relationship change and its audit trail as one atomic
 *          unit via OI_HierarchyRelationshipWriter.
 * Responsibilities: assignParent — create a new relationship, or (when the child already
 *                    has an active parent and the definition does not allow multiple
 *                    parents) treat the call as a move: the old relationship is deactivated
 *                    and the new one created/reactivated in the same commit, with a single
 *                    "Moved" history row capturing both. deactivateRelationship — explicit
 *                    removal, always audited, never a hard delete (Business Rule 7's spirit
 *                    applied to relationships, not just definitions).
 * Dependencies: OI_HierarchyDefinitionSelector, OI_HierarchyRelationshipSelector,
 *               OI_HierarchyValidationService, OI_HierarchyRelationshipWriter (all
 *               constructor-injected for testability, ADR-0003).
 * Limitations: Reactivating a previously-deactivated identical (definition, parent, child)
 *              pair is a natural consequence of Relationship_Key__c's stable identity (an
 *              upsert on that key updates the existing inactive row rather than erroring) —
 *              this is intentional, not a gap: the FRD's business rules govern the CURRENT
 *              active state, and a relationship's identity is stable across activate/
 *              deactivate/reactivate cycles.
 */
public with sharing class OI_HierarchyRelationshipService {
    private static final String ROOT_PARENT_TOKEN = 'root';

    private final OI_HierarchyDefinitionSelector definitionSelector;
    private final OI_HierarchyRelationshipSelector relationshipSelector;
    private final OI_HierarchyValidationService validationService;
    private final OI_HierarchyRelationshipWriter repository;

    public OI_HierarchyRelationshipService() {
        this(new OI_HierarchyDefinitionSelector(), new OI_HierarchyRelationshipSelector(), new OI_HierarchyValidationService(), new OI_HierarchyRelationshipWriter());
    }

    public OI_HierarchyRelationshipService(
        OI_HierarchyDefinitionSelector definitionSelector,
        OI_HierarchyRelationshipSelector relationshipSelector,
        OI_HierarchyValidationService validationService,
        OI_HierarchyRelationshipWriter repository
    ) {
        this.definitionSelector = definitionSelector;
        this.relationshipSelector = relationshipSelector;
        this.validationService = validationService;
        this.repository = repository;
    }

    public OI_Hierarchy_Relationship__c assignParent(
        Id definitionId,
        String parentObjectApiName,
        String parentRecordId,
        String childObjectApiName,
        String childRecordId,
        Id hierarchyLevelId,
        String relationshipType,
        Date effectiveStartDate,
        Date effectiveEndDate
    ) {
        OI_Hierarchy_Definition__c definition = definitionSelector.selectById(definitionId);
        if (definition == null) {
            throw new OI_ValidationException('Unknown hierarchy definition.');
        }
        validationService.assertLevelBelongsToDefinition(hierarchyLevelId, definitionSelector.selectLevelsByDefinitionId(definitionId));
        validationService.validateEffectiveDates(effectiveStartDate, effectiveEndDate);

        List<OI_Hierarchy_Relationship__c> existingForDefinition = relationshipSelector.selectAllByDefinitionId(definitionId);
        validationService.validateAssignment(definition, existingForDefinition, parentRecordId, childRecordId);

        List<OI_Hierarchy_Relationship__c> existingActiveParents = new List<OI_Hierarchy_Relationship__c>();
        for (OI_Hierarchy_Relationship__c candidate : existingForDefinition) {
            if (candidate.Is_Active__c == true && candidate.Child_Record_Id__c == childRecordId) {
                existingActiveParents.add(candidate);
            }
        }
        List<OI_Hierarchy_Relationship__c> relationshipsToCommit = new List<OI_Hierarchy_Relationship__c>();
        String previousParentRecordId = null;
        /** A move only when the hierarchy is single-parent AND a parent already exists — when Allow_Multiple_Parents__c is true, an existing active parent must be left untouched while the new one is added alongside it, never deactivated. */
        Boolean isMove = !existingActiveParents.isEmpty() && definition.Allow_Multiple_Parents__c != true;
        if (isMove) {
            OI_Hierarchy_Relationship__c previous = existingActiveParents[0];
            previousParentRecordId = previous.Parent_Record_Id__c;
            previous.Is_Active__c = false;
            relationshipsToCommit.add(previous);
        }

        OI_Hierarchy_Relationship__c newRelationship = new OI_Hierarchy_Relationship__c(
            Hierarchy_Definition__c = definitionId,
            Hierarchy_Level__c = hierarchyLevelId,
            Parent_Object_Api_Name__c = parentObjectApiName,
            Parent_Record_Id__c = parentRecordId,
            Child_Object_Api_Name__c = childObjectApiName,
            Child_Record_Id__c = childRecordId,
            Effective_Start_Date__c = effectiveStartDate,
            Effective_End_Date__c = effectiveEndDate,
            Is_Active__c = true,
            Relationship_Type__c = relationshipType,
            Relationship_Key__c = buildRelationshipKey(definitionId, parentRecordId, childRecordId)
        );
        relationshipsToCommit.add(newRelationship);

        OI_Hierarchy_Relationship_History__c historyEntry = new OI_Hierarchy_Relationship_History__c(
            Hierarchy_Definition__c = definitionId,
            Child_Object_Api_Name__c = childObjectApiName,
            Child_Record_Id__c = childRecordId,
            Previous_Parent_Record_Id__c = previousParentRecordId,
            New_Parent_Record_Id__c = parentRecordId,
            Changed_By__c = UserInfo.getUserId(),
            Changed_Date__c = Datetime.now(),
            Change_Type__c = isMove ? 'Moved' : 'Created'
        );

        repository.commitChange(historyEntry, relationshipsToCommit);
        return newRelationship;
    }

    /** Explicit removal — always audited, never a hard delete, so relationship history (FR-017) survives (mirrors Business Rule 7's "deactivating must not delete history" spirit, applied here to a relationship rather than a whole definition). */
    public void deactivateRelationship(Id relationshipId) {
        OI_Hierarchy_Relationship__c relationship = [
            SELECT Id, Hierarchy_Definition__c, Parent_Record_Id__c, Child_Object_Api_Name__c, Child_Record_Id__c, Is_Active__c, Relationship_Key__c
            FROM OI_Hierarchy_Relationship__c
            WHERE Id = :relationshipId
            LIMIT 1
        ];
        if (relationship.Is_Active__c != true) {
            return;
        }
        relationship.Is_Active__c = false;

        OI_Hierarchy_Relationship_History__c historyEntry = new OI_Hierarchy_Relationship_History__c(
            Hierarchy_Definition__c = relationship.Hierarchy_Definition__c,
            Child_Object_Api_Name__c = relationship.Child_Object_Api_Name__c,
            Child_Record_Id__c = relationship.Child_Record_Id__c,
            Previous_Parent_Record_Id__c = relationship.Parent_Record_Id__c,
            New_Parent_Record_Id__c = null,
            Changed_By__c = UserInfo.getUserId(),
            Changed_Date__c = Datetime.now(),
            Change_Type__c = 'Deactivated'
        );
        repository.commitChange(historyEntry, new List<OI_Hierarchy_Relationship__c>{ relationship });
    }

    /** Stable, deterministic identity for a (definition, parent, child) pair (ADR-0022) — a blank parent (root-level relationship) resolves to a literal token, not null, since Relationship_Key__c is a required Text field. */
    private String buildRelationshipKey(Id definitionId, String parentRecordId, String childRecordId) {
        String parentSegment = String.isBlank(parentRecordId) ? ROOT_PARENT_TOKEN : parentRecordId;
        return definitionId + '::' + parentSegment + '::' + childRecordId;
    }
}
