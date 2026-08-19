/**
 * Purpose: Verifies OI_LogEventTriggerHandler's field mapping and bulk-safety
 *          (CodingStandards.md §3).
 */
@isTest
private class OI_LogEventTriggerHandlerTest {
    @isTest
    static void testHandleAfterInsertMapsFieldsCorrectly() {
        List<OI_Log_Event__e> events = new List<OI_Log_Event__e>{
            new OI_Log_Event__e(Level__c = 'ERROR', Message__c = 'msg', Source__c = 'src', Correlation_Id__c = 'corr-map', Stack_Trace__c = 'trace')
        };
        new OI_LogEventTriggerHandler().handleAfterInsert(events);
        List<OI_Log__c> logs = [
            SELECT Level__c, Message__c, Source__c, Correlation_Id__c, Stack_Trace__c, Running_User__c
            FROM OI_Log__c
            WHERE Correlation_Id__c = 'corr-map'
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('ERROR', logs[0].Level__c);
        System.assertEquals('msg', logs[0].Message__c);
        System.assertEquals(UserInfo.getUserId(), logs[0].Running_User__c);
    }

    @isTest
    static void testHandleAfterInsertBulk() {
        List<OI_Log_Event__e> events = new List<OI_Log_Event__e>();
        for (Integer i = 0; i < 200; i++) {
            events.add(new OI_Log_Event__e(Level__c = 'INFO', Message__c = 'm' + i, Correlation_Id__c = 'corr-bulk-handler'));
        }
        new OI_LogEventTriggerHandler().handleAfterInsert(events);
        System.assertEquals(200, [SELECT COUNT() FROM OI_Log__c WHERE Correlation_Id__c = 'corr-bulk-handler']);
    }

    @isTest
    static void testHandleAfterInsertEmptyListIsNoOp() {
        new OI_LogEventTriggerHandler().handleAfterInsert(new List<OI_Log_Event__e>());
        System.assertEquals(0, [SELECT COUNT() FROM OI_Log__c]);
    }
}
