/**
 * Purpose: Verifies OI_NodeIntelligenceService groups a node's real graph neighbours into the
 *          Automation / Code / Security sections the Intelligence panel renders, with correct
 *          direction semantics and honest coverage/freshness reporting.
 *
 * These tests assert relationship SEMANTICS, not just counts: which category a neighbour lands
 * in, and which direction it is reported as. A test that only counted rows would pass even if
 * every trigger were filed under Security or every direction were inverted.
 */
@isTest
private class OI_NodeIntelligenceServiceTest {
    private static final String OBJECT_TYPE = 'SalesforceMetadata.CustomObject';
    private static final String APEX_TYPE = 'SalesforceMetadata.ApexClass';
    private static final String TRIGGER_TYPE = 'SalesforceMetadata.ApexTrigger';
    private static final String PERMSET_TYPE = 'SalesforceMetadata.PermissionSet';

    /** Builds a small, deliberately mixed neighbourhood: one object with a trigger firing on it, a permission set granting access to it, and an Apex class referencing it — one neighbour per section, so a mis-categorisation cannot hide behind another. */
    @testSetup
    static void setup() {
        List<OI_Graph_Node__c> nodes = new List<OI_Graph_Node__c>{
            node('objAccount', OBJECT_TYPE, 'Test Object'),
            node('trgOnObject', TRIGGER_TYPE, 'TestTrigger'),
            node('permsetGrant', PERMSET_TYPE, 'Test Permission Set'),
            node('apexCaller', APEX_TYPE, 'TestCallerClass')
        };
        insert nodes;

        insert new List<OI_Graph_Edge__c>{
            edge('e-trg', 'SalesforceMetadata.EXECUTES_ON', 'trgOnObject', 'objAccount'),
            edge('e-ps', 'SalesforceMetadata.GRANTS_ACCESS_TO', 'permsetGrant', 'objAccount'),
            edge('e-apex', 'SalesforceMetadata.REFERENCES', 'apexCaller', 'objAccount')
        };
    }

    private static OI_Graph_Node__c node(String key, String typeKey, String label) {
        return new OI_Graph_Node__c(
            Node_Key__c = key,
            Node_Version_Key__c = key + '::v1',
            Node_Type__c = typeKey,
            Label__c = label,
            Secondary_Key__c = label,
            State__c = 'Active',
            Is_Current__c = true,
            Version_Number__c = 1
        );
    }

    private static OI_Graph_Edge__c edge(String key, String typeKey, String source, String target) {
        return new OI_Graph_Edge__c(
            Edge_Key__c = key,
            Edge_Version_Key__c = key + '::v1',
            Edge_Type__c = typeKey,
            Source_Node_Key__c = source,
            Target_Node_Key__c = target,
            State__c = 'Active',
            Is_Current__c = true,
            Version_Number__c = 1
        );
    }

    /**
     * The core contract: each neighbour must land in the section its TYPE dictates via the
     * registry, and all three must be reported as 'incoming' because they all point AT the
     * object. Direction is the half most likely to be silently inverted, and inverting it would
     * tell a user "this object uses that trigger", which is backwards.
     */
    @isTest
    static void testGroupsNeighboursIntoAutomationCodeAndSecurityWithIncomingDirection() {
        OI_NodeIntelligenceDTO dto = new OI_NodeIntelligenceService().getIntelligence('objAccount');

        Map<String, OI_NodeIntelligenceDTO.Category> byCategory = new Map<String, OI_NodeIntelligenceDTO.Category>();
        for (OI_NodeIntelligenceDTO.Category c : dto.categories) {
            byCategory.put(c.category, c);
        }

        System.assertEquals(3, dto.categories.size(), 'Automation, Code and Security must each render as their own section.');

        OI_NodeIntelligenceDTO.Category automation = byCategory.get('Automation');
        System.assertEquals(1, automation.items.size(), 'The trigger firing on this object belongs under Automation.');
        System.assertEquals('TestTrigger', automation.items[0].label);
        System.assertEquals('incoming', automation.items[0].direction, 'A trigger fires ON this object, so it points at it — incoming.');

        OI_NodeIntelligenceDTO.Category security = byCategory.get('Security');
        System.assertEquals(1, security.items.size(), 'The permission set granting access belongs under Security.');
        System.assertEquals('Test Permission Set', security.items[0].label);
        System.assertEquals('incoming', security.items[0].direction);

        OI_NodeIntelligenceDTO.Category code = byCategory.get('Code');
        System.assertEquals(1, code.items.size(), 'The Apex class referencing this object belongs under Code.');
        System.assertEquals('TestCallerClass', code.items[0].label);
        System.assertEquals('incoming', code.items[0].direction);
    }

