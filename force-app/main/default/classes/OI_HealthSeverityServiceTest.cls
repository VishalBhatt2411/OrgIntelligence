/**
 * Purpose: Verifies OI_HealthSeverityService's registry read and score-to-severity band
 *          resolution, including the mandatory generic-fallback (null) behavior.
 */
@isTest
private class OI_HealthSeverityServiceTest {
  @isTest
  static void testGetSeverityRegistryReturnsAllThreeSeedRecords() {
    List<OI_HealthSeverityDescriptorDTO> registry = new OI_HealthSeverityService()
      .getSeverityRegistry();
    Set<String> keys = new Set<String>();
    for (OI_HealthSeverityDescriptorDTO row : registry) {
      keys.add(row.severityKey);
    }
    System.assertEquals(true, keys.contains('Good'));
    System.assertEquals(true, keys.contains('Warning'));
    System.assertEquals(true, keys.contains('Critical'));
  }

  @isTest
  static void testResolveSeverityKeyMapsScoreToTheCorrectBand() {
    OI_HealthSeverityService service = new OI_HealthSeverityService();
    System.assertEquals('Good', service.resolveSeverityKey(85));
    System.assertEquals('Warning', service.resolveSeverityKey(55));
    System.assertEquals('Critical', service.resolveSeverityKey(10));
  }

  @isTest
  static void testResolveSeverityKeyReturnsNullForNullScore() {
    System.assertEquals(
      null,
      new OI_HealthSeverityService().resolveSeverityKey(null)
    );
  }

  @isTest
  static void testResolveSeverityKeyReturnsNullForAnOutOfBandScore() {
    System.assertEquals(
      null,
      new OI_HealthSeverityService().resolveSeverityKey(-5),
      'A score outside every configured band must resolve to null, never a guessed severity.'
    );
  }
}
