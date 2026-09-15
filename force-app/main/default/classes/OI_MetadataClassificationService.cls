/**
 * Purpose: The single authoritative source for "is this object Salesforce Standard, this org's
 *          own Unmanaged Custom, an installed Managed Package's, or Unknown" — replacing a
 *          naming-convention regex that was both unreliable in principle and, in this codebase's
 *          prior form, actually broken (it ran against the node's friendly Describe Label__c,
 *          not its API name, so a custom object whose label contains spaces or omits
 *          underscores was silently misclassified).
 * Responsibilities: classifyByApiName — one bulk EntityDefinition query for an entire object
 *                    set, never one query per object, using the platform's own publisher
 *                    identity (PublisherId = 'System' for standard, '<local>' for this org's own
 *                    unmanaged metadata, anything else for an installed package) rather than
 *                    pattern-matching a name.
 * Dependencies: EntityDefinition.
 * Limitations: EntityDefinition only describes entities the running user can see and that the
 *              platform still exposes through it; an API name with no matching row (deleted,
 *              or a component kind EntityDefinition does not describe) classifies Unknown rather
 *              than guessing — callers must always handle Unknown as a real, displayable state,
 *              never treat a missing classification as Standard or Custom by default.
 */
public with sharing class OI_MetadataClassificationService {
  public static final String STANDARD = 'Standard';
  public static final String CUSTOM = 'Custom';
  public static final String MANAGED = 'Managed';
  public static final String UNKNOWN = 'Unknown';

  private static final Map<String, String> DISPLAY_LABELS = new Map<String, String>{
    STANDARD => 'Salesforce Standard',
    CUSTOM => 'Unmanaged Custom',
    MANAGED => 'Managed Package',
    UNKNOWN => 'Unknown/Insufficient Metadata'
  };

  /**
   * EntityDefinition is a system entity that does not support queryMore() — a WHERE...IN filter
   * wide enough to match more than one query-locator batch (2,000 rows) throws QueryException
   * instead of paging, unlike every ordinary sObject. Chunking the caller's apiNames keeps each
   * query's own result set (at most one row per requested name) well under that ceiling
   * regardless of how many objects this org has, so this never regresses as the org grows.
   */
  private static final Integer ENTITY_DEFINITION_CHUNK_SIZE = 200;

  /**
   * One bulk query per chunk of the object set. An apiName absent from the result (not found in
   * EntityDefinition at all) is filled in as UNKNOWN so every caller-supplied key always comes
   * back with a value — never a silent gap a caller has to remember to null-check.
   */
  public Map<String, String> classifyByApiName(Set<String> apiNames) {
    Map<String, String> result = new Map<String, String>();
    if (apiNames == null || apiNames.isEmpty()) {
      return result;
    }
    for (
      List<String> apiNameChunk : chunk(
        new List<String>(apiNames),
        ENTITY_DEFINITION_CHUNK_SIZE
      )
    ) {
      for (EntityDefinition definition : [
        SELECT QualifiedApiName, PublisherId, NamespacePrefix
        FROM EntityDefinition
        WHERE QualifiedApiName IN :apiNameChunk
        LIMIT :ENTITY_DEFINITION_CHUNK_SIZE
      ]) {
        result.put(
          definition.QualifiedApiName,
          classify(definition.PublisherId, definition.NamespacePrefix)
        );
      }
    }
    for (String apiName : apiNames) {
      if (!result.containsKey(apiName)) {
        result.put(apiName, UNKNOWN);
      }
    }
    return result;
  }

  private static List<List<String>> chunk(List<String> items, Integer size) {
    List<List<String>> chunks = new List<List<String>>();
    List<String> current = new List<String>();
    for (String item : items) {
      current.add(item);
      if (current.size() == size) {
        chunks.add(current);
        current = new List<String>();
      }
    }
    if (!current.isEmpty()) {
      chunks.add(current);
    }
    return chunks;
  }

  /** The internal classification key ('Standard'/'Custom'/'Managed'/'Unknown') for one already-classified value, rendered as the user-facing label a finding's Component Type should actually display. */
  public static String displayLabel(String classificationKey) {
    String label = DISPLAY_LABELS.get(classificationKey);
    return label == null ? DISPLAY_LABELS.get(UNKNOWN) : label;
  }

  /**
   * PublisherId is the platform's own authoritative answer: 'System' for every Salesforce
   * standard entity, the literal string '<local>' for metadata this org created itself with no
   * namespace, or the namespace prefix of whichever installed package owns it. A populated,
   * non-'<local>' publisher with no separately-exposed NamespacePrefix (rare, but possible for
   * some system-adjacent entities) is still conservatively treated as Managed rather than
   * Unknown, since a real publisher identity — just not one this org owns — is exactly what
   * "installed package" means; only a truly blank publisher falls back to Unknown.
   */
  @TestVisible
  private static String classify(String publisherId, String namespacePrefix) {
    if (publisherId == 'System') {
      return STANDARD;
    }
    if (publisherId == '<local>') {
      return CUSTOM;
    }
    if (String.isNotBlank(namespacePrefix)) {
      return MANAGED;
    }
    if (String.isNotBlank(publisherId)) {
      return MANAGED;
    }
    return UNKNOWN;
  }
}
