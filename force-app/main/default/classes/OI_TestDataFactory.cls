/**
 * Purpose: Factory/builder for constructing OI_Node/OI_Edge/OI_VersionRecord test fixtures
 *          (Architecture.md §16) — no test relies on org-specific existing metadata.
 * Responsibilities: Produce deterministic, realistic fixtures for unit tests across this
 *                    sprint's foundation classes.
 * Dependencies: None.
 * Limitations: Test-only — annotated @isTest so it never counts against org code limits.
 */
@isTest
public class OI_TestDataFactory {
    public static OI_VersionRecord newNodeVersionRecord(String nodeKey, Integer versionNumber, String checksum) {
        return new OI_VersionRecord(
            nodeKey,
            nodeKey + '::v' + versionNumber,
            versionNumber,
            'Test.NodeType',
            'Test Label',
            'TestSecondaryKey',
            null,
            new Map<String, Object>{ 'k' => 'v' },
            checksum,
            'Active',
            null,
            null,
            null,
            true,
            null,
            null
        );
    }

    public static OI_VersionRecord newEdgeVersionRecord(String edgeKey, String sourceKey, String targetKey, Integer versionNumber) {
        return new OI_VersionRecord(
            edgeKey,
            edgeKey + '::v' + versionNumber,
            versionNumber,
            'Test.EdgeType',
            null,
            null,
            null,
            new Map<String, Object>(),
            null,
            'Active',
            null,
            null,
            null,
            true,
            sourceKey,
            targetKey
        );
    }

    public static OI_Scan_Run__c newScanRun() {
        return new OI_Scan_Run__c(Status__c = 'Queued', Scan_Type__c = 'Full');
    }
}
