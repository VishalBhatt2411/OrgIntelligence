# ADR-0031: Scan Scope Policy and Storage-Light Graph Persistence

## Status

Accepted.

## Context

Each persisted graph node or edge is a Custom Object row, and a row costs about 2 KB of data storage whatever it holds. Before this ADR the metadata scan persisted:

- every queryable, non-structural SObject in the org. That is several hundred standard and setup objects, most of which the org never customised.
- every field on every one of those objects, each with a `HAS_FIELD` edge.

In the Developer Edition development org (5 MB of data storage) the CustomObject task alone wrote 968 nodes. The CustomField task then failed with `STORAGE_LIMIT_EXCEEDED`, leaving the org at about 7.3 MB of 5 MB. Scaled to a real subscriber org, the same approach would use a large share of the customer's storage for the package's own bookkeeping. That is an AppExchange good-citizenship problem (ADR-0002, DataModel.md §7).

Most of those rows add no graph structure. A plain text or number field has no edges beyond `HAS_FIELD`. An uncustomised standard object only adds noise to the map. The field browser in the detail panel was the only consumer of the plain-field rows, and live Schema Describe can serve it just as well.

Superseded versions (ADR-0014) also stayed in the Custom Objects indefinitely, because `archiveSupersededVersions` was only a documented seam.

## Decision

### 1. A scan scope policy, shared by every scanner

`OI_ObjectScopeFilter` stays the single place that decides object scope. After the unchanged structural exclusions (`__mdt`, `__e`, `__b`, `__x`, History/Share/Feed/ChangeEvent), it applies these rules in order:

1. An `OI_Scan_Object_Scope__mdt` record with `Enabled__c = false` always excludes the object.
2. An `OI_Scan_Object_Scope__mdt` record with `Enabled__c = true` always includes the object. The package ships 20 records for the core CRM objects: Account, Contact, Lead, Opportunity, Case, Task, Event, User and others.
3. A custom object from the org's own namespace, or with no namespace, is included. A custom object from another namespace (an installed managed package) is included only when `OI_Settings__mdt.Scan_Managed_Package_Objects__c` is checked. It is off by default.
4. A standard object is included when `Scan_Customized_Standard_Objects__c` is checked (on by default) and the object has at least one custom field from an in-scope namespace.
5. Everything else is out of scope.

The same managed-package rule covers code components. `OI_ObjectScopeFilter.isNamespaceInScope` checks an Apex class's, trigger's or flow's `NamespacePrefix`, and the Apex class, Apex trigger and Flow scanners skip other namespaces unless `Scan_Managed_Package_Objects__c` is checked. Managed code bodies are hidden, so those nodes would add storage cost but no dependency edges. In the development org this removes 823 of 1,182 Apex nodes (the FSL, thsecurity and sf_fieldservice packages).

Code and security components go through `OI_ObjectScopeFilter.isComponentInScope(namespacePrefix, name)`, which applies the managed-package rule above and two more rules.

