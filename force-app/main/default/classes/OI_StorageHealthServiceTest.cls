/**
 * Purpose: Verifies OI_StorageHealthService reads real System.OrgLimits and shapes them
 *          into the DTO's used/limit/remaining triples without fabricating any value.
 */
@isTest
private class OI_StorageHealthServiceTest {
  @isTest
  static void testGetStorageHealthPopulatesDataAndFileStorageFromRealOrgLimits() {
    OI_StorageHealthDTO dto = new OI_StorageHealthService().getStorageHealth();

    System.assertNotEquals(
      null,
      dto.dataUsedMb,
      'DataStorageMB is a limit type present in every Salesforce org.'
    );
    System.assertNotEquals(null, dto.dataLimitMb);
    System.assertEquals(dto.dataLimitMb - dto.dataUsedMb, dto.dataRemainingMb);

    System.assertNotEquals(
      null,
      dto.fileUsedMb,
      'FileStorageMB is a limit type present in every Salesforce org.'
    );
    System.assertNotEquals(null, dto.fileLimitMb);
    System.assertEquals(dto.fileLimitMb - dto.fileUsedMb, dto.fileRemainingMb);
  }

  @isTest
  static void testGetStorageHealthReportsNoUnavailableMetricsWhenBothLimitsExist() {
    OI_StorageHealthDTO dto = new OI_StorageHealthService().getStorageHealth();
    System.assertEquals(
      0,
      dto.unavailableMetrics.size(),
      'Both DataStorageMB and FileStorageMB are always present, so nothing should be reported as not obtainable.'
    );
  }
}
