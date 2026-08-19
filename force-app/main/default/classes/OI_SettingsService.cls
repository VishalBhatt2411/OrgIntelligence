/**
 * Purpose: Reads OI_Settings__mdt configuration (Architecture.md §4) — the single place
 *          the rest of the platform gets org-wide configuration from.
 * Responsibilities: Resolve the org-default "Default" record. Any runtime business logic
 *                    belongs elsewhere (Architecture.md §4's "does not own" column).
 * Dependencies: OI_Settings__mdt.
 * Limitations: Per-profile/permission-set-group override (DataModel.md §4.3's hierarchical
 *              aspiration) is not implemented this sprint — only the single org-default
 *              record is resolved. Documented as a follow-up, not silently dropped.
 */
public with sharing class OI_SettingsService {
    public OI_Settings__mdt getSettings() {
        OI_Settings__mdt settings = OI_Settings__mdt.getInstance('Default');
        if (settings == null) {
            throw new OI_ServiceException('OI_Settings__mdt "Default" record not found — the package did not seed its default configuration.');
        }
        return settings;
    }
}