**The app never maps itself.** Its own objects, fields, Apex classes, triggers, flows and permission sets are always out of scope, even when managed packages are switched on. When the app is installed as a package, the package namespace (read from the filter class's own runtime type name) identifies its components. When it is deployed un-namespaced, as in development, the `OI_` prefix that every app component carries identifies them. The prefix is detected, not a setting, because a shipped prefix setting could silently exclude a customer's own `OI_`-named components. The prefix rule applies only to un-namespaced deployments, and only there could it collide with customer components. In the development org this removes 301 of 302 Apex class nodes and the app's own permission sets and objects.

**Permission sets follow the standard-object rule.** `OI_PermissionSetScanner` skips:

- rows with `Type = 'Group'`, the synthetic shadows of Permission Set Groups, excluded for the same reason as profile-owned sets;
- Salesforce-supplied sets (`IsCustom = false`), unless the new `Scan_Standard_Permission_Sets__c` setting is checked (off by default);
- managed-package and app-owned sets, through `isComponentInScope`.

Apex-class grant edges target only in-scope classes, so no edge dangles. In the development org this removes about 90 of 108 permission-set nodes and most `GRANTS_ACCESS_TO` edges.

"Local" namespace means the org's own namespace (`Organization.NamespacePrefix`, one query per transaction). It is not the package's namespace. In a subscriber org the two differ, and only the org's own components belong to the customer. An earlier version of this ADR derived the local namespace from the class name, which would have treated the app's packaged namespace as the customer's.

The Tech Debt engine (`OI_TD_ScanEngine`) applies the same self-exclusion but keeps its own managed-package rules, so it calls the ownership-only checks `isAppComponent`, `isAppLightningComponent` and `isAppApiName` when it collects objects, classes, triggers, flows, Lightning bundles, Visualforce pages and components, and non-profile permission sets. Un-namespaced, a Lightning bundle is recognised as the app's when its name is `oi` followed by an upper-case letter; seven app bundles without that prefix (for example `graphViewState`) are still scanned until they are renamed or the app is packaged.

Decisions are memoised per transaction, so every scanner in a hop gets the same answer.

If the settings record is missing, the scan falls back to the defaults and logs a warning; it does not fail.

### 2. Persist only relationship fields; serve the rest live

`OI_FieldScanner` persists a field only when all of these hold:

- it is a reference field (Lookup or Master-Detail);
- it belongs to an in-scope namespace;
- it has at least one in-scope target object.

Its attributes still record the full `referenceTo` list, but edges are created only to in-scope targets, so no edge ever points at a node that doesn't exist. Owner, CreatedBy and LastModifiedBy lookups are kept, because User is a shipped include.

`OI_ObjectScanner` now records `fieldCount` and `customFieldCount` attributes on each object node. It counts them from the Describe field map, with no per-field describe calls.

`OI_FieldSummaryService` (used by `OI_GraphController.getFieldSummaries`) builds the field browser from live Describe. It merges in the persisted field nodes, so those rows keep their `nodeKey` and stay clickable. Rows that come only from Describe are shown but are not navigable. Persisted fields that Describe no longer returns are still listed until the next scan retires them.

Org Health reads the new attributes:

- **Metadata Health.** The custom-field penalty uses `customFieldCount`. It falls back to counting persisted field nodes for objects scanned before this ADR.
- **Org Overview.** The Fields KPI is the sum of `fieldCount`. If any object lacks the attribute, it falls back to the field-node count.

### 3. Archive superseded versions to Big Objects (ADR-0002, implemented)

`OI_GraphArchivalBatch` runs after every completed scan. It is launched best-effort from `OI_ScanOrchestratorQueueable.completeRun`, and only one chain runs at a time.

The batch processes non-current rows whose `SystemModstamp` is older than `Graph_Version_Retention_Days__c` (default 1; 0 archives immediately). It runs four chained phases:

1. **Archive nodes.** `OI_GraphRepository.archiveSupersededVersions` writes the rows to `OI_Graph_Node_Archive__b` via `insertImmediate`.
2. **Purge nodes.** `OI_GraphRepository.purgeArchivedVersions` deletes the rows through `OI_CustomObjectStorageProvider.moveToArchive`.
3. **Archive edges.** The same archive step, for edge rows.
4. **Purge edges.** The same purge step, for edge rows.

The archive and purge steps are separate batch jobs because Big Object `insertImmediate` and sObject DML cannot share a transaction.

If a phase has any failed chunk, the chain stops before the next phase, so a version is never deleted without being archived first. Re-archiving is idempotent, because the Big Object index is the version key. Every read and delete re-checks `Is_Current__c = false`.

## Consequences

- **Positive.** Storage grows with the org's own customisation rather than with the platform's size. In the development org the scope drops from about 968 objects plus several thousand fields to about 51 objects and about 885 rows in total (≈1.8 MB).
- **Positive.** The field browser shows every field, including ones the old scan could never fit into storage.
- **Positive.** Version history no longer accumulates in data storage.
- **Negative.** Plain fields are no longer graph nodes. They cannot be search results, impact-analysis targets or canvas nodes. Phase 3 (field dependencies) must bring a field into the graph when a dependency references it, not rely on every field already being there.
- **Negative.** Uncustomised standard objects that aren't shipped includes are not on the map. An admin adds one with an `OI_Scan_Object_Scope__mdt` record.
- **Negative.** Deleted rows sit in the Recycle Bin, which counts toward storage for up to 15 days unless an admin empties it.
- **Negative.** Adding the count attributes changes every object node's checksum, so the first scan after upgrading writes a new version of every object. The archival batch then removes the old versions.
- **Neutral.** The Big Object archive is still write-only. Reading history back remains future work (GraphRepository.md §29 Q4).

## Alternatives Considered

- **Keep all fields, shrink each row.** Rejected. Storage is charged per row (about 2 KB) regardless of content, so smaller attribute payloads save nothing.
- **Store fields in Big Objects.** Rejected. Big Objects can't be queried synchronously the way the interactive graph needs, and the field browser doesn't need persistence at all.
- **Scope by an allow-list only.** Rejected. It would silently miss every customised standard object and every new custom object. The rule-based policy discovers these automatically, and override records handle the exceptions.

## Related

- [ADR-0002](0002-hybrid-custom-object-big-object-graph-persistence.md): hybrid persistence. This ADR implements its archival leg.
- [ADR-0014](0014-immutable-node-edge-versioning.md): immutable versioning, which is where superseded rows come from.
- [ADR-0026](0026-org-health-visual-contract-and-dashboard-architecture.md): the Org Health consumers.
- DataModel.md §7 (storage growth control), GraphRepository.md §9 (archival).
