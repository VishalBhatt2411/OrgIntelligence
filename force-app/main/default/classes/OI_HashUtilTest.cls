@isTest
private class OI_HashUtilTest {
    @isTest
    static void testHashIsDeterministic() {
        System.assertEquals(OI_HashUtil.hash('abc'), OI_HashUtil.hash('abc'));
    }

    @isTest
    static void testHashDiffersForDifferentInput() {
        System.assertNotEquals(OI_HashUtil.hash('abc'), OI_HashUtil.hash('abd'));
    }

    @isTest
    static void testHashOfNullDoesNotThrow() {
        System.assertNotEquals(null, OI_HashUtil.hash(null));
    }
}
