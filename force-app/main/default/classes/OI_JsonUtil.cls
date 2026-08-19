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

    public static String toJson(Map<String, Object> attributes) {
        if (attributes == null || attributes.isEmpty()) {
            return null;
        }
        return JSON.serialize(attributes);
    }
}
