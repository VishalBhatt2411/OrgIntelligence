/**
 * Purpose: Deterministic, small OI_IMetadataScanner test double for
 *          OI_ScanOrchestratorQueueableTest — injected via
 *          OI_ScanOrchestratorQueueable.testScannerOverrides so lifecycle tests never
 *          need to drive the real, org-scale Describe/SOQL-based Scanners through the
 *          Orchestrator's chunked chaining (Apex enforces a hard ceiling on total chained
 *          Queueable enqueues within one test method, which a 796-class real org scan
 *          would exceed many times over).
 * Dependencies: OI_DiscoveryBatch, OI_DiscoveredComponent.
 * Limitations: Test-only — annotated @isTest.
 */
@isTest
public class OI_FakeMetadataScanner implements OI_IMetadataScanner {
    private final Integer componentCount;
    private final Boolean isFullSnapshot;

    public OI_FakeMetadataScanner(Integer componentCount, Boolean isFullSnapshot) {
        this.componentCount = componentCount;
        this.isFullSnapshot = isFullSnapshot;
    }

    public OI_DiscoveryBatch scan(OI_ScanContext context) {
        List<OI_DiscoveredComponent> components = new List<OI_DiscoveredComponent>();
        for (Integer i = 0; i < componentCount; i++) {
            String fullyQualifiedName = 'FakeComponent' + i;
            components.add(
                new OI_DiscoveredComponent(
                    OI_ComponentKeyUtil.build('FakeKind', null, fullyQualifiedName),
                    'FakeKind',
                    fullyQualifiedName,
                    null,
                    'Fake',
                    new Map<String, Object>{ 'index' => i },
                    OI_ChecksumUtil.computeChecksum('FakeKind', fullyQualifiedName, new Map<String, Object>{ 'index' => i }),
                    null,
                    null
                )
            );
        }
        return new OI_DiscoveryBatch(context.scanTaskId, 'FakeKind', components, new List<OI_DiscoveredRelationship>(), isFullSnapshot, 0);
    }
}
