/**
 * Purpose: Verifies OI_NodeConnectionsService — the drill-down behind every count in the
 *          Intelligence panel — with particular emphasis on the product's central promise:
 *          a summary count and its drill-down must describe the exact same set.
 */
@isTest
private class OI_NodeConnectionsServiceTest {
    private static final String OBJECT_TYPE = 'SalesforceMetadata.CustomObject';
    private static final String FIELD_TYPE = 'SalesforceMetadata.CustomField';

    /** One parent object with 5 field children — enough to prove pagination without a large fixture. */
    @testSetup
    static void setup() {
        List<OI_Graph_Node__c> nodes = new List<OI_Graph_Node__c>{ node('objA', OBJECT_TYPE, 'Account', null) };
        for (Integer i = 0; i < 5; i++) {
            nodes.add(node('field' + i, FIELD_TYPE, 'Field ' + i, '{"type":"STRING"}'));
        }
        insert nodes;

        List<OI_Graph_Edge__c> edges = new List<OI_Graph_Edge__c>();
        for (Integer i = 0; i < 5; i++) {
            edges.add(edge('e' + i, 'SalesforceMetadata.HAS_FIELD', 'objA', 'field' + i));
        }
        insert edges;
        /** No custom metadata is inserted here — CMDT records cannot be created via DML in a
         * test context. Role-label assertions below rely on the real, already-deployed
         * OI_Edge_Type_Descriptor.SalesforceMetadata_HAS_FIELD record (Source_Role_Label__c =
         * "Has Field", Target_Role_Label__c = "Field Of"), the same record the running org
         * actually uses. */
    }

