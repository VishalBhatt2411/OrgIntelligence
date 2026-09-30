/**
 * Purpose: Small, shared JSON <-> Map conversion helper for the schemaless attribute-bag
 *          fields every Storage Provider maps (GraphEngine.md §2, §8).
 * Responsibilities: Null/blank-safe serialize/deserialize of Map<String, Object> to/from
 *                    the Attributes_Json__c text representation.
 * Dependencies: None.
 * Limitations: Shallow bag only, by convention (GraphEngine.md §8) — this class does not
 *              enforce that convention, only performs the conversion.
 */
public class OI_JsonUtil {
  public static Map<String, Object> toMap(String jsonText) {
    if (String.isBlank(jsonText)) {
      return new Map<String, Object>();
    }
    return (Map<String, Object>) JSON.deserializeUntyped(jsonText);
  }

  /**
   * One integer attribute from an Attributes_Json__c bag, or null when the text is blank,
   * unparseable, or the attribute is absent or not an integer — null means "unknown", so a
   * caller can fall back instead of reporting a false zero (ADR-0031 scan-time aggregates).
   */
  public static Integer readInteger(String jsonText, String attributeName) {
    if (String.isBlank(jsonText)) {
      return null;
    }
    try {
      Object raw = toMap(jsonText).get(attributeName);
      return raw instanceof Integer ? (Integer) raw : null;
    } catch (Exception parseException) {
      return null;
    }
  }

  public static String toJson(Map<String, Object> attributes) {
    if (attributes == null || attributes.isEmpty()) {
      return null;
    }
    return JSON.serialize(attributes);
  }
}
