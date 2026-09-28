/**
 * Purpose: Verifies OI_ApprovalProcessScanner discovers Approval Processes and emits only
 *          well-formed, non-dangling APPLIES_TO edges toward the object each one applies to.
 *
 * Test data strategy: ProcessDefinition is a read-only platform object — a test cannot insert an
 *          Approval Process, and this package ships none, so assertions are written as
 *          PROPERTIES that must hold over whatever Approval Processes the org actually contains
 *          (including none at all), mirroring OI_FlowScannerTest's own established pattern for
 *          the same reason. What these tests genuinely guarantee is that the scanner never emits
 *          a malformed or dangling edge and never fails on an org regardless of its Approval
 *          Process population — not that a specific Approval Process produces a specific edge.
 */
@isTest
private class OI_ApprovalProcessScannerTest {
  @isTest
  static void testScanReturnsAWellFormedBatchRegardlessOfHowManyApprovalProcessesTheOrgHas() {
    OI_DiscoveryBatch batch = new OI_ApprovalProcessScanner()
      .scan(new OI_ScanContext(null, 200, null, 'SOQL'));

    System.assertEquals('ApprovalProcess', batch.componentKind);
    System.assertEquals(true, batch.isFullSnapshot);
    System.assertNotEquals(
      null,
      batch.components,
      'An org with no Approval Processes must still yield an empty batch, never a null or a failure.'
    );
    System.assertNotEquals(null, batch.relationships);
    System.assertEquals(
      OI_ScanCoverage.STATUS_PARTIAL,
      batch.coverage.status,
      'Step/criteria/approver internals are a permanent boundary (Partial), not a failure (Degraded).'
    );
  }

  /** Every discovered Approval Process must carry a usable identity — the invariant OI_MutationGenerator depends on to build a nodeKey at all. */
  @isTest
  static void testEveryDiscoveredApprovalProcessHasACompleteComponentIdentity() {
    OI_DiscoveryBatch batch = new OI_ApprovalProcessScanner()
      .scan(new OI_ScanContext(null, 200, null, 'SOQL'));

    for (OI_DiscoveredComponent component : batch.components) {
      System.assertEquals('ApprovalProcess', component.componentKind);
      System.assert(
        String.isNotBlank(component.componentKey),
        'Every Approval Process component needs a componentKey.'
      );
      System.assert(
        String.isNotBlank(component.fullyQualifiedName),
        'Every Approval Process component needs a fullyQualifiedName.'
      );
      System.assert(
        String.isNotBlank(component.rawChecksum),
        'Every Approval Process component needs a checksum for change detection.'
      );
      System.assertEquals('SOQL', component.sourceApi);
    }
  }

  /** The dangling-edge guard, stated as a property over the whole batch: an APPLIES_TO edge may only target an object OI_ObjectScanner would also create a node for. */
  @isTest
  static void testEveryAppliesToEdgeTargetsAnObjectTheObjectScannerWouldAlsoCreate() {
    OI_DiscoveryBatch batch = new OI_ApprovalProcessScanner()
      .scan(new OI_ScanContext(null, 200, null, 'SOQL'));

    Set<String> approvalProcessComponentKeys = new Set<String>();
    for (OI_DiscoveredComponent component : batch.components) {
      approvalProcessComponentKeys.add(component.componentKey);
    }

    for (OI_DiscoveredRelationship relationship : batch.relationships) {
      System.assertEquals(
        'APPLIES_TO',
        relationship.relationshipKind,
        'This scanner emits no relationship kind other than APPLIES_TO today.'
      );
      System.assert(
        approvalProcessComponentKeys.contains(relationship.fromComponentKey),
        'Every edge must originate from an Approval Process this same batch discovered.'
      );

      OI_ComponentKeyUtil.ParsedComponentKey parsed = OI_ComponentKeyUtil.parse(
        relationship.toComponentKey
      );
      System.assertNotEquals(null, parsed);
      System.assertEquals('CustomObject', parsed.componentKind);

      System.assertEquals(
        parsed.fullyQualifiedName,
        OI_ScannerObjectResolver.canonicalInScopeName(
          parsed.fullyQualifiedName
        ),
        'APPLIES_TO target ' +
          parsed.fullyQualifiedName +
          ' must resolve to itself as an in-scope, node-producing object, or the edge would dangle.'
      );
    }
  }

  /** An Approval Process whose object could not be resolved must simply produce no edge — absence of an edge means "object out of scan scope," never a swallowed failure. */
  @isTest
  static void testApprovalProcessesWithoutAResolvedObjectProduceNoEdgeRatherThanAFabricatedOne() {
    OI_DiscoveryBatch batch = new OI_ApprovalProcessScanner()
      .scan(new OI_ScanContext(null, 200, null, 'SOQL'));

    Set<String> keysWithAnEdge = new Set<String>();
    for (OI_DiscoveredRelationship relationship : batch.relationships) {
      keysWithAnEdge.add(relationship.fromComponentKey);
    }
    for (OI_DiscoveredComponent component : batch.components) {
      Object objectApiName = component.rawAttributes.get('objectApiName');
      if (objectApiName == null) {
        System.assert(
          !keysWithAnEdge.contains(component.componentKey),
          'An Approval Process with no resolved object must have no APPLIES_TO edge: ' +
          component.fullyQualifiedName
        );
      }
    }
  }

  /** Every component's namespace is reported as null — see the scanner's own Limitations on why this platform never guesses a namespace ProcessDefinition does not expose. */
  @isTest
  static void testEveryComponentReportsNullNamespace() {
    OI_DiscoveryBatch batch = new OI_ApprovalProcessScanner()
      .scan(new OI_ScanContext(null, 200, null, 'SOQL'));

    for (OI_DiscoveredComponent component : batch.components) {
      System.assertEquals(null, component.namespace);
    }
  }

  @isTest
  static void testComponentIdentityIsDeterministicAcrossRepeatedScans() {
    OI_ApprovalProcessScanner scanner = new OI_ApprovalProcessScanner();
    OI_DiscoveryBatch first = scanner.scan(
      new OI_ScanContext(null, 200, null, 'SOQL')
    );
    OI_DiscoveryBatch second = scanner.scan(
      new OI_ScanContext(null, 200, null, 'SOQL')
    );

    Map<String, String> checksumByKey = new Map<String, String>();
    for (OI_DiscoveredComponent component : first.components) {
      checksumByKey.put(component.componentKey, component.rawChecksum);
    }
    for (OI_DiscoveredComponent component : second.components) {
      System.assert(
        checksumByKey.containsKey(component.componentKey),
        'A repeated scan must produce identical componentKeys — an unstable key would create a duplicate node every scan.'
      );
      System.assertEquals(
        checksumByKey.get(component.componentKey),
        component.rawChecksum,
        'An unchanged Approval Process must produce an identical checksum, or every scan would spuriously version it.'
      );
    }
  }
}