    private static OI_Graph_Node__c node(String key, String typeKey, String label, String attributesJson) {
        return new OI_Graph_Node__c(
            Node_Key__c = key,
            Node_Version_Key__c = key + '::v1',
            Node_Type__c = typeKey,
            Label__c = label,
            Secondary_Key__c = label,
            Attributes_Json__c = attributesJson,
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
     * The product's central promise, proven directly: the exact count OI_EdgeSelector's
     * aggregate query reports (what the panel displays) must equal the drill-down's own total.
     * A regression here would mean the panel and its drill-down could silently disagree.
     */
    @isTest
    static void testDrilldownTotalMatchesTheSummaryCountExactly() {
        Integer summaryCount = new OI_EdgeSelector().countCurrentBySourceKeyGroupedByType('objA').get('SalesforceMetadata.HAS_FIELD');

        OI_ConnectionPageDTO page = new OI_NodeConnectionsService().getConnections('objA', 'outgoing', 'SalesforceMetadata.HAS_FIELD', 100, null, null);

        System.assertEquals(5, summaryCount, 'Precondition: the summary count itself must be 5.');
        System.assertEquals(summaryCount, page.totalCount, 'The drill-down total must equal the summary count that opened it — this is the product\'s central promise.');
        System.assertEquals(5, page.rows.size());
    }

    @isTest
    static void testPaginationReturnsDistinctPagesWithNoOverlapAndHasMoreFlagsCorrectly() {
        OI_NodeConnectionsService service = new OI_NodeConnectionsService();
        OI_ConnectionPageDTO firstPage = service.getConnections('objA', 'outgoing', 'SalesforceMetadata.HAS_FIELD', 2, null, null);
        System.assertEquals(2, firstPage.rows.size());
        System.assertEquals(true, firstPage.hasMore);
        System.assertNotEquals(null, firstPage.nextCursor);

        OI_ConnectionPageDTO secondPage = service.getConnections('objA', 'outgoing', 'SalesforceMetadata.HAS_FIELD', 2, firstPage.nextCursor, null);
        System.assertEquals(2, secondPage.rows.size());

        Set<String> firstKeys = new Set<String>();
        for (OI_ConnectionPageDTO.Row row : firstPage.rows) {
            firstKeys.add(row.nodeKey);
        }
        for (OI_ConnectionPageDTO.Row row : secondPage.rows) {
            System.assert(!firstKeys.contains(row.nodeKey), 'Page 2 must not repeat a row already returned on page 1.');
        }

        OI_ConnectionPageDTO thirdPage = service.getConnections('objA', 'outgoing', 'SalesforceMetadata.HAS_FIELD', 2, secondPage.nextCursor, null);
        System.assertEquals(1, thirdPage.rows.size(), 'The last page must return exactly the remainder (5 total - 2 - 2 = 1).');
        System.assertEquals(false, thirdPage.hasMore, 'The final page must not claim more exists.');
    }

    /**
     * From field0's own side (incoming direction), the row IS the object (objA), and it must
     * read as "Account Has Field [this field]" — the object plays HAS_FIELD's SOURCE role, since
     * the object genuinely is the edge's source (Account -> HAS_FIELD -> Field). Getting this
     * backwards would render as "Account Field Of [this field]", which is nonsense.
     */
    @isTest
    static void testIncomingDirectionFindsTheParentNotTheChildren() {
        OI_ConnectionPageDTO page = new OI_NodeConnectionsService().getConnections('field0', 'incoming', 'SalesforceMetadata.HAS_FIELD', 10, null, null);

        System.assertEquals(1, page.rows.size());
        System.assertEquals('objA', page.rows[0].nodeKey);
        System.assertEquals('Has Field', page.rows[0].roleLabel, 'The object is the edge\'s SOURCE, so from the field\'s side the object must read as "Has Field" ("Account Has Field this field"), not the target role.');
    }

    /**
     * From objA's own side (outgoing direction), each row IS a field, and it must read as
     * "[this field] Field Of Account" — the field plays HAS_FIELD's TARGET role, since the field
     * genuinely is the edge's target. Getting this backwards would render as "[field] Has Field
     * Account", which inverts the real relationship.
     */
    @isTest
    static void testOutgoingRoleLabelDescribesTheChildFromTheParentSide() {
        OI_ConnectionPageDTO page = new OI_NodeConnectionsService().getConnections('objA', 'outgoing', 'SalesforceMetadata.HAS_FIELD', 10, null, null);

        System.assertEquals(5, page.rows.size());
        for (OI_ConnectionPageDTO.Row row : page.rows) {
            System.assertEquals('Field Of', row.roleLabel, 'The field is the edge\'s TARGET, so from the object\'s side each field must read as "Field Of" ("this field Field Of Account"), not the source role.');
            System.assertEquals('outgoing', row.direction);
        }
    }

    @isTest
    static void testFieldRowsCarryDataTypeFromTheirOwnScannedAttributes() {
        OI_ConnectionPageDTO page = new OI_NodeConnectionsService().getConnections('objA', 'outgoing', 'SalesforceMetadata.HAS_FIELD', 10, null, null);

        for (OI_ConnectionPageDTO.Row row : page.rows) {
            System.assertEquals('STRING', row.dataType, 'Field rows must surface their real scanned data type, not a blank.');
        }
    }

    @isTest
    static void testSearchNarrowsToMatchingNeighboursAndReportsAFilteredTotal() {
        OI_ConnectionPageDTO page = new OI_NodeConnectionsService().getConnections('objA', 'outgoing', 'SalesforceMetadata.HAS_FIELD', 10, null, 'Field 2');

        System.assertEquals(true, page.isFiltered);
        System.assertEquals(1, page.totalCount, 'The filtered total must reflect only matching rows, not the full unfiltered set of 5.');
        System.assertEquals(1, page.rows.size());
        System.assertEquals('field2', page.rows[0].nodeKey);
    }

    /** A search matching nothing must return a clean empty result, not an error and not (on some platforms) every row via an empty IN-clause. */
    @isTest
    static void testSearchMatchingNothingReturnsAnEmptyFilteredResultRatherThanEverything() {
        OI_ConnectionPageDTO page = new OI_NodeConnectionsService().getConnections('objA', 'outgoing', 'SalesforceMetadata.HAS_FIELD', 10, null, 'NoSuchFieldNameXYZ');

        System.assertEquals(true, page.isFiltered);
        System.assertEquals(0, page.totalCount);
        System.assertEquals(0, page.rows.size());
    }

    @isTest
    static void testBlankNodeKeyIsRejected() {
        try {
            new OI_NodeConnectionsService().getConnections('', 'outgoing', 'SalesforceMetadata.HAS_FIELD', 10, null, null);
            System.assert(false, 'A blank node key must be rejected.');
        } catch (OI_ValidationException expected) {
            System.assert(expected.getMessage().containsIgnoreCase('node key'));
        }
    }

    @isTest
    static void testBlankEdgeTypeKeyIsRejected() {
        try {
            new OI_NodeConnectionsService().getConnections('objA', 'outgoing', '', 10, null, null);
            System.assert(false, 'A blank relationship type must be rejected.');
        } catch (OI_ValidationException expected) {
            System.assert(expected.getMessage().containsIgnoreCase('relationship type'));
        }
    }

    @isTest
    static void testInvalidDirectionIsRejected() {
        try {
            new OI_NodeConnectionsService().getConnections('objA', 'sideways', 'SalesforceMetadata.HAS_FIELD', 10, null, null);
            System.assert(false, 'An unrecognized direction must be rejected rather than silently defaulting.');
        } catch (OI_ValidationException expected) {
            System.assert(expected.getMessage().containsIgnoreCase('direction'));
        }
    }

    /** A category with zero real connections must return a clean, honest empty page — never an error and never a fabricated row. */
    @isTest
    static void testUnsupportedCombinationReturnsAnHonestEmptyPageNotAnError() {
        OI_ConnectionPageDTO page = new OI_NodeConnectionsService().getConnections('objA', 'outgoing', 'SalesforceMetadata.GRANTS_ACCESS_TO', 10, null, null);

        System.assertEquals(0, page.totalCount);
        System.assertEquals(0, page.rows.size());
        System.assertEquals(false, page.hasMore);
    }
}
