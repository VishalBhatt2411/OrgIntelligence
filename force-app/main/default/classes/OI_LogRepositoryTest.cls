/**
 * Purpose: Verifies OI_LogRepository's bulk insert and no-op boundary conditions.
 */
@isTest
private class OI_LogRepositoryTest {
    @isTest
    static void testInsertLogsPersistsRows() {
        new OI_LogRepository().insertLogs(new List<OI_Log__c>{ new OI_Log__c(Timestamp__c = Datetime.now(), Level__c = 'INFO', Message__c = 'test') });
        System.assertEquals(1, [SELECT COUNT() FROM OI_Log__c]);
    }

    @isTest
    static void testInsertLogsNullOrEmptyIsNoOp() {
        new OI_LogRepository().insertLogs(null);
        new OI_LogRepository().insertLogs(new List<OI_Log__c>());
        System.assertEquals(0, [SELECT COUNT() FROM OI_Log__c]);
    }

    @isTest
    static void testInsertLogsBulk() {
        List<OI_Log__c> logs = new List<OI_Log__c>();
        for (Integer i = 0; i < 200; i++) {
            logs.add(new OI_Log__c(Timestamp__c = Datetime.now(), Level__c = 'DEBUG', Message__c = 'm' + i));
        }
        new OI_LogRepository().insertLogs(logs);
        System.assertEquals(200, [SELECT COUNT() FROM OI_Log__c]);
    }
}
