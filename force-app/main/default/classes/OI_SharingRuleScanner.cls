/**
 * Purpose: Discovers Sharing Rules as Discovery Model components (MetadataScanner.md §6) —
 *          componentKind "SharingRule" — and the Sharing Rule -> Object edge it is defined
 *          against (APPLIES_TO, the same edge kind OI_ApprovalProcessScanner,
 *          OI_WorkflowRuleScanner, and OI_EmailAlertScanner already register). Puts Sharing Rule
 *          into the Object Intelligence Panel's Security section. First (and, at the time of
 *          writing, only) caller of OI_MetadataApiAdapter — Sharing Rules have no Tooling API or
 *          Apex-queryable standard-object equivalent at all, confirmed against the official
 *          Metadata API reference.
 * Responsibilities: Derive this org's in-scope object universe the same way OI_ObjectScanner and
 *                    OI_FieldScanner already do (Schema.getGlobalDescribe -> chunked
 *                    Schema.describeSObjects -> OI_ObjectScopeFilter.isInScope), issue one
 *                    OI_MetadataApiAdapter.readMetadata('SharingRules', chunk) SOAP callout per
 *                    <=10-object chunk (the Metadata API's own hard per-call limit, already
 *                    enforced inside the Adapter), and flatten whichever of the four rule-category
 *                    arrays (sharingCriteriaRules / sharingGuestRules / sharingOwnerRules /
 *                    sharingTerritoryRules) a returned object result carries into one
 *                    OI_DiscoveredComponent per individual rule. Stays graph-blind (never
 *                    constructs a typeKey, never touches OI_GraphEngine).
 * Dependencies: OI_MetadataApiAdapter, OI_ObjectScopeFilter, OI_ScannerObjectResolver,
 *               OI_ComponentKeyUtil, OI_ChecksumUtil.
 *
 * Object universe, not a Tooling/SOQL query: unlike every other Phase 2 scanner, there is no
 * queryable list of "which objects have Sharing Rules" — the Metadata API's readMetadata contract
 * for this type requires the caller to already know which object fullNames to ask about (one
 * component per object, per the official SharingRules reference: "Components of this metadata
 * type are stored in the sharingRules folder... named using the object name"). This scanner
 * therefore drives its callouts from the same in-scope object universe OI_ObjectScanner already
 * computes, rather than introducing a second, divergent notion of "which objects exist."
 *
 * Why no sharing-model pre-filter: only objects whose org-wide default is Private or Public Read
 * Only can carry Sharing Rules, which would let this scanner skip (and not spend a callout on)
 * every Controlled-by-Parent / fully-Public object. This was investigated directly against the
 * official Apex Reference for Schema.DescribeSObjectResult (its complete, alphabetized Properties
 * and Methods lists) and confirmed: DescribeSObjectResult exposes no sharing-model
 * property/method at all — organization-wide default is a Setup/Metadata API concept
 * (OrganizationWideDefault_x) with no Apex Describe accessor. Adding this pre-filter would require
 * a SECOND Metadata API round trip (reading Organization-wide defaults) to save callouts on a
 * THIRD — not a net win for the realistic org sizes this platform targets, and CLAUDE.md's
 * "avoid unnecessary complexity" favors the simpler design. Named, deferred future optimization if
 * very-large-object-count orgs make it worthwhile.
 *
 * Chunking and the per-transaction callout ceiling: OI_ScanOrchestratorQueueable runs exactly one
 * scanner per Queueable hop (confirmed by reading its beginScanTask() dispatch), so this scanner
 * has the full Apex 100-synchronous-callout-per-transaction budget to itself. MAX_METADATA_API_CALLS
 * caps it at 90 (a 10-call safety margin, not a precisely derived number — simple and conservative
 * beats a fragile exact-fit calculation) chunks of <=10 objects each, i.e. up to 900 objects can be
 * checked for Sharing Rules in one run. An org with more in-scope objects than that has the
 * remainder skipped THIS run (reported via OI_ScanCoverage.partial with an explicit skipped-object
 * count) rather than risking a governor-limit exception that would lose the whole batch — the same
 * "never load everything, degrade honestly" posture as OI_ObjectScanner's own documented
 * extreme-object-count limitation. maxMetadataApiCallsOverride is a @TestVisible seam purely so a
 * test can exercise this cap path without needing hundreds of real describable objects.
 *
 * Why namespace is always null on a SharingRule component: unlike WorkflowRule/EmailAlert (which
 * get an explicit NamespacePrefix column from the Tooling API), a Sharing Rule's Metadata API
 * fullName is only ever the compound "<ObjectApiName>.<RuleName>" string with no separate
 * namespace field. OI_ComponentKeyUtil.extractNamespaceFromApiName's namespace__Name__c convention
 * does not reliably apply to rule developer names (no "__c" suffix), so guessing at a namespace
 * split would risk a wrong answer OI_ScannerObjectResolver's own doc comment explicitly warns
 * against ("null means emit no edge, never guess") — extended here to component identity too.
 *
 * Limitations: A rule's criteria filter (booleanFilter/criteriaItems) and its shared-to/shared-from
 *              targets (roles, public groups, territories, roles-and-subordinates, record owners)
 *              are stored as reference-only rawAttributes — this scanner does not resolve them into
 *              their own dependency edges (that correlation is Phase 3/field-dependency territory,
 *              not this scanner's job), which is why coverage is always OI_ScanCoverage.partial on
 *              a fully successful run, mirroring OI_WorkflowRuleScanner/OI_EmailAlertScanner's same
 *              posture. A readMetadata failure on an individual chunk does not abort the whole scan
 *              (unlike the single-query precedent scanners) — remaining chunks still run, and the
 *              batch reports OI_ScanCoverage.degraded only when at least one chunk actually failed,
 *              so a transient failure on one object never discards every other object's already-
 *              retrieved rules.
 */
