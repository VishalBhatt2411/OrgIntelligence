/**
 * Purpose: Single shared reader that turns a scanned component's own raw attributes into the
 *          one lifecycle status word the UI shows (Intelligence panel RelatedComponent.status,
 *          drill-down Row.status) — used by both OI_NodeIntelligenceService and
 *          OI_NodeConnectionsService so the same component reports the same status wherever it
 *          is shown.
 * Responsibilities: Recognise the two attribute shapes scanners in this codebase actually use for
 *                    "is this thing on" — a boolean flag (Flow's `isActive`, WorkflowRule's and
 *                    ValidationRule's `active`) and a tri-state string (ApprovalProcess's
 *                    `state`: Active/Inactive/Obsolete) — and return one display-ready String.
 *                    Never guesses: a component whose attributes carry none of these keys, or
 *                    whose value is a null/wrong-typed surprise, returns null rather than a
 *                    fabricated status.
 * Dependencies: None. Pure function over a raw attributes Map, so it carries no Graph Engine or
 *               metadata-type knowledge — only the attribute-key convention scanners already
 *               follow (the same neutrality OI_HashUtil/OI_JsonUtil already have).
 * Limitations: A component type with a genuinely different "is this on" attribute name would need
 *              a new recognised key added here. Types with no such concept at all (EmailAlert,
 *              SharingRule) correctly and permanently return null — there is nothing to normalize.
 */
public inherited sharing class OI_ComponentStatusUtil {
  private static final String KEY_IS_ACTIVE = 'isActive';
  private static final String KEY_ACTIVE = 'active';
  private static final String KEY_STATE = 'state';
  private static final String STATUS_ACTIVE = 'Active';
  private static final String STATUS_INACTIVE = 'Inactive';

  /** Reads one component's attributes and returns its display-ready status, or null when the type has no recognised status concept (or the value present is null/not the expected type). */
  public static String normalizeStatus(Map<String, Object> attributes) {
    if (attributes == null) {
      return null;
    }
    String fromBooleanFlag = statusFromBooleanFlag(attributes, KEY_IS_ACTIVE);
    if (fromBooleanFlag != null) {
      return fromBooleanFlag;
    }
    fromBooleanFlag = statusFromBooleanFlag(attributes, KEY_ACTIVE);
    if (fromBooleanFlag != null) {
      return fromBooleanFlag;
    }
    Object stateValue = attributes.get(KEY_STATE);
    if (
      stateValue instanceof String && String.isNotBlank((String) stateValue)
    ) {
      return (String) stateValue;
    }
    return null;
  }

  private static String statusFromBooleanFlag(
    Map<String, Object> attributes,
    String key
  ) {
    Object value = attributes.get(key);
    if (value instanceof Boolean) {
      return ((Boolean) value) ? STATUS_ACTIVE : STATUS_INACTIVE;
    }
    return null;
  }
}
