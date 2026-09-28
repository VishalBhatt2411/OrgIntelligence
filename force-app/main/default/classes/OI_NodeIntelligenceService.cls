/**
 * Purpose: Turns one node's raw graph neighbourhood into the Automation / Code / Security
 *          intelligence an administrator actually asked for, with the provenance needed to
 *          trust it.
 * Responsibilities: Read a bounded 1-hop neighbourhood through OI_GraphEngine (both
 *                    directions), group neighbours into user-facing categories using the Domain
 *                    Type Registry, attach each category's honest coverage note, and stamp the
 *                    payload with scan freshness.
 * Dependencies: OI_GraphEngine (read-only), OI_Node_Type_Descriptor__mdt, OI_Scan_Run__c,
 *               OI_Scan_Task__c.
 *
 * Layering — why this class exists at all rather than the logic living in the Graph Engine or
 * the LWC: grouping metadata types into "Automation" vs "Code" vs "Security" is Salesforce
 * domain knowledge, and the Graph Engine is deliberately generic (ADR-0013 — it must never
 * learn what a Flow is). Equally it must not live in the LWC, which is presentational and holds
 * no business logic (CLAUDE.md). A service between them is the correct home, and it reads the
 * graph exclusively through the OI_GraphEngine facade — never a Selector, never SOQL against
 * OI_Graph_Edge__c directly.
 *
 * The category mapping itself is registry-driven, not coded here: a typeKey's category comes
 * from `OI_Node_Type_Descriptor__mdt.Intelligence_Category__c`. Consequently a new scanner +
 * descriptor lands in the right panel section with zero change to this class, which is the
 * whole point of ADR-0011's generic typing. A type with no category is summarised by the
 * existing structural counts and correctly gets no section of its own.
 *
 * Intelligence_Category__c may name MORE THAN ONE category, semicolon-delimited (e.g.
 * "Automation;Code") — a component can genuinely belong under more than one heading (an Apex
 * Trigger is both an automation trigger point and a piece of Apex code); it is listed once per
 * category it is registered for, never merged into a single section.
 *
 * Every item additionally carries a lifecycle status (Active/Inactive, or a tri-state
 * Active/Inactive/Obsolete for ApprovalProcess) read from the node's own attributes through the
 * shared OI_ComponentStatusUtil — see enrichItemAttributes. Flow items further carry a subType
 * split (Flow vs. Process Builder), which stays a small, named exception to "no Salesforce type
 * knowledge here" for exactly the reason this class exists at all: distinguishing a Flow from a
 * Process Builder is domain knowledge an admin needs and the Graph Engine must never learn
 * (ADR-0013), so it belongs here, not in a generic registry field that would otherwise need one
 * bespoke value-mapping mechanism for a single type.
 *
 * Limitations: 1 hop only, by design — these sections answer "what directly touches this?",
 *              which is a different question from Impact Analysis's multi-hop blast radius and
 *              is deliberately not conflated with it. Bounded by MAX_NEIGHBOURS per direction;
 *              exceeding it sets the category's `truncated` flag rather than silently dropping
 *              neighbours. Structure-category neighbours (fields, related objects) are
 *              intentionally excluded from the named lists: an object has hundreds of fields and
 *              listing them here would bury the handful of triggers and permission sets that
 *              are the actual signal — they remain available as counts and in the Fields
 *              browser. Coverage notes are static per category because they describe what the
 *              SCANNERS structurally support, which does not vary per node; per-run degradation
 *              is reported separately on the scan task itself (OI_ScanCoverage).
 */