public with sharing class OI_SharingRuleScanner implements OI_IMetadataScanner {
  private static final String COMPONENT_KIND = 'SharingRule';
  private static final String APPLIES_TO_RELATIONSHIP_KIND = 'APPLIES_TO';
  private static final String METADATA_TYPE = 'SharingRules';
  private static final Integer DESCRIBE_CHUNK_SIZE = 100;
  private static final Integer READ_METADATA_CHUNK_SIZE = 10;
  private static final Integer MAX_METADATA_API_CALLS = 90;
  private static final List<String> RULE_LIST_FIELD_NAMES = new List<String>{
    'sharingCriteriaRules',
    'sharingGuestRules',
    'sharingOwnerRules',
    'sharingTerritoryRules'
  };
  private static final List<String> RULE_LIST_FIELD_LABELS = new List<String>{
    'SharingCriteriaRule',
    'SharingGuestRule',
    'SharingOwnerRule',
    'SharingTerritoryRule'
  };

  /** Test-only override for MAX_METADATA_API_CALLS — see this class's chunking rationale for why. Null means "use the real default." */
  @TestVisible
  private static Integer maxMetadataApiCallsOverride = null;

  private final OI_MetadataApiAdapter metadataApiAdapter;

  public OI_SharingRuleScanner() {
    this(new OI_MetadataApiAdapter());
  }

  /** DI seam for tests (CodingStandards.md's DI-based-fake convention for Adapter dependencies) — the orchestrator (OI_ScanOrchestratorQueueable) always instantiates via the zero-arg constructor above. */
  public OI_SharingRuleScanner(OI_MetadataApiAdapter metadataApiAdapter) {
    this.metadataApiAdapter = metadataApiAdapter;
  }

  public OI_DiscoveryBatch scan(OI_ScanContext context) {
    List<List<String>> chunks = chunk(
      objectUniverse(context),
      READ_METADATA_CHUNK_SIZE
    );

    List<OI_DiscoveredComponent> components = new List<OI_DiscoveredComponent>();
    List<OI_DiscoveredRelationship> relationships = new List<OI_DiscoveredRelationship>();
    Integer apiCallsConsumed = 0;
    Integer failedChunkCount = 0;
    Integer chunkIndex = 0;

    for (List<String> oneChunk : chunks) {
      if (chunkIndex >= effectiveMaxMetadataApiCalls()) {
        break;
      }
      chunkIndex++;
      try {
        List<Map<String, Object>> objectResults = metadataApiAdapter.readMetadata(
          METADATA_TYPE,
          oneChunk
        );
        apiCallsConsumed++;
        for (Map<String, Object> objectResult : objectResults) {
          appendRulesForObject(objectResult, components, relationships);
        }
      } catch (Exception e) {
        apiCallsConsumed++;
        failedChunkCount++;
      }
    }

    Boolean allChunksProcessed = chunkIndex == chunks.size();
    OI_ScanCoverage coverage;
    if (failedChunkCount > 0) {
      coverage = OI_ScanCoverage.degraded(
        relationships.size(),
        failedChunkCount +
          ' of ' +
          chunkIndex +
          ' Sharing Rule batches could not be retrieved from the Metadata API this run (permission or availability issue on the OI_Self_Callout Named Credential, or a transient failure) — retry once resolved. Sharing rules for the affected objects are not reflected.'
      );
    } else {
      String reason = 'A rule\'s criteria filter and the roles/groups/territories/owners it shares to or from are stored as reference-only attributes, not resolved into their own dependency edges — only the applies-to edge to the rule\'s object is emitted.';
      if (!allChunksProcessed) {
        reason +=
          ' Additionally, ' +
          (chunks.size() - chunkIndex) +
          ' of ' +
          chunks.size() +
          ' object batches were skipped this run to stay within a safety margin under Apex\'s per-transaction callout ceiling.';
      }
      coverage = OI_ScanCoverage.partial(relationships.size(), reason);
    }

    return new OI_DiscoveryBatch(
      context.scanTaskId,
      COMPONENT_KIND,
      components,
      relationships,
      failedChunkCount == 0 && allChunksProcessed,
      apiCallsConsumed,
      coverage
    );
  }

  private Integer effectiveMaxMetadataApiCalls() {
    return maxMetadataApiCallsOverride == null
      ? MAX_METADATA_API_CALLS
      : maxMetadataApiCallsOverride;
  }

  /** Same describe-driven in-scope object universe OI_ObjectScanner/OI_FieldScanner already compute — see their class docs for why this must go through Schema.describeSObjects rather than trusting keySet() names alone. */
  private List<String> objectUniverse(OI_ScanContext context) {
    List<String> apiNames = new List<String>(
      Schema.getGlobalDescribe().keySet()
    );
    if (context.scopedApiNames != null) {
      apiNames = filterToScope(apiNames, context.scopedApiNames);
    }
    apiNames.sort();

    List<String> inScopeNames = new List<String>();
    for (
      Integer startIndex = 0;
      startIndex < apiNames.size();
      startIndex += DESCRIBE_CHUNK_SIZE
    ) {
      Integer endIndex = Math.min(
        startIndex + DESCRIBE_CHUNK_SIZE,
        apiNames.size()
      );
      List<String> describeChunk = new List<String>();
      for (Integer i = startIndex; i < endIndex; i++) {
        describeChunk.add(apiNames[i]);
      }
      for (
        Schema.DescribeSObjectResult describeResult : Schema.describeSObjects(
          describeChunk
        )
      ) {
        if (OI_ObjectScopeFilter.isInScope(describeResult)) {
          inScopeNames.add(describeResult.getName());
        }
      }
    }
    return inScopeNames;
  }

  /** Mirrors OI_FieldScanner's scopedApiNames narrowing seam so this scanner is unit-testable without a full org-wide Describe. */
  private List<String> filterToScope(
    List<String> apiNames,
    Set<String> scopedApiNames
  ) {
    Set<String> scopeLower = new Set<String>();
    for (String scopedName : scopedApiNames) {
      scopeLower.add(scopedName.toLowerCase());
    }
    List<String> filtered = new List<String>();
    for (String apiName : apiNames) {
      if (scopeLower.contains(apiName.toLowerCase())) {
        filtered.add(apiName);
      }
    }
    return filtered;
  }

  private List<List<String>> chunk(List<String> apiNames, Integer chunkSize) {
    List<List<String>> chunks = new List<List<String>>();
    for (
      Integer startIndex = 0;
      startIndex < apiNames.size();
      startIndex += chunkSize
    ) {
      Integer endIndex = Math.min(startIndex + chunkSize, apiNames.size());
      List<String> oneChunk = new List<String>();
      for (Integer i = startIndex; i < endIndex; i++) {
        oneChunk.add(apiNames[i]);
      }
      chunks.add(oneChunk);
    }
    return chunks;
  }

  private void appendRulesForObject(
    Map<String, Object> objectResult,
    List<OI_DiscoveredComponent> components,
    List<OI_DiscoveredRelationship> relationships
  ) {
    String objectApiName = (String) objectResult.get('fullName');
    if (String.isBlank(objectApiName)) {
      return;
    }
    String toComponentKey = OI_ScannerObjectResolver.toObjectComponentKey(
      objectApiName
    );

    for (Integer i = 0; i < RULE_LIST_FIELD_NAMES.size(); i++) {
      List<Object> rawRules = normalizeToRuleList(
        objectResult.get(RULE_LIST_FIELD_NAMES[i])
      );
      for (Object rawRule : rawRules) {
        if (!(rawRule instanceof Map<String, Object>)) {
          continue;
        }
        OI_DiscoveredComponent component = toRuleComponent(
          objectApiName,
          RULE_LIST_FIELD_LABELS[i],
          (Map<String, Object>) rawRule
        );
        if (component == null) {
          continue;
        }
        components.add(component);
        if (toComponentKey != null) {
          relationships.add(
            new OI_DiscoveredRelationship(
              component.componentKey +
                '::' +
                APPLIES_TO_RELATIONSHIP_KIND +
                '::' +
                toComponentKey,
              APPLIES_TO_RELATIONSHIP_KIND,
              component.componentKey,
              toComponentKey,
              new Map<String, Object>()
            )
          );
        }
      }
    }
  }

  /** OI_MetadataApiAdapter.nodeToMap collapses a single child element to a bare Map and a repeated one to a List — a Sharing Rule category with exactly one rule looks identical to any other single-element field, so this normalizes both shapes to a uniform List before iterating. */
  private List<Object> normalizeToRuleList(Object raw) {
    if (raw == null) {
      return new List<Object>();
    }
    if (raw instanceof List<Object>) {
      return (List<Object>) raw;
    }
    return new List<Object>{ raw };
  }

  private OI_DiscoveredComponent toRuleComponent(
    String objectApiName,
    String ruleType,
    Map<String, Object> rawRule
  ) {
    String fullName = (String) rawRule.get('fullName');
    if (String.isBlank(fullName)) {
      return null;
    }
    Map<String, Object> attributes = new Map<String, Object>{
      'objectApiName' => objectApiName,
      'ruleType' => ruleType,
      'accessLevel' => rawRule.get('accessLevel'),
      'label' => rawRule.get('label'),
      'description' => rawRule.get('description'),
      'sharedTo' => rawRule.get('sharedTo'),
      'sharedFrom' => rawRule.get('sharedFrom'),
      'accountSettings' => rawRule.get('accountSettings'),
      'booleanFilter' => rawRule.get('booleanFilter'),
      'criteriaItems' => rawRule.get('criteriaItems'),
      'includeRecordsOwnedByAll' => rawRule.get('includeRecordsOwnedByAll'),
      'includeHVUOwnedRecords' => rawRule.get('includeHVUOwnedRecords')
    };
    return new OI_DiscoveredComponent(
      OI_ComponentKeyUtil.build(COMPONENT_KIND, null, fullName),
      COMPONENT_KIND,
      fullName,
      null,
      'Metadata',
      attributes,
      OI_ChecksumUtil.computeChecksum(COMPONENT_KIND, fullName, attributes),
      null,
      null
    );
  }
}
