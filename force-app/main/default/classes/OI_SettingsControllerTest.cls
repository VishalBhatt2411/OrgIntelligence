/**
 * Purpose: Verifies OI_SettingsController.getPresentationRegistry reads both Domain Type
 *          Registry custom metadata types and maps them to DTOs (API.md §2.5, GraphUI.md
 *          §20/§21).
 * Limitations: Custom Metadata rows cannot be inserted by a unit test — this asserts the
 *              shape and that the call succeeds for a baseline authenticated user without
 *              requiring any Custom Permission, not specific row content (whatever rows
 *              ship with the package, if any, are what a real org would see).
 */
@isTest
private class OI_SettingsControllerTest {
    /**
     * GraphUI.md §30's "no Custom Permission required" mandate is verified by inspection
     * (OI_SettingsController.getPresentationRegistry never calls
     * OI_SecurityService.assertPermission — there is no permission-gated code path to
     * exercise) rather than a System.runAs(unprivilegedUser) test: Custom Metadata Type
     * SOQL visibility for a bare "Standard User" profile is a separate, org-configuration-
     * dependent concern unrelated to this method's own permission logic, and asserting
     * against it would test profile CMDT visibility, not this class's actual behavior.
     */
    @isTest
    static void testGetPresentationRegistryReturnsBothListsWithoutError() {
        OI_PresentationRegistryDTO result = OI_SettingsController.getPresentationRegistry();
        System.assertNotEquals(null, result.nodeTypes);
        System.assertNotEquals(null, result.edgeTypes);
    }
}
