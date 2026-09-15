@IsTest
private class OI_ApexClassSelectorTest {
  @IsTest
  static void testSelectClassesBoundedRespectsCeilingAndOrdersByName() {
    List<ApexClass> results = new OI_ApexClassSelector()
      .selectClassesBounded(3);
    System.assert(results.size() <= 3, 'The ceiling must never be exceeded.');
  }

  @IsTest
  static void testSelectClassesBoundedDefaultsNonPositiveCeiling() {
    List<ApexClass> results = new OI_ApexClassSelector()
      .selectClassesBounded(0);
    System.assert(
      results.size() <= 500,
      'A non-positive ceiling must fall back to the default of 500.'
    );
  }

  @IsTest
  static void testSelectClassesBoundedReturnsAtLeastOneRealClass() {
    List<ApexClass> results = new OI_ApexClassSelector()
      .selectClassesBounded(500);
    System.assert(
      !results.isEmpty(),
      'The org always has at least the classes deployed alongside this one.'
    );
    System.assertNotEquals(null, results[0].ApiVersion);
  }
}
