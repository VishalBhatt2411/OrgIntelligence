/**
 * Purpose: Verifies OI_ObjectSharingSettingsService's mapping and its "report unsupported
 *          rather than throw" behavior on every Tooling API failure mode, using DI-based fakes
 *          for OI_ToolingApiAdapter (CodingStandards.md) rather than a real HTTP callout — the
 *          Adapter's own callout contract is covered separately by OI_ToolingApiAdapterTest.
 */
@isTest
private class OI_ObjectSharingSettingsServiceTest {
  @isTest
  static void testReturnsTheSharingModelWhenToolingApiReturnsARow() {
    OI_ObjectSharingSettingsService service = new OI_ObjectSharingSettingsService(
      new FakeToolingApiAdapter(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'InternalSharingModel' => 'ReadWrite',
            'ExternalSharingModel' => 'Private'
          }
        }
      )
    );

    OI_ObjectSharingSettingsDTO result = service.getObjectSharingSettings(
      'Account'
    );

    System.assertEquals(true, result.supported);
    System.assertEquals(null, result.unavailableReason);
    System.assertEquals('ReadWrite', result.internalSharingModel);
    System.assertEquals('Private', result.externalSharingModel);
  }

  @isTest
  static void testReturnsANullExternalSharingModelWhenNotApplicable() {
    OI_ObjectSharingSettingsService service = new OI_ObjectSharingSettingsService(
      new FakeToolingApiAdapter(
        new List<Map<String, Object>>{
          new Map<String, Object>{
            'InternalSharingModel' => 'Private',
            'ExternalSharingModel' => null
          }
        }
      )
    );

    OI_ObjectSharingSettingsDTO result = service.getObjectSharingSettings(
      'Account'
    );

    System.assertEquals(true, result.supported);
    System.assertEquals('Private', result.internalSharingModel);
    System.assertEquals(
      null,
      result.externalSharingModel,
      'External Sharing Model not being enabled for this org/object is a real, common case — not an error.'
    );
  }

  @isTest
  static void testReportsUnsupportedWhenToolingApiReturnsNoRows() {
    OI_ObjectSharingSettingsService service = new OI_ObjectSharingSettingsService(
      new FakeToolingApiAdapter(new List<Map<String, Object>>())
    );

    OI_ObjectSharingSettingsDTO result = service.getObjectSharingSettings(
      'Account'
    );

    System.assertEquals(false, result.supported);
    System.assertNotEquals(null, result.unavailableReason);
    System.assertEquals(null, result.internalSharingModel);
  }

  @isTest
  static void testReportsUnsupportedRatherThanThrowingWhenTheAdapterFails() {
    OI_ObjectSharingSettingsService service = new OI_ObjectSharingSettingsService(
      new ThrowingToolingApiAdapter()
    );

    OI_ObjectSharingSettingsDTO result = service.getObjectSharingSettings(
      'Account'
    );

    System.assertEquals(false, result.supported);
    System.assertNotEquals(null, result.unavailableReason);
  }

  @isTest
  static void testThrowsValidationExceptionForAnUnknownObject() {
    OI_ObjectSharingSettingsService service = new OI_ObjectSharingSettingsService(
      new FakeToolingApiAdapter(new List<Map<String, Object>>())
    );

    try {
      service.getObjectSharingSettings('Not_A_Real_Object__x');
      System.assert(
        false,
        'Expected an OI_ValidationException for an unknown object — never a Tooling API callout attempt against a name that cannot exist.'
      );
    } catch (OI_ValidationException e) {
      System.assert(true);
    }
  }

  private class FakeToolingApiAdapter extends OI_ToolingApiAdapter {
    private final List<Map<String, Object>> records;

    private FakeToolingApiAdapter(List<Map<String, Object>> records) {
      this.records = records;
    }

    public override List<Map<String, Object>> query(String soql) {
      return records;
    }
  }

  private class ThrowingToolingApiAdapter extends OI_ToolingApiAdapter {
    public override List<Map<String, Object>> query(String soql) {
      throw new OI_ServiceException('Simulated Tooling API failure.');
    }
  }
}
