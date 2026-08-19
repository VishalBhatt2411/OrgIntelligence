/**
 * Purpose: Centralized Custom Permission gating (Architecture.md §14) — the single entry
 *          point every @AuraEnabled/@RestResource method checks before any other logic
 *          (CodingStandards.md §8).
 * Responsibilities: Wrap FeatureManagement.checkPermission with a throw-on-denial helper,
 *                    so a Controller's permission check is one line and one exception type.
 * Dependencies: None (FeatureManagement is a platform static, not an injectable dependency).
 * Limitations: Checks Custom Permission assignment only — CRUD/FLS/sharing on the
 *              underlying data is a separate concern, enforced at the Selector/Repository
 *              layer per object (ADR-0006).
 */
public with sharing class OI_SecurityService {
    public static void assertPermission(String customPermissionApiName) {
        if (!hasPermission(customPermissionApiName)) {
            throw new OI_SecurityException('Access denied.');
        }
    }

    public static Boolean hasPermission(String customPermissionApiName) {
        return FeatureManagement.checkPermission(customPermissionApiName);
    }
}
