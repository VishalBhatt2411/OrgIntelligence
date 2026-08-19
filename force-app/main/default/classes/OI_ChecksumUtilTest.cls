@isTest
private class OI_ChecksumUtilTest {
    @isTest
    static void testChecksumIsStableRegardlessOfMapInsertionOrder() {
        Map<String, Object> attributesA = new Map<String, Object>{ 'b' => 2, 'a' => 1 };
        Map<String, Object> attributesB = new Map<String, Object>{ 'a' => 1, 'b' => 2 };
        System.assertEquals(
            OI_ChecksumUtil.computeChecksum('CustomObject', 'Account', attributesA),
            OI_ChecksumUtil.computeChecksum('CustomObject', 'Account', attributesB)
        );
    }

    @isTest
    static void testChecksumChangesWhenAValueChanges() {
        String checksum1 = OI_ChecksumUtil.computeChecksum('CustomObject', 'Account', new Map<String, Object>{ 'label' => 'Account' });
        String checksum2 = OI_ChecksumUtil.computeChecksum('CustomObject', 'Account', new Map<String, Object>{ 'label' => 'Accounts' });
        System.assertNotEquals(checksum1, checksum2);
    }
}
