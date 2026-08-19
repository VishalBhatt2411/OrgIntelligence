@isTest
private class OI_RecordHierarchyControllerTest {
    @isTest
    static void testGetRecordFragmentReturnsTheServiceResult() {
        Account parent = new Account(Name = 'Parent Co');
        insert parent;
        Contact child = new Contact(LastName = 'Kid', AccountId = parent.Id);
        insert child;

        OI_RecordFragmentDTO fragment = OI_RecordHierarchyController.getRecordFragment('Contact', child.Id);

        /** At least the center Contact plus its resolved parent Account (a User owner node may also legitimately appear — see OI_RecordHierarchyServiceTest for why an exact count isn't asserted here). */
        System.assert(fragment.nodes.size() >= 2);
        Boolean foundParent = false;
        for (OI_NodeSummaryDTO node : fragment.nodes) {
            if (node.label == 'Parent Co') {
                foundParent = true;
            }
        }
        System.assert(foundParent, 'The parent Account must appear as a resolved node.');
    }

    @isTest
    static void testGetRecordFragmentWithoutPermissionThrowsAuraHandledException() {
        User unprivileged = createUnprivilegedTestUser();
        System.runAs(unprivileged) {
            try {
                OI_RecordHierarchyController.getRecordFragment('Account', '001000000000000AAA');
                System.assert(false, 'Expected AuraHandledException when OI_View_Records is not assigned.');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
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
