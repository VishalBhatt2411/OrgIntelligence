/**
 * Purpose: Recognises the one DML failure an admin can act on when saving anything this app
 *          owns: the org's data storage is full (STORAGE_LIMIT_EXCEEDED).
 * Responsibilities: Tell a storage-limit failure apart from every other exception, and supply
 *                    the single actionable message each write-path controller's translate()
 *                    shows in place of its generic "Something went wrong" text.
 * Dependencies: None.
 * Limitations: Recognises the failure from DmlException status codes, or from the status code
 *              text in the message when an exception was wrapped or rethrown. Apex forbids
 *              constructing a DmlException in user code, so tests exercise the message path.
 */
public with sharing class OI_StorageLimitUtil {
  public static final String STORAGE_FULL_MESSAGE =
    'The data storage of this org is full, so Org Intelligence cannot save changes. ' +
    'Free up data storage (for example, empty the Recycle Bin) and try again.';

  private static final String STORAGE_STATUS_CODE = 'STORAGE_LIMIT_EXCEEDED';

  public static Boolean isStorageLimitFailure(Exception e) {
    if (e == null) {
      return false;
    }
    if (e instanceof DmlException) {
      DmlException dmlError = (DmlException) e;
      for (Integer i = 0; i < dmlError.getNumDml(); i++) {
        if (dmlError.getDmlType(i) == StatusCode.STORAGE_LIMIT_EXCEEDED) {
          return true;
        }
      }
    }
    String text = e.getMessage();
    return text != null && text.contains(STORAGE_STATUS_CODE);
  }
}
