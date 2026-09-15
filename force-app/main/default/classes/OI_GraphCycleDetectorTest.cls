@IsTest
private class OI_GraphCycleDetectorTest {
  @IsTest
  static void testComputeHopDistancesReturnsBfsDistanceFromRoot() {
    OI_GraphFragment fragment = buildFragment(
      new List<String>{ 'a', 'b', 'c', 'd' },
      new List<List<String>>{
        new List<String>{ 'a', 'b' },
        new List<String>{ 'b', 'c' },
        new List<String>{ 'a', 'd' }
      }
    );

    Map<String, Integer> distances = OI_GraphCycleDetector.computeHopDistances(
      'a',
      fragment,
      true
    );

    System.assertEquals(0, distances.get('a'));
    System.assertEquals(1, distances.get('b'));
    System.assertEquals(1, distances.get('d'));
    System.assertEquals(2, distances.get('c'));
  }

  @IsTest
  static void testDetectCycleParticipantsFindsEveryNodeOnACycle() {
    OI_GraphFragment fragment = buildFragment(
      new List<String>{ 'a', 'b', 'c', 'd' },
      new List<List<String>>{
        new List<String>{ 'a', 'b' },
        new List<String>{ 'b', 'c' },
        new List<String>{ 'c', 'a' },
        new List<String>{ 'a', 'd' }
      }
    );

    Set<String> cyclic = OI_GraphCycleDetector.detectCycleParticipants(
      fragment,
      true
    );

    System.assert(cyclic.contains('a'));
    System.assert(cyclic.contains('b'));
    System.assert(cyclic.contains('c'));
    System.assert(!cyclic.contains('d'));
  }

  @IsTest
  static void testDetectCycleParticipantsReturnsEmptySetForAcyclicGraph() {
    OI_GraphFragment fragment = buildFragment(
      new List<String>{ 'a', 'b', 'c' },
      new List<List<String>>{
        new List<String>{ 'a', 'b' },
        new List<String>{ 'b', 'c' }
      }
    );

    Set<String> cyclic = OI_GraphCycleDetector.detectCycleParticipants(
      fragment,
      true
    );

    System.assert(cyclic.isEmpty());
  }

  private static OI_GraphFragment buildFragment(
    List<String> nodeKeys,
    List<List<String>> edgePairs
  ) {
    List<OI_NodeSummary> nodes = new List<OI_NodeSummary>();
    for (String nodeKey : nodeKeys) {
      nodes.add(
        new OI_NodeSummary(nodeKey, 'Test.Type', nodeKey, nodeKey, 'Active')
      );
    }
    List<OI_EdgeSummary> edges = new List<OI_EdgeSummary>();
    for (List<String> pair : edgePairs) {
      edges.add(
        new OI_EdgeSummary(
          pair[0] + '::' + pair[1],
          'Test.EDGE',
          pair[0],
          pair[1]
        )
      );
    }
    return new OI_GraphFragment(
      nodeKeys[0],
      nodes,
      edges,
      new List<String>(),
      false,
      null
    );
  }
}