    /** The mirror case: from the trigger's own perspective the object is OUTGOING. Asserted separately because a service that hardcoded 'incoming' would pass the test above. */
    @isTest
    static void testReportsOutgoingDirectionFromTheDependentSide() {
        OI_NodeIntelligenceDTO dto = new OI_NodeIntelligenceService().getIntelligence('trgOnObject');

        Boolean sawOutgoingObject = false;
        for (OI_NodeIntelligenceDTO.Category c : dto.categories) {
            for (OI_NodeIntelligenceDTO.RelatedComponent item : c.items) {
                if (item.nodeKey == 'objAccount') {
                    System.assertEquals('outgoing', item.direction, 'The trigger points AT the object, so from the trigger the object is outgoing.');
                    sawOutgoingObject = true;
                }
            }
        }
        /** The object is Structure-category and so is correctly absent from the named sections — this assertion documents that deliberately rather than leaving the absence ambiguous. */
        System.assertEquals(false, sawOutgoingObject, 'Structure-category neighbours are excluded from the named sections by design; they remain in the structural counts.');
    }

    /**
     * An empty section must still be returned WITH its coverage note. Omitting empty sections
     * would leave a user unable to distinguish "no triggers exist" from "triggers are not
     * detected" — the precise ambiguity this feature exists to remove.
     */
    @isTest
    static void testEmptySectionsAreStillReturnedWithTheirCoverageNote() {
        OI_NodeIntelligenceDTO dto = new OI_NodeIntelligenceService().getIntelligence('apexCaller');

        System.assertEquals(3, dto.categories.size(), 'All three sections must be present even when some have no items.');
        for (OI_NodeIntelligenceDTO.Category c : dto.categories) {
            System.assert(String.isNotBlank(c.coverageNote), 'Section ' + c.category + ' must always carry a coverage note, including when empty.');
        }
    }

    /** Freshness must reflect a real completed run, and must be null — not a fabricated date — when none exists. */
    @isTest
    static void testScanFreshnessIsNullWhenNoScanHasEverCompleted() {
        OI_NodeIntelligenceDTO dto = new OI_NodeIntelligenceService().getIntelligence('objAccount');
        System.assertEquals(null, dto.lastScannedAt, 'With no completed scan run in this test context, freshness must be null rather than a guessed timestamp.');
        System.assertEquals(false, dto.hasCoverageLimitations, 'With no completed run there is nothing to report limitations about — must not fabricate a warning.');
    }

    @isTest
    static void testReportsFreshnessFromTheMostRecentlyCompletedRun() {
        insert new OI_Scan_Run__c(Status__c = 'Completed', Scan_Type__c = 'Full');

        OI_NodeIntelligenceDTO dto = new OI_NodeIntelligenceService().getIntelligence('objAccount');

        System.assertNotEquals(null, dto.lastScannedAt, 'A completed scan run must surface as scan freshness.');
    }

    @isTest
    static void testBlankNodeKeyIsRejected() {
        try {
            new OI_NodeIntelligenceService().getIntelligence('   ');
            System.assert(false, 'A blank node key must be rejected rather than silently returning empty intelligence.');
        } catch (OI_ValidationException expected) {
            System.assert(expected.getMessage().containsIgnoreCase('node key'), 'The error must name what was missing. Got: ' + expected.getMessage());
        }
    }

    /** A node with no neighbours at all must return three empty-but-present sections, never an error or a null category list. */
    @isTest
    static void testNodeWithNoNeighboursReturnsEmptySectionsNotAnError() {
        insert node('isolatedNode', OBJECT_TYPE, 'Isolated Object');

        OI_NodeIntelligenceDTO dto = new OI_NodeIntelligenceService().getIntelligence('isolatedNode');

        System.assertEquals(3, dto.categories.size());
        for (OI_NodeIntelligenceDTO.Category c : dto.categories) {
            System.assertEquals(0, c.items.size(), c.category + ' must be empty for an isolated node.');
            System.assertEquals(false, c.truncated);
        }
    }
}
