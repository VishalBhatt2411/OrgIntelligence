/**
 * Purpose: Pure graph algorithms over an already-bounded OI_GraphFragment — BFS hop
 *          distances and DFS cycle detection. Extracted from OI_DependencyEngineService
 *          (behavior-preserving, ADR-0026 Phase 3) so Automation Health and Code Health can
 *          reuse the exact same cycle-detection logic Impact Analysis already relies on,
 *          instead of a second, drifting copy.
 * Responsibilities: Two pure functions, both over a caller-supplied, already-bounded
 *                    fragment — neither issues a SOQL query or knows what a "dependency" is;
 *                    that definition stays with each caller.
 * Dependencies: OI_GraphFragment, OI_NodeSummary, OI_EdgeSummary.
 * Limitations: Cheap only because callers are expected to bound the fragment first (a small
 *              node/edge set) — this class does no bounding of its own.
 */
public inherited sharing class OI_GraphCycleDetector {
  /** BFS over the fragment's own edges (never a new SOQL round-trip) — hop distance from the root, in the given direction. */
  public static Map<String, Integer> computeHopDistances(
    String rootKey,
    OI_GraphFragment subgraph,
    Boolean isForward
  ) {
    Map<String, List<String>> adjacency = buildAdjacency(subgraph, isForward);
    Map<String, Integer> distanceByKey = new Map<String, Integer>{
      rootKey => 0
    };
    List<String> frontier = new List<String>{ rootKey };
    Integer hop = 0;
    while (!frontier.isEmpty()) {
      hop++;
      List<String> nextFrontier = new List<String>();
      for (String key : frontier) {
        List<String> neighbors = adjacency.get(key);
        if (neighbors == null) {
          continue;
        }
        for (String neighbor : neighbors) {
          if (!distanceByKey.containsKey(neighbor)) {
            distanceByKey.put(neighbor, hop);
            nextFrontier.add(neighbor);
          }
        }
      }
      frontier = nextFrontier;
    }
    return distanceByKey;
  }

  /**
   * Classic DFS white/gray/black cycle detection over the fragment — cheap even though it's
   * DFS, since the caller is expected to have already bounded the node/edge set. Every node
   * on a back-edge's cycle is marked, not just the two endpoints of the closing edge.
   */
  public static Set<String> detectCycleParticipants(
    OI_GraphFragment subgraph,
    Boolean isForward
  ) {
    Map<String, List<String>> adjacency = buildAdjacency(subgraph, isForward);
    Map<String, Integer> color = new Map<String, Integer>();
    Set<String> cyclicKeys = new Set<String>();
    for (String startKey : adjacency.keySet()) {
      if (color.get(startKey) == null) {
        dfsDetectCycle(
          startKey,
          adjacency,
          color,
          new List<String>(),
          cyclicKeys
        );
      }
    }
    return cyclicKeys;
  }

  private static void dfsDetectCycle(
    String key,
    Map<String, List<String>> adjacency,
    Map<String, Integer> color,
    List<String> stack,
    Set<String> cyclicKeys
  ) {
    color.put(key, 1);
    stack.add(key);
    List<String> neighbors = adjacency.get(key);
    if (neighbors != null) {
      for (String neighbor : neighbors) {
        Integer neighborColor = color.get(neighbor);
        if (neighborColor == null) {
          dfsDetectCycle(neighbor, adjacency, color, stack, cyclicKeys);
        } else if (neighborColor == 1) {
          Boolean onCycle = false;
          for (String stackKey : stack) {
            if (stackKey == neighbor) {
              onCycle = true;
            }
            if (onCycle) {
              cyclicKeys.add(stackKey);
            }
          }
        }
      }
    }
    stack.remove(stack.size() - 1);
    color.put(key, 2);
  }

  private static Map<String, List<String>> buildAdjacency(
    OI_GraphFragment subgraph,
    Boolean isForward
  ) {
    Map<String, List<String>> adjacency = new Map<String, List<String>>();
    for (OI_NodeSummary summary : subgraph.nodes) {
      adjacency.put(summary.nodeKey, new List<String>());
    }
    for (OI_EdgeSummary edge : subgraph.edges) {
      String fromKey = isForward ? edge.sourceNodeKey : edge.targetNodeKey;
      String toKey = isForward ? edge.targetNodeKey : edge.sourceNodeKey;
      if (adjacency.containsKey(fromKey)) {
        adjacency.get(fromKey).add(toKey);
      }
    }
    return adjacency;
  }
}
