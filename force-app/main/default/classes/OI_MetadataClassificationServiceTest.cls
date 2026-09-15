@IsTest
private class OI_MetadataClassificationServiceTest {
  @IsTest
  static void testClassifyByApiNameResolvesRealStandardAndCustomObjectsInBulk() {
    Map<String, String> classifications = new OI_MetadataClassificationService()
      .classifyByApiName(
        new Set<String>{
          'Account',
          'User',
          'OI_Org_Health_Finding__c',
          'NoSuchObject__doesNotExist'
        }
      );

    System.assertEquals('Standard', classifications.get('Account'));
    System.assertEquals('Standard', classifications.get('User'));
    System.assertEquals(
      'Custom',
      classifications.get('OI_Org_Health_Finding__c'),
      'This org\'s own package object, deployed with no namespace, must classify as Unmanaged Custom.'
    );
    System.assertEquals(
      'Unknown',
      classifications.get('NoSuchObject__doesNotExist'),
      'An API name absent from EntityDefinition must classify Unknown, never guessed as Standard or Custom.'
    );
  }

  @IsTest
  static void testClassifyByApiNameHandlesMoreNamesThanOneEntityDefinitionQueryBatch() {
    Set<String> apiNames = new Set<String>{
      'Account',
      'User',
      'OI_Org_Health_Finding__c'
    };
    for (Integer i = 0; i < 500; i++) {
      apiNames.add('NoSuchObject' + i + '__doesNotExist');
    }

    Map<String, String> classifications = new OI_MetadataClassificationService()
      .classifyByApiName(apiNames);

    System.assertEquals(
      apiNames.size(),
      classifications.size(),
      'Every requested apiName must come back with a value, chunked or not.'
    );
    System.assertEquals('Standard', classifications.get('Account'));
    System.assertEquals(
      'Unknown',
      classifications.get('NoSuchObject0__doesNotExist')
    );
  }

  @IsTest
  static void testClassifyByApiNameReturnsEmptyMapForNullOrEmptyInput() {
    System.assertEquals(
      0,
      new OI_MetadataClassificationService().classifyByApiName(null).size()
    );
    System.assertEquals(
      0,
      new OI_MetadataClassificationService()
        .classifyByApiName(new Set<String>())
        .size()
    );
  }

  @IsTest
  static void testClassifyPublisherIdSystemIsStandard() {
    System.assertEquals(
      'Standard',
      OI_MetadataClassificationService.classify('System', null)
    );
  }

  @IsTest
  static void testClassifyPublisherIdLocalIsUnmanagedCustom() {
    System.assertEquals(
      'Custom',
      OI_MetadataClassificationService.classify('<local>', null)
    );
  }

  @IsTest
  static void testClassifyNamespacedPublisherIsManagedPackage() {
    System.assertEquals(
      'Managed',
      OI_MetadataClassificationService.classify('npsp', 'npsp')
    );
  }

  @IsTest
  static void testClassifyPopulatedPublisherWithoutNamespaceIsStillManaged() {
    System.assertEquals(
      'Managed',
      OI_MetadataClassificationService.classify('someInstalledPackage', null)
    );
  }

  @IsTest
  static void testClassifyBlankPublisherIsUnknown() {
    System.assertEquals(
      'Unknown',
      OI_MetadataClassificationService.classify(null, null)
    );
  }

  @IsTest
  static void testDisplayLabelMapsEveryKnownKeyToItsUserFacingLabel() {
    System.assertEquals(
      'Salesforce Standard',
      OI_MetadataClassificationService.displayLabel('Standard')
    );
    System.assertEquals(
      'Unmanaged Custom',
      OI_MetadataClassificationService.displayLabel('Custom')
    );
    System.assertEquals(
      'Managed Package',
      OI_MetadataClassificationService.displayLabel('Managed')
    );
    System.assertEquals(
      'Unknown/Insufficient Metadata',
      OI_MetadataClassificationService.displayLabel('Unknown')
    );
  }

  @IsTest
  static void testDisplayLabelFallsBackToUnknownForAnUnrecognizedKey() {
    System.assertEquals(
      'Unknown/Insufficient Metadata',
      OI_MetadataClassificationService.displayLabel('SomethingUnrecognized')
    );
  }
}