public inherited sharing class OI_NodeIntelligenceService {
  private static final String DIRECTION_FORWARD = 'forward';
  private static final String DIRECTION_REVERSE = 'reverse';
  private static final String CATEGORY_AUTOMATION = 'Automation';
  private static final String CATEGORY_CODE = 'Code';
  private static final String CATEGORY_SECURITY = 'Security';
  /** Categories that earn their own named section, in display order. Structure/Data are deliberately absent — see this class's Limitations. */
  private static final List<String> SECTION_CATEGORIES = new List<String>{
    CATEGORY_AUTOMATION,
    CATEGORY_CODE,
    CATEGORY_SECURITY
  };
  private static final Integer MAX_NEIGHBOURS = 50;
  private static final String CATEGORY_DELIMITER = ';';
  /** Flow's own typeKey — the one type this class knows by name, for the status/Process-Builder split. See class doc comment. */
  private static final String FLOW_TYPE_KEY = 'SalesforceMetadata.Flow';
  private static final String PROCESS_BUILDER_SUBTYPE_KEY = 'ProcessBuilder';
  private static final String PROCESS_BUILDER_PROCESS_TYPE = 'Workflow';

  /**
   * What each category's underlying scanners structurally cannot see. Shown even for an empty
   * section, because "no triggers found" and "we cannot detect triggers" are completely
   * different statements to an admin and an empty list alone cannot distinguish them.
   */
  private static final Map<String, String> COVERAGE_NOTE_BY_CATEGORY = new Map<String, String>{
    CATEGORY_AUTOMATION => 'Detected: the object each Apex trigger, record-triggered Flow, Workflow Rule, Validation Rule, and Approval Process fires on/validates/applies to, each Workflow Rule\'s Email Alert actions, and whether each Workflow Rule, Validation Rule, or Approval Process is active. Not detected: what a Flow reads or updates internally, which specific fields a Validation Rule\'s formula references (see the Field dependency section for that), a Workflow Rule\'s field-update/task/outbound-message actions, an Email Alert\'s recipients or template, or an Approval Process\'s entry criteria, steps, and approvers.',
    CATEGORY_CODE => 'Detected: Apex class and trigger references matched by name against source. Not detected: dynamic Apex (Type.forName) or interface indirection.',
    CATEGORY_SECURITY => 'Detected: object-level and Apex-class grants from permission sets, and the object each Sharing Rule extends access to. Not detected: field-level grants, grants from profiles, or a Sharing Rule\'s criteria/owner rule and recipient groups.'
  };

  private final OI_GraphEngine graphEngine;

  public OI_NodeIntelligenceService() {
    this(new OI_GraphEngine());
  }

  public OI_NodeIntelligenceService(OI_GraphEngine graphEngine) {
    this.graphEngine = graphEngine;
  }

  public OI_NodeIntelligenceDTO getIntelligence(String nodeKey) {
    if (String.isBlank(nodeKey)) {
      throw new OI_ValidationException(
        'A node key is required to load intelligence.'
      );
    }

    Map<String, List<CategoryDescriptor>> descriptorByTypeKey = loadCategoryDescriptors();
    Map<String, List<OI_NodeIntelligenceDTO.RelatedComponent>> itemsByCategory = new Map<String, List<OI_NodeIntelligenceDTO.RelatedComponent>>();
    Map<String, Boolean> truncatedByCategory = new Map<String, Boolean>();
    for (String category : SECTION_CATEGORIES) {
      itemsByCategory.put(
        category,
        new List<OI_NodeIntelligenceDTO.RelatedComponent>()
      );
      truncatedByCategory.put(category, false);
    }

    /**
     * Both directions matter and mean different things: a trigger firing ON this object
     * arrives as an incoming neighbour, whereas a class this class CALLS is outgoing.
     * Collapsing them would make "who depends on me" indistinguishable from "what I depend
     * on" — the single most important distinction in the whole panel.
     */
    collectNeighbours(
      nodeKey,
      DIRECTION_FORWARD,
      'outgoing',
      descriptorByTypeKey,
      itemsByCategory,
      truncatedByCategory
    );
    collectNeighbours(
      nodeKey,
      DIRECTION_REVERSE,
      'incoming',
      descriptorByTypeKey,
      itemsByCategory,
      truncatedByCategory
    );
    enrichItemAttributes(itemsByCategory);

    List<OI_NodeIntelligenceDTO.Category> categories = new List<OI_NodeIntelligenceDTO.Category>();
    for (String category : SECTION_CATEGORIES) {
      categories.add(
        new OI_NodeIntelligenceDTO.Category(
          category,
          itemsByCategory.get(category),
          truncatedByCategory.get(category),
          COVERAGE_NOTE_BY_CATEGORY.get(category)
        )
      );
    }

    return new OI_NodeIntelligenceDTO(
      nodeKey,
      categories,
      resolveLastScannedAt(),
      resolveHasCoverageLimitations()
    );
  }

  /**
   * One bounded directional read, grouped by registry category. Deduplicates by nodeKey within
   * a category so a neighbour reachable by two different edge types is listed once — a user
   * seeing the same trigger twice would reasonably assume the data is wrong.
   */
  private void collectNeighbours(
    String nodeKey,
    String traversalDirection,
    String userFacingDirection,
    Map<String, List<CategoryDescriptor>> descriptorByTypeKey,
    Map<String, List<OI_NodeIntelligenceDTO.RelatedComponent>> itemsByCategory,
    Map<String, Boolean> truncatedByCategory
  ) {
    OI_GraphFragment fragment = graphEngine.getImpactSubgraph(
      nodeKey,
      traversalDirection,
      null,
      1,
      MAX_NEIGHBOURS
    );
    Map<String, String> edgeTypeKeyByNeighbourKey = buildEdgeTypeKeyByNeighbour(
      fragment.edges,
      nodeKey
    );
    for (OI_NodeSummary summary : fragment.nodes) {
      if (summary.nodeKey == nodeKey) {
        continue;
      }
      List<CategoryDescriptor> descriptors = descriptorByTypeKey.get(
        summary.typeKey
      );
      if (descriptors == null) {
        continue;
      }
      /** A typeKey registered for more than one category (e.g. "Automation;Code") is listed once per category — it genuinely belongs in both, never merged into a single section. */
      for (CategoryDescriptor descriptor : descriptors) {
        if (!itemsByCategory.containsKey(descriptor.category)) {
          continue;
        }
        List<OI_NodeIntelligenceDTO.RelatedComponent> bucket = itemsByCategory.get(
          descriptor.category
        );
        if (containsNodeKey(bucket, summary.nodeKey)) {
          continue;
        }
        if (bucket.size() >= MAX_NEIGHBOURS) {
          truncatedByCategory.put(descriptor.category, true);
          continue;
        }
        OI_NodeIntelligenceDTO.RelatedComponent component = new OI_NodeIntelligenceDTO.RelatedComponent(
          summary.nodeKey,
          summary.label,
          summary.typeKey,
          descriptor.displayLabel == null
            ? summary.typeKey
            : descriptor.displayLabel,
          userFacingDirection
        );
        component.edgeTypeKey = edgeTypeKeyByNeighbourKey.get(summary.nodeKey);
        bucket.add(component);
      }
    }
    if (fragment.hasMore == true) {
      /** The traversal itself hit its ceiling, so every category this read could have contributed to is potentially incomplete — flagged conservatively rather than guessing which one lost data. */
      for (String category : SECTION_CATEGORIES) {
        truncatedByCategory.put(category, true);
      }
    }
  }

  private Boolean containsNodeKey(
    List<OI_NodeIntelligenceDTO.RelatedComponent> bucket,
    String nodeKey
  ) {
    for (OI_NodeIntelligenceDTO.RelatedComponent existing : bucket) {
      if (existing.nodeKey == nodeKey) {
        return true;
      }
    }
    return false;
  }

  /**
   * Maps each neighbour reached in this traversal to the edge type that reached it — the other
   * end of whichever edge touches the anchor nodeKey. A neighbour reachable through more than one
   * edge type keeps the first one encountered, the same "first reaches it, wins" rule
   * collectNeighbours already applies to bucket membership itself.
   */
  private Map<String, String> buildEdgeTypeKeyByNeighbour(
    List<OI_EdgeSummary> edges,
    String nodeKey
  ) {
    Map<String, String> edgeTypeKeyByNeighbour = new Map<String, String>();
    for (OI_EdgeSummary edgeSummary : edges) {
      String neighbourKey = null;
      if (edgeSummary.sourceNodeKey == nodeKey) {
        neighbourKey = edgeSummary.targetNodeKey;
      } else if (edgeSummary.targetNodeKey == nodeKey) {
        neighbourKey = edgeSummary.sourceNodeKey;
      }
      if (
        neighbourKey != null &&
        !edgeTypeKeyByNeighbour.containsKey(neighbourKey)
      ) {
        edgeTypeKeyByNeighbour.put(neighbourKey, edgeSummary.typeKey);
      }
    }
    return edgeTypeKeyByNeighbour;
  }

  /**
   * The registry lookup that keeps this class free of hardcoded Salesforce type knowledge — see
   * the class doc comment. A typeKey maps to one descriptor per semicolon-delimited category in
   * Intelligence_Category__c, so a dual-registered type (e.g. "Automation;Code") comes back as
   * two entries sharing the same display label.
   */
  private Map<String, List<CategoryDescriptor>> loadCategoryDescriptors() {
    Map<String, List<CategoryDescriptor>> byTypeKey = new Map<String, List<CategoryDescriptor>>();
    for (OI_Node_Type_Descriptor__mdt descriptor : [
      SELECT Type_Key__c, Display_Label__c, Intelligence_Category__c
      FROM OI_Node_Type_Descriptor__mdt
      WHERE Intelligence_Category__c != NULL
    ]) {
      List<CategoryDescriptor> descriptors = new List<CategoryDescriptor>();
      for (
        String category : descriptor.Intelligence_Category__c.split(
          CATEGORY_DELIMITER
        )
      ) {
        if (String.isNotBlank(category)) {
          descriptors.add(
            new CategoryDescriptor(category.trim(), descriptor.Display_Label__c)
          );
        }
      }
      byTypeKey.put(descriptor.Type_Key__c, descriptors);
    }
    return byTypeKey;
  }

  /**
   * Attaches each item's lifecycle status through the shared OI_ComponentStatusUtil (so the same
   * component reports the same status here and in the connections drill-down), and, for Flow
   * items only, the Flow-vs-Process-Builder subType split — all read from attributes the scanners
   * already persist (isActive/active/state, processType), never a second scan or a live org read.
   * Runs once, after both traversal directions have populated itemsByCategory, over the union of
   * every collected nodeKey (never the whole neighbourhood) to keep this a single small bulk
   * query.
   */
  private void enrichItemAttributes(
    Map<String, List<OI_NodeIntelligenceDTO.RelatedComponent>> itemsByCategory
  ) {
    List<OI_NodeIntelligenceDTO.RelatedComponent> allItems = new List<OI_NodeIntelligenceDTO.RelatedComponent>();
    Set<String> allNodeKeys = new Set<String>();
    for (
      List<OI_NodeIntelligenceDTO.RelatedComponent> bucket : itemsByCategory.values()
    ) {
      for (OI_NodeIntelligenceDTO.RelatedComponent item : bucket) {
        allItems.add(item);
        allNodeKeys.add(item.nodeKey);
      }
    }
    if (allItems.isEmpty()) {
      return;
    }
    Map<String, Map<String, Object>> attributesByNodeKey = new Map<String, Map<String, Object>>();
    for (
      OI_Graph_Node__c node : new OI_NodeSelector()
        .selectCurrentByKeys(allNodeKeys)
    ) {
      attributesByNodeKey.put(
        node.Node_Key__c,
        OI_JsonUtil.toMap(node.Attributes_Json__c)
      );
    }
    for (OI_NodeIntelligenceDTO.RelatedComponent item : allItems) {
      Map<String, Object> attributes = attributesByNodeKey.get(item.nodeKey);
      if (attributes == null) {
        continue;
      }
      item.status = OI_ComponentStatusUtil.normalizeStatus(attributes);
      if (item.typeKey != FLOW_TYPE_KEY) {
        continue;
      }
      String processType = (String) attributes.get('processType');
      if (processType == PROCESS_BUILDER_PROCESS_TYPE) {
        item.subTypeKey = PROCESS_BUILDER_SUBTYPE_KEY;
        item.subTypeLabel = 'Process Builder';
      } else {
        item.subTypeKey = FLOW_TYPE_KEY;
        item.subTypeLabel = 'Flow';
      }
    }
  }

  /** When the graph was last successfully refreshed. Null when no scan has ever completed — the UI must say "never scanned" rather than imply freshness. */
  private Datetime resolveLastScannedAt() {
    List<OI_Scan_Run__c> runs = [
      SELECT LastModifiedDate
      FROM OI_Scan_Run__c
      WHERE Status__c = 'Completed'
      ORDER BY LastModifiedDate DESC
      LIMIT 1
    ];
    return runs.isEmpty() ? null : runs[0].LastModifiedDate;
  }

  /**
   * Whether the most recent scan knowingly left dependency coverage incomplete. Read from the
   * scan tasks' own recorded coverage rather than assumed, so this reflects what actually
   * happened on the last run rather than a static claim.
   */
  private Boolean resolveHasCoverageLimitations() {
    List<OI_Scan_Run__c> runs = [
      SELECT Id
      FROM OI_Scan_Run__c
      WHERE Status__c = 'Completed'
      ORDER BY LastModifiedDate DESC
      LIMIT 1
    ];
    if (runs.isEmpty()) {
      return false;
    }
    /** Delegated so this returns false rather than throwing where the coverage fields are not visible — the per-section coverage notes, which need no persisted fields, are shown regardless. */
    return OI_ScanCoverageFields.hasLimitations(runs[0].Id);
  }

  private class CategoryDescriptor {
    private final String category;
    private final String displayLabel;

    private CategoryDescriptor(String category, String displayLabel) {
      this.category = category;
      this.displayLabel = displayLabel;
    }
  }
}
