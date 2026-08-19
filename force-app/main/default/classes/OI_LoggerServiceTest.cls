/**
 * Purpose: Verifies OI_LoggerService's level-threshold filtering and async persistence
 *          path (Architecture.md §13).
 */
@isTest
private class OI_LoggerServiceTest {
    @isTest
    static void testDebugBelowDefaultThresholdIsNotPersisted() {
        Test.startTest();
        new OI_LoggerService().debug('debug message', 'OI_LoggerServiceTest', 'corr-debug');
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM OI_Log__c WHERE Correlation_Id__c = 'corr-debug'], 'DEBUG is below the seeded WARN threshold.');
    }

    @isTest
    static void testWarnMeetsThresholdAndIsPersisted() {
        Test.startTest();
        new OI_LoggerService().warn('warn message', 'OI_LoggerServiceTest', 'corr-warn');
        Test.stopTest();
        List<OI_Log__c> logs = [SELECT Level__c, Message__c FROM OI_Log__c WHERE Correlation_Id__c = 'corr-warn'];
        System.assertEquals(1, logs.size());
        System.assertEquals('WARN', logs[0].Level__c);
    }

    @isTest
    static void testErrorCarriesStackTrace() {
        Test.startTest();
        new OI_LoggerService().error('error message', 'OI_LoggerServiceTest', 'corr-error', 'fake stack trace');
        Test.stopTest();
        List<OI_Log__c> logs = [SELECT Stack_Trace__c FROM OI_Log__c WHERE Correlation_Id__c = 'corr-error'];
        System.assertEquals(1, logs.size());
        System.assertEquals('fake stack trace', logs[0].Stack_Trace__c);
    }

    /**
     * Each OI_LoggerService call publishes one Platform Event, and EventBus.publish
     * consumes one DML-equivalent statement per call — 120 (not 200) individual calls
     * is the honest boundary within the platform's 150-statement-per-transaction
     * ceiling. What this test actually verifies is that OI_LogEventTriggerHandler
     * bulk-inserts every event delivered together at Test.stopTest() in one DML,
     * regardless of how many individual publish calls produced them.
     */
    @isTest
    static void testBulkLoggingDeliversAllEventsToTheHandler() {
        Test.startTest();
        OI_LoggerService logger = new OI_LoggerService();
        for (Integer i = 0; i < 120; i++) {
            logger.warn('bulk message ' + i, 'OI_LoggerServiceTest', 'corr-bulk');
        }
        Test.stopTest();
        System.assertEquals(120, [SELECT COUNT() FROM OI_Log__c WHERE Correlation_Id__c = 'corr-bulk']);
    }
}
