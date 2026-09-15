/**
 * Purpose: Verifies OI_DataHealthComputeBatchable's real data-collection logic end-to-end
 *          (against seeded Account/Contact records) and its per-object skip path in isolation.
 * Limitations: Account/Contact/Lead/Opportunity/Case are ordinary business-data objects, so
 *              (unlike ApexClass/PermissionSet) a test's data context starts empty — no real
 *              org data leaks in — making the duplicate-detection assertion below fully
 *              deterministic. The "object not found" skip path is exercised directly via the
 *              @TestVisible processObject seam, since OI_Data_Health_Object_Scope__mdt (a
 *              Custom Metadata Type) cannot be seeded with an invalid row via DML in a test.
 *              The end-to-end test drives start()/execute()/finish() directly (all public,
 *              required by Database.Batchable) rather than through Database.executeBatch —
 *              Salesforce allows at most one real executeBatch invocation across an entire
 *              RunLocalTests execution, and that one call is reserved for
 *              OI_OrgHealthControllerTest.testRecomputeDataHealthEnqueuesTheBatchAndReturnsQueued,
 *              which exercises the real async framework end-to-end through the Controller —
 *              exactly the path the UI actually uses. Calling the interface methods directly
 *              here exercises identical logic without competing for that one-per-run budget.
 */
@isTest
private class OI_DataHealthComputeBatchableTest {
  @isTest
  static void testProcessObjectSkipsAnObjectNotFoundInThisOrgAndRecordsTheReason() {
    OI_DataHealthComputeBatchable batchable = new OI_DataHealthComputeBatchable();

    batchable.processObject('OI_Nonexistent_Object__c', 200);

    System.assertEquals(
      0,
      batchable.signals.size(),
      'An unresolvable object must never produce a signal.'
    );
    System.assertEquals(1, batchable.skippedObjects.size());
    System.assert(
      batchable.skippedObjects[0].startsWith('OI_Nonexistent_Object__c'),
      'The skip reason must name the object it could not resolve.'
    );
    System.assert(
      batchable.skippedObjects[0].contains('not found in this org')
    );
  }

  @isTest
  static void testProcessObjectIgnoresABlankObjectApiNameWithoutError() {
    OI_DataHealthComputeBatchable batchable = new OI_DataHealthComputeBatchable();

    batchable.processObject('', 200);

    System.assertEquals(0, batchable.signals.size());
    System.assertEquals(
      0,
      batchable.skippedObjects.size(),
      'A blank scope row is silently ignored, not reported as a skip.'
    );
  }

  @isTest
  static void testExecuteEndToEndAgainstScopedObjectsProducesAWellFormedPersistedSnapshotWithDuplicateDetection() {
    insert new List<Account>{
      new Account(Name = 'OI Data Health Test 1'),
      new Account(Name = 'OI Data Health Test 2')
    };
    insert new List<Contact>{
      new Contact(
        LastName = 'Doe',
        Email = 'oi.duplicate.test@example.invalid'
      ),
      new Contact(
        LastName = 'Smith',
        Email = 'oi.duplicate.test@example.invalid'
      )
    };

    OI_DataHealthComputeBatchable batchable = new OI_DataHealthComputeBatchable(
      UserInfo.getUserId()
    );
    for (OI_Data_Health_Object_Scope__mdt scopeRow : batchable.start(null)) {
      batchable.execute(
        null,
        new List<OI_Data_Health_Object_Scope__mdt>{ scopeRow }
      );
    }
    batchable.finish(null);

    OI_DataHealthDTO dto = new OI_DataHealthService().getDataHealthDetail();

    System.assertEquals(5, dto.kpiTiles.size());
    System.assert(
      !dto.breakdownRows.isEmpty(),
      'At least one scoped object produced sampled records.'
    );

    Map<String, String> kpiByLabel = new Map<String, String>();
    for (OI_HealthKeyValueDTO tile : dto.kpiTiles) {
      kpiByLabel.put(tile.label, tile.value);
    }
    System.assertEquals(
      5,
      Integer.valueOf(kpiByLabel.get('Objects scanned')),
      'All 5 enabled OI_Data_Health_Object_Scope__mdt rows must be processed.'
    );
    System.assert(
      Integer.valueOf(kpiByLabel.get('Duplicate records')) >= 2,
      'The two Contacts sharing one Email must both count as duplicates.'
    );
  }
}
