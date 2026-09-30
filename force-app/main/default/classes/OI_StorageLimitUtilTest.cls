/**
 * Purpose: Verifies OI_StorageLimitUtil recognises a storage-limit failure and nothing else.
 */
@isTest
private class OI_StorageLimitUtilTest {
  /** Apex forbids constructing a DmlException in user code, so the message path uses a stand-in. */
  private class FakeFailureException extends Exception {
  }

  @isTest
  static void testStorageLimitFailureIsRecognised() {
    System.assert(
      OI_StorageLimitUtil.isStorageLimitFailure(
        new FakeFailureException(
          'Insert failed. STORAGE_LIMIT_EXCEEDED, storage limit exceeded: []'
        )
      ),
      'A storage-limit DML failure must be recognised.'
    );
  }

  @isTest
  static void testOtherFailuresAreNotRecognised() {
    System.assert(
      !OI_StorageLimitUtil.isStorageLimitFailure(
        new FakeFailureException('REQUIRED_FIELD_MISSING')
      ),
      'Any other failure keeps its controller-specific generic message.'
    );
    System.assert(
      !OI_StorageLimitUtil.isStorageLimitFailure(new FakeFailureException()),
      'An exception with no message is not a storage failure.'
    );
    System.assert(!OI_StorageLimitUtil.isStorageLimitFailure(null));
  }

  @isTest
  static void testMessageTellsTheAdminWhatToDo() {
    System.assert(
      OI_StorageLimitUtil.STORAGE_FULL_MESSAGE.contains('Recycle Bin')
    );
  }
}
