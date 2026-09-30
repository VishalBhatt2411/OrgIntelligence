/**
 * Purpose: The @AuraEnabled boundary for graph reads (API.md §2.1) — backs oiGraphExplorer/
 *          oiGraphCanvas/oiNodeDetailPanel (Sprint 10).
 * Responsibilities: Permission check -> call OI_GraphEngine only (never
 *                    OI_GraphBuilder/OI_GraphTraversal/OI_GraphRepository/OI_GraphSerializer/
 *                    OI_GraphCache directly, ADR-0013) -> map to a DTO -> return, or
 *                    translate to a sanitized AuraHandledException (CodingStandards.md §6),
 *                    matching OI_ScanController's own established pattern exactly.
 *                    getFieldSummaries delegates to OI_FieldSummaryService, which owns
 *                    the one Salesforce-specific concern here (HAS_FIELD membership joined
 *                    to live Describe, ADR-0031).
 * Dependencies: OI_GraphEngine, OI_SecurityService, OI_GraphFragmentDTO, OI_NodeDetailDTO,
 *               OI_FieldSummaryDTO, OI_FieldSummaryService, OI_RelationshipFieldDetailService,
 *               OI_RelationshipFieldDetailDTO, OI_TargetObjectRecordCountsDTO,
 *               OI_ObjectSharingSettingsService, OI_ObjectSharingSettingsDTO.
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
  @AuraEnabled(cacheable=true)
  public static OI_GraphFragmentDTO getGraphFragment(
    String nodeKey,
    Integer hopDepth,
    String pageCursor,
    Map<String, String> knownChecksums
  ) {
    try {
      OI_SecurityService.assertPermission('OI_View_Graph');
      OI_GraphFragment fragment = new OI_GraphEngine()
        .getGraphFragment(nodeKey, hopDepth, pageCursor, knownChecksums);
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
        throw new OI_ValidationException(
          'No node found for key ' + nodeKey + '.'
        );
      }
      OI_RelationshipCounts relationshipCounts = graphEngine.getRelationshipCounts(
        nodeKey
      );
      return new OI_NodeDetailDTO(version, relationshipCounts);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /**
   * The Intelligence panel's Automation / Code / Security sections for one node, plus scan
   * freshness (OI_NodeIntelligenceService owns all derivation; this is a thin gated boundary).
   *
   * Deliberately NOT cacheable, unlike getNodeDetail above: this payload's whole purpose is to
   * report the current state of scanned intelligence INCLUDING when it was last scanned, and a
   * platform-cached response would let the panel confidently display a stale "last scanned"
   * timestamp immediately after a fresh scan — precisely the trust failure this sprint exists
   * to remove.
   */
  @AuraEnabled
  public static OI_NodeIntelligenceDTO getNodeIntelligence(String nodeKey) {
    try {
      OI_SecurityService.assertPermission('OI_View_Graph');
      return new OI_NodeIntelligenceService().getIntelligence(nodeKey);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /**
   * One page of the actual rows behind a count shown in the Intelligence panel — what makes
   * "Outgoing — Has Field 22" clickable and answerable.
   *
   * Deliberately a SEPARATE call from getNodeDetail rather than more data on it: the panel
   * opens on every node selection, and loading every connected row each time would make
   * selection progressively slower on exactly the hub nodes users explore most. Drill-down
   * rows are fetched only once a user asks for them.
   *
   * Not cacheable, because paging and searching vary per request and a cached first page would
   * make "Load more" return the page the user already has.
   */
  @AuraEnabled
  public static OI_ConnectionPageDTO getNodeConnections(
    String nodeKey,
    String direction,
    String edgeTypeKey,
    Integer pageSize,
    String cursor,
    String searchTerm
  ) {
    try {
      OI_SecurityService.assertPermission('OI_View_Graph');
      return new OI_NodeConnectionsService()
        .getConnections(
          nodeKey,
          direction,
          edgeTypeKey,
          pageSize,
          cursor,
          searchTerm
        );
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /**
   * Where clicking a component should navigate. Resolved server-side because Salesforce Setup
   * pages are addressed by durable identifiers that are not derivable from an API name — see
   * OI_MetadataNavigationService for the verified traps (a lookup field's durable id drops its
   * "Id" suffix; custom objects are not addressable by API name at all).
   *
   * Cacheable: a component's Setup address is stable for the life of that component, so
   * repeated clicks on the same row should not re-query.
   */
  @AuraEnabled(cacheable=true)
  public static OI_NavigationTargetDTO getNavigationTarget(
    String typeKey,
    String apiName
  ) {
    try {
      OI_SecurityService.assertPermission('OI_View_Graph');
      return new OI_MetadataNavigationService().resolve(typeKey, apiName);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /**
   * Bulk field metadata for one object's own fields (never another object's fields that
   * merely reference it) — backs oiNodeDetailPanel's field browser (Show All/Custom/
   * Standard, field type). Since ADR-0031 the full list comes from live Describe, joined to
   * the persisted relationship-field nodes (OI_FieldSummaryService) — still one round trip.
   */
  @AuraEnabled(cacheable=true)
  public static List<OI_FieldSummaryDTO> getFieldSummaries(
    String objectNodeKey
  ) {
    try {
      OI_SecurityService.assertPermission('OI_View_Graph');
      return new OI_FieldSummaryService().getFieldSummaries(objectNodeKey);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /**
   * The Object panel's reworked Relationships section (outgoing side) — per-field Lookup/
   * Master-Detail detail (required-ness, cascade delete), replacing the old flat "Outgoing
   * Lookups — N" count (see OI_RelationshipFieldDetailService's own doc comment). Target-object
   * record counts are a separate, explicit call — see getRelationshipTargetObjectRecordCounts
   * below.
   */
  @AuraEnabled
  public static OI_RelationshipFieldDetailDTO getRelationshipFieldDetail(
    String objectNodeKey
  ) {
    try {
      OI_SecurityService.assertPermission('OI_View_Graph');
      return new OI_RelationshipFieldDetailService()
        .getRelationshipFieldDetail(objectNodeKey);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /**
   * On-demand companion to getRelationshipFieldDetail above: live per-target-object record
   * counts, split into their own round-trip after live-org profiling showed computing every
   * relationship field's target-object COUNT() synchronously on section expand made wide-fanout
   * objects (e.g. a polymorphic WhatId/WhoId field spanning dozens of targets) slow to open. The
   * LWC requests this only when a user explicitly triggers "Load record counts".
   *
   * Deliberately NOT cacheable, same rationale as the old inline behavior it replaces: a
   * platform-cached response would present a stale record count as current — the same trust
   * concern getNodeIntelligence's own doc comment raises for stale scan timestamps.
   */
  @AuraEnabled
  public static OI_TargetObjectRecordCountsDTO getRelationshipTargetObjectRecordCounts(
    List<String> objectApiNames
  ) {
    try {
      OI_SecurityService.assertPermission('OI_View_Graph');
      return new OI_RelationshipFieldDetailService()
        .getTargetObjectRecordCounts(objectApiNames);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /**
   * The Object panel's Sharing Settings section — internal/external sharing model (OWD), this
   * platform's first Tooling-API-sourced fact (Apex Describe has no accessor for it at all;
   * see OI_ObjectScanner's own documented gap and OI_ToolingApiAdapter's own doc comment on
   * why a same-org callout needs no Named Credential/Remote Site Setting and elevates nothing
   * beyond the running user's own Tooling API access).
   *
   * Takes the object's real API name directly rather than a graph nodeKey: unlike
   * getRelationshipFieldDetail above, this never reads the persisted graph at all (OI_GraphEngine
   * is not involved), so there is no node to key off of — OI_RecordSchemaUtil validates the
   * name the same way every other object-scoped service in this codebase already does.
   *
   * Deliberately NOT cacheable: OWD is admin-changeable at any time, same rationale as
   * getRelationshipFieldDetail above.
   */
  @AuraEnabled
  public static OI_ObjectSharingSettingsDTO getObjectSharingSettings(
    String objectApiName
  ) {
    try {
      OI_SecurityService.assertPermission('OI_View_Graph');
      return new OI_ObjectSharingSettingsService()
        .getObjectSharingSettings(objectApiName);
    } catch (Exception e) {
      throw translate(e);
    }
  }

  /** Sanitized Controller-boundary translation (CodingStandards.md §6) — mirrors OI_ScanController.translate exactly, including keeping the permission check inside the same try block it protects. */
  private static AuraHandledException translate(Exception e) {
    String message;
    if (e instanceof OI_SecurityException) {
      message = 'You don\'t have permission to view org graph data.';
    } else if (
      e instanceof OI_ValidationException || e instanceof OI_ServiceException
    ) {
      message = e.getMessage();
    } else {
      message = 'Something went wrong retrieving the graph. Please try again.';
    }
    AuraHandledException handled = new AuraHandledException(message);
    handled.setMessage(message);
    return handled;
  }
}
