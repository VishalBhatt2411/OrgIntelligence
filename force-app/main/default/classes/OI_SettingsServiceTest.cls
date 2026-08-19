/**
 * Purpose: Verifies OI_SettingsService resolves the seeded "Default" OI_Settings__mdt record.
 */
@isTest
private class OI_SettingsServiceTest {
    @isTest
    static void testGetSettingsReturnsSeededDefaults() {
        OI_Settings__mdt settings = new OI_SettingsService().getSettings();
        System.assertNotEquals(null, settings, 'The package must ship a "Default" OI_Settings__mdt record.');
        System.assertEquals('Off', settings.Storage_Migration_Mode__c);
        System.assertEquals('WARN', settings.Log_Level__c);
        System.assertEquals(false, settings.Enable_Record_Search__c);
        System.assertNotEquals(null, settings.Max_Traversal_Node_Count__c);
    }
}
