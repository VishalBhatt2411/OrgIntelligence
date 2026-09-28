/**
 * Purpose: Verifies OI_ComponentStatusUtil recognises both attribute shapes scanners use for
 *          lifecycle status (boolean isActive/active, tri-state state string) and never guesses
 *          when neither is present or a value is the wrong type.
 */
@isTest
private class OI_ComponentStatusUtilTest {
  @isTest
  static void testIsActiveTrueSurfacesAsActive() {
    System.assertEquals(
      'Active',
      OI_ComponentStatusUtil.normalizeStatus(
        new Map<String, Object>{ 'isActive' => true }
      )
    );
  }

  @isTest
  static void testIsActiveFalseSurfacesAsInactive() {
    System.assertEquals(
      'Inactive',
      OI_ComponentStatusUtil.normalizeStatus(
        new Map<String, Object>{ 'isActive' => false }
      )
    );
  }

  @isTest
  static void testActiveTrueSurfacesAsActive() {
    System.assertEquals(
      'Active',
      OI_ComponentStatusUtil.normalizeStatus(
        new Map<String, Object>{ 'active' => true }
      )
    );
  }

  @isTest
  static void testActiveFalseSurfacesAsInactive() {
    System.assertEquals(
      'Inactive',
      OI_ComponentStatusUtil.normalizeStatus(
        new Map<String, Object>{ 'active' => false }
      )
    );
  }

  @isTest
  static void testTriStateStringIsPassedThroughVerbatim() {
    System.assertEquals(
      'Obsolete',
      OI_ComponentStatusUtil.normalizeStatus(
        new Map<String, Object>{ 'state' => 'Obsolete' }
      ),
      'ApprovalProcess.State is already display-ready — must be passed through, never rewritten.'
    );
  }

  @isTest
  static void testNullAttributesReturnsNull() {
    System.assertEquals(null, OI_ComponentStatusUtil.normalizeStatus(null));
  }

  @isTest
  static void testAttributesWithNoRecognisedKeyReturnsNull() {
    System.assertEquals(
      null,
      OI_ComponentStatusUtil.normalizeStatus(
        new Map<String, Object>{ 'objectApiName' => 'Account' }
      ),
      'A type with no status concept (e.g. EmailAlert, SharingRule) must return null, never a guess.'
    );
  }

  @isTest
  static void testActiveKeyPresentButNullValueReturnsNullRatherThanInactive() {
    System.assertEquals(
      null,
      OI_ComponentStatusUtil.normalizeStatus(
        new Map<String, Object>{ 'active' => null }
      ),
      'A present-but-null flag must not be misread as false/Inactive.'
    );
  }
}
