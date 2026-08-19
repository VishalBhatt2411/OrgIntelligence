/**
 * Purpose: Verifies OI_SecurityService's Custom Permission gating (CodingStandards.md §8).
 * Note: the org-running user for this package's own deployment/test execution is
 * expected to have OI_Administrator assigned (required for FLS on optional fields —
 * see the Sprint 7 deliverables report) — so the denied-permission path is tested
 * against a freshly-created user with no permission sets assigned, via System.runAs,
 * rather than assuming anything about whichever user happens to be running the suite.
 */
@isTest
private class OI_SecurityServiceTest {
    @isTest
    static void testHasPermissionTrueForCurrentUser() {
        System.assertEquals(true, OI_SecurityService.hasPermission('OI_View_Graph'), 'The deploying/test-running user is expected to have OI_Administrator assigned.');
    }

    @isTest
    static void testAssertPermissionThrowsForUserWithoutPermission() {
        User unprivileged = createUnprivilegedTestUser();
        System.runAs(unprivileged) {
            try {
                OI_SecurityService.assertPermission('OI_View_Graph');
                System.assert(false, 'Expected OI_SecurityException when the permission is not assigned.');
            } catch (OI_SecurityException e) {
                System.assert(true);
            }
        }
    }

    @isTest
    static void testHasPermissionFalseForUserWithoutPermission() {
        User unprivileged = createUnprivilegedTestUser();
        System.runAs(unprivileged) {
            System.assertEquals(false, OI_SecurityService.hasPermission('OI_View_Graph'));
        }
    }

    private static User createUnprivilegedTestUser() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniqueSuffix = String.valueOf(Crypto.getRandomInteger()).right(8);
        User u = new User(
            FirstName = 'OI Test',
            LastName = 'Unprivileged' + uniqueSuffix,
            Email = 'oi.test.' + uniqueSuffix + '@example.invalid',
            Username = 'oi.test.' + uniqueSuffix + '@example.invalid',
            Alias = 'oitst' + uniqueSuffix.left(3),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = standardProfile.Id
        );
        insert u;
        return u;
    }
}
