/**
 * Purpose: Verifies OI_TD_UsageMatcher gives the same answers as a per-needle substring search,
 *          and OI_TD_DataStore's chunked storage.
 */
@isTest
private class OI_TD_UsageMatcherTest {
  @isTest
  static void matchesWordAndNonWordNeedles() {
    OI_TD_UsageMatcher m = new OI_TD_UsageMatcher(
      new Set<String>{
        'Invoice__c',
        'Invoice',
        'Amount',
        'My Rule',
        'Missing',
        ''
      }
    );
    Set<String> found = m.match(
      'List<Invoice__c> rows = [SELECT TotalAmount__c FROM Invoice__c]; // My Rule'
    );
    System.assert(found.contains('Invoice__c'));
    System.assert(found.contains('Invoice'));
    System.assert(found.contains('Amount'), 'substring inside a longer token');
    System.assert(found.contains('My Rule'));
    System.assert(!found.contains('Missing'));

    // Cached tokens give the same answer on a second document.
    System.assert(m.match('Invoice__c x;').contains('Invoice__c'));
    System.assert(m.match('').isEmpty());
    System.assert(m.match(null).isEmpty());
    System.assert(
      !m.match('invoice__c').contains('Invoice__c'),
      'matching is case-sensitive'
    );
  }

  @isTest
  static void onlyNonWordNeedles() {
    OI_TD_UsageMatcher m = new OI_TD_UsageMatcher(
      new Set<String>{ 'Send Email' }
    );
    System.assertEquals(
      new Set<String>{ 'Send Email' },
      m.match('Action: Send Email now')
    );
  }

  @isTest
  static void dataStoreChunksAndReads() {
    OI_TD_Scan__c scan = OI_TD_TestSupport.insertScan(
      OI_TD_ScanEngine.STATUS_COMPLETED,
      System.now(),
      90
    );
    String big = 'a'.repeat(OI_TD_DataStore.CHUNK_SIZE) + 'bcd';
    List<OI_TD_Scan_Data__c> rows = OI_TD_DataStore.chunks(
      scan.Id,
      'objects',
      big
    );
    System.assertEquals(2, rows.size());
    insert rows;
    insert OI_TD_DataStore.pack(scan.Id, 'hay:flows:0', 0, '[["F","text"]]');
    insert OI_TD_DataStore.chunks(scan.Id, 'empty', null);

    System.assertEquals(big, OI_TD_DataStore.read(scan.Id, 'objects'));
    System.assertEquals(null, OI_TD_DataStore.read(scan.Id, 'nothing'));
    System.assertEquals(
      '[["F","text"]]',
      OI_TD_DataStore.readPack(scan.Id, 'hay:flows:0', 0)
    );
    System.assertEquals(
      null,
      OI_TD_DataStore.readPack(scan.Id, 'hay:flows:0', 1)
    );
    System.assertEquals(2, OI_TD_DataStore.countPacks(scan.Id, 'objects'));
    System.assertEquals(2, OI_TD_DataStore.existing(scan.Id, 'objects').size());
    System.assertEquals(0, OI_TD_DataStore.readList(scan.Id, 'empty').size());
    System.assertEquals(0, OI_TD_DataStore.readList(scan.Id, 'nothing').size());
  }
}
