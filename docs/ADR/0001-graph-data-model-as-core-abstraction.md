# ADR-0001: Graph Data Model as the Core Abstraction

## Status
Accepted — the "small closed set of `NodeType`/`EdgeType` values" phrasing below is **amended by [ADR-0011](0011-generic-node-edge-typing-via-domain-registry.md)**: types are opaque strings resolved via an externalized Domain Type Registry, not a closed enum in the engine. Separately, **[ADR-0014](0014-immutable-node-edge-versioning.md) elaborates** how a node/edge persists once written (immutable, versioned) — this record's "model every entity as a Node/Edge" decision stands unchanged by that. Everything else in this record stands.

## Context
The product's purpose is to help administrators and architects understand how Salesforce metadata entities relate to each other — objects, fields, Apex, Flows, permissions, dashboards, and the dependencies between them. A purely relational/tabular model (one custom object per metadata type, with lookup fields for relationships) is the "obvious" Salesforce-native approach, but relationships between metadata entities are heterogeneous, many-to-many, cross-type, and the interesting questions ("what breaks if I change this field") are inherently traversal questions, not row-filter questions.

## Decision
Model every scanned metadata entity as a **Node** and every relationship as an **Edge**, with a small closed set of `NodeType`/`EdgeType` values (Architecture §5). The Graph Engine is the only component permitted to construct nodes/edges; all other engines (Dependency, Search) and all UI consume the graph, never build it.

## Consequences
- **Positive**: a single, uniform model serves browsing, search, and impact analysis without a special case per metadata type; adding a new metadata type means adding a new `NodeType`/scanner, not a new relational schema and a new set of joins.
- **Positive**: the UI's "graph is primary, tables are secondary" design (`CLAUDE.md` §UI Philosophy) maps directly onto the storage model — no translation layer between how data is stored and how it's browsed.
- **Negative**: traversal (BFS/DFS for expansion and impact analysis) must be implemented in Apex rather than expressed as SOQL joins, since SOQL cannot do recursive/variable-depth traversal — accepted cost, addressed by keeping traversal server-side and depth-bounded (Architecture §5, §7).
- **Negative**: node/edge attributes are semi-structured (`Attributes_Json__c`) rather than fully typed columns, since node shape varies by type — accepted trade of some queryability for schema flexibility across ~15 heterogeneous node types.

## Alternatives Considered
- **One custom object per metadata type with standard Lookups for relationships** — rejected: relationships are inherently cross-type (an edge can connect any two node types), which standard Lookup fields (single-target-object) can't express generically; would require a lookup field per possible relationship pair, an unbounded and unmaintainable schema.
- **Fully typed node schema (a column per possible attribute)** — rejected: attribute sets vary too widely across 15+ node types; would produce an extremely wide, mostly-null object.

## Related
Architecture.md §5, §9; ADR-0002 (persistence), ADR-0011 (amendment), DataModel.md §2.3–2.4; GraphEngine.md.
