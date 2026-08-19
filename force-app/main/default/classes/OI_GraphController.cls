/**
 * Purpose: The @AuraEnabled boundary for graph reads (API.md §2.1) — backs oiGraphExplorer/
 *          oiGraphCanvas/oiNodeDetailPanel (Sprint 10).
 * Responsibilities: Permission check -> call OI_GraphEngine only (never
 *                    OI_GraphBuilder/OI_GraphTraversal/OI_GraphRepository/OI_GraphSerializer/
 *                    OI_GraphCache directly, ADR-0013) -> map to a DTO -> return, or
 *                    translate to a sanitized AuraHandledException (CodingStandards.md §6),
 *                    matching OI_ScanController's own established pattern exactly.
 *                    getFieldSummaries (Hierarchy Visualizer field-browser sprint) is the one
 *                    method here that knows a Salesforce-specific typeKey literal
 *                    (HAS_FIELD_EDGE_TYPE_KEY) — a deliberate, narrow exception matching the
 *                    same precedent oiGraphExplorer.js's Field analyze mode already
 *                    established client-side, not a drift from ADR-0013 (OI_GraphEngine
 *                    itself stays fully generic; only the Controller-level constant is
 *                    domain-specific).
 * Dependencies: OI_GraphEngine, OI_SecurityService, OI_GraphFragmentDTO, OI_NodeDetailDTO,
 *               OI_FieldSummaryDTO.
 * Limitations: getMiniMapSummary (API.md §2.1) is not implemented — mini-map is deferred
 *              alongside oiMiniMap (Backlog UI-6, Phase 3), consistent with Sprint 10's
 *              MVP scope. getGraphFragment does not yet accept nodeTypeFilter[]/
 *              edgeTypeFilter[] despite API.md/GraphEngine.md documenting them — that
 *              remains real, deferred backend work (Backlog UI-4, Phase 3); the relationship
 *              filter this sprint ships is a client-side-only rendering filter over the
 *              already-fetched fragment (oiGraphExplorer.js/graphRelationshipFilter.js),
 *              never a server-side traversal change.
 */
public with sharing class OI_GraphController {
    /**
     * The one Salesforce-metadata-domain constant this otherwise-generic Controller knows
     * about — matching the exact precedent oiGraphExplorer.js's own HAS_FIELD_EDGE_TYPE_KEY
     * constant already sets for this same "list an object's own fields" concern (Sprint,
     * Field analyze mode's object field picker). OI_GraphEngine.getMembersByEdgeType stays
     * fully generic; this Controller is the boundary where "field membership means
     * SalesforceMetadata.HAS_FIELD" is allowed to be known, exactly as it already is on the
     * client side.
     */
    private static final String HAS_FIELD_EDGE_TYPE_KEY = 'SalesforceMetadata.HAS_FIELD';

    @AuraEnabled(cacheable=true)
    public static OI_GraphFragmentDTO getGraphFragment(String nodeKey, Integer hopDepth, String pageCursor, Map<String, String> knownChecksums) {
        try {
            OI_SecurityService.assertPermission('OI_View_Graph');
            OI_GraphFragment fragment = new OI_GraphEngine().getGraphFragment(nodeKey, hopDepth, pageCursor, knownChecksums);
            return new OI_GraphFragmentDTO(fragment);
        } catch (Exception e) {
            throw translate(e);
        }
    }

    @AuraEnabled(cacheable=true)
    public static OI_NodeDetailDTO getNodeDetail(String nodeKey) {
        try {
            OI_SecurityService.assertPermission('OI_View_Graph');
            OI_GraphEngine graphEngine = new OI_GraphEngine();
            OI_VersionRecord version = graphEngine.getNodeDetail(nodeKey);
            if (version == null) {
                throw new OI_ValidationException('No node found for key ' + nodeKey + '.');
            }
            OI_RelationshipCounts relationshipCounts = graphEngine.getRelationshipCounts(nodeKey);
            return new OI_NodeDetailDTO(version, relationshipCounts);
        } catch (Exception e) {
            throw translate(e);
        }
    }

    /**
     * Bulk field metadata for one object's own fields (never another object's fields that
     * merely reference it) — backs oiNodeDetailPanel's field browser (Show All/Custom/
     * Standard, field type). One query for the membership edges, one bulk query for the
     * field nodes themselves (OI_GraphEngine.getMembersByEdgeType) — never N getNodeDetail
     * round trips for an object with dozens of fields.
     */
    @AuraEnabled(cacheable=true)
    public static List<OI_FieldSummaryDTO> getFieldSummaries(String objectNodeKey) {
        try {
            OI_SecurityService.assertPermission('OI_View_Graph');
            List<OI_VersionRecord> fieldVersions = new OI_GraphEngine().getMembersByEdgeType(objectNodeKey, HAS_FIELD_EDGE_TYPE_KEY);
            List<OI_FieldSummaryDTO> summaries = new List<OI_FieldSummaryDTO>();
            for (OI_VersionRecord fieldVersion : fieldVersions) {
                summaries.add(new OI_FieldSummaryDTO(fieldVersion));
            }
            return summaries;
        } catch (Exception e) {
            throw translate(e);
        }
    }

    /** Sanitized Controller-boundary translation (CodingStandards.md §6) — mirrors OI_ScanController.translate exactly, including keeping the permission check inside the same try block it protects. */
    private static AuraHandledException translate(Exception e) {
        String message;
        if (e instanceof OI_SecurityException) {
            message = 'You don\'t have permission to view org graph data.';
        } else if (e instanceof OI_ValidationException || e instanceof OI_ServiceException) {
            message = e.getMessage();
        } else {
            message = 'Something went wrong retrieving the graph. Please try again.';
        }
        AuraHandledException handled = new AuraHandledException(message);
        handled.setMessage(message);
        return handled;
    }
}
