# MASTER IMPLEMENTATION DIRECTIVE

> **Visual authority:** For Object Analyze mode, [VisualDesignSpecification.md](VisualDesignSpecification.md) and [ADR-0025](ADR/0025-reference-image-as-binding-visual-acceptance-contract.md) are the binding visual acceptance contract. “Use SLDS” does not authorize a visually approximate substitute. Functional, security, data, performance, and packaging requirements in this document remain controlling.

You are working inside the existing **Salesforce Org Intelligence Platform** repository.

This is NOT a greenfield project.

The current repository already contains a substantial, validated implementation.

Your role is now:

**Senior Salesforce Product Engineer + Technical Architect responsible for completing the product against the approved Master Product Specification without destroying working architecture.**

---

# CURRENT VERIFIED BASELINE

The project currently reports:

* Salesforce DX managed-package-oriented project
* API 67.0
* deployed to `entTrial`
* 304 Apex tests passing
* 209 Jest tests passing

Existing major capabilities include:

* Graph Engine
* Graph Repository
* graph persistence
* metadata scanning
* graph traversal
* impact traversal
* Graph Explorer
* search
* minimap
* breadcrumbs
* filters
* virtualization
* hub clustering
* pan / zoom / drag foundations
* Object scanner
* Field scanner
* Apex Class scanner
* Apex Trigger scanner
* Flow scanner
* Permission Set scanner
* Multi-Hierarchy Accelerator MVP

Do not assume this status report is perfectly accurate.

Verify the repository.

---

# PRIMARY INSTRUCTION

Read and treat the approved:

**Salesforce Org Intelligence Platform — Master Product Specification**

as the product source of truth.

Also read:

* CLAUDE.md
* Architecture.md
* GraphEngine.md
* GraphUI.md
* MetadataScanner.md
* SearchEngine.md
* DataModel.md
* API.md
* Backlog.md
* Roadmap.md
* ADRs
* Multi-Hierarchy FRD

Do not redesign the product.

Do not interpret vague requirements independently.

Implement against the specification.

---

# PHASE 0 — FULL REPOSITORY AUDIT

Before modifying any source:

Inspect the complete repository.

Build an implementation matrix:

| Requirement | Implemented | Partial | Missing | Broken | Validation |
| ----------- | ----------- | ------- | ------- | ------ | ---------- |

Audit specifically:

## Explorer

* analysis selector
* Object selection
* Field selection
* Record selection
* graph layout
* pan
* zoom
* node drag
* expand
* collapse
* fit
* center
* reset
* minimap
* breadcrumbs
* filters
* node cards
* side panel

## Backend

* Graph Engine
* Graph Traversal
* Graph Repository
* Search
* Impact
* scanners
* dependency edges
* caching

## Org Health

Determine exactly what currently exists.

## Multi-Hierarchy

Verify existing FRD functionality.

## Package

* permission sets
* tabs
* applications
* FlexiPages
* Custom Metadata
* configuration
* install/deploy assumptions

Do NOT write code during the audit.

---

# PHASE 1 — STABILIZE THE EXPLORER

This is the highest priority.

Do not proceed to Org Health until the Explorer is genuinely usable.

---

# 1. PAN / ZOOM ARCHITECTURE

Inspect existing transform/event handling.

The graph viewport must have a coherent transform model:

translate(panX, panY) scale(zoom)

Separate:

* canvas pan state
* zoom state
* node-position state

Do not patch individual handlers if the architecture is fundamentally wrong.

---

# 2. CANVAS PAN

Required behavior:

Pointer down on empty canvas
→ pointer move
→ entire graph moves.

Node drag must NOT trigger pan.

Use pointer capture where appropriate.

Test:

* mouse
* rapid drag
* start/stop
* leaving SVG bounds
* released pointer

---

# 3. ZOOM

Implement / verify:

* mouse wheel
* trackpad
* *
* *
* fit
* reset
* center

Respect min/max zoom.

Wheel zoom should preserve sensible focus.

The displayed zoom percentage must always match actual transform state.

---

# 4. NODE DRAG

Dragging a node:

* moves only node
* updates edges live
* preserves viewport
* preserves selected state
* does not pan canvas

Manual node coordinates should remain during the current graph session.

---

# 5. OBJECT ANALYSIS FLOW

Object mode must be intentional.

User:

Object
→ Select Object
→ Analyze

Do not rely on generic search alone.

Selected Object becomes the focus.

Load the appropriate bounded hierarchy.

Show:

* fields
* referenced Objects
* referencing Objects
* triggers
* Flows
* Apex references
* Permission Set relationships

Only where real graph data supports them.

---

# 6. FIELD ANALYSIS FLOW

Field mode MUST require Object selection.

User:

Field
→ Object
→ Field
→ Analyze

Field picker must be scoped to selected Object.

Graph must focus selected Field.

Show:

* owning Object
* relationship target
* relationship type
* dependencies
* impact

according to actual coverage.

---

# 7. RECORD ANALYSIS

Record mode MUST NOT remain disabled.

Implement a bounded live-query architecture.

Do NOT persist full record populations into metadata graph storage.

User:

Record
→ Object
→ Search Record
→ Analyze

Implement:

* record search
* record summary
* parent lookup traversal
* Master-Detail traversal
* child relationship discovery
* child counts
* bounded expansion
* pagination

Security:

* USER_MODE where appropriate
* CRUD
* FLS
* sharing

Unknown/inaccessible records must not leak.

---

# PHASE 2 — REDESIGN INTELLIGENCE PANEL

The current side panel must become a structured intelligence panel.

Do not render an unorganized property dump.

---

# OBJECT PANEL

Implement these sections where data exists.

## Overview

* Label
* API Name
* Standard/Custom
* Namespace
* type

## Data

* Record Count
* other safe real-data metrics

## Fields

* Total
* Standard
* Custom
* Relationship

## Relationships

* Incoming Lookup
* Outgoing Lookup
* Incoming Master Detail
* Outgoing Master Detail
* Referencing Objects
* Referenced Objects

## Automation

* Trigger count
* Flow count

## Code

* Apex dependency count

## Security

* Permission Set dependency count

## Impact

* Direct
* Indirect
* cycle status
* depth
* analysis coverage

---

# FIELD PANEL

Implement:

## Overview

* Label
* API Name
* Object
* Data Type
* Standard/Custom
* Namespace

## Relationship

* type
* target
* relationship name

## Dependencies

Group by currently scanned metadata type.

## Impact

Show direct / indirect effects plus coverage statement.

---

# RECORD PANEL

Implement:

* Record Name
* Record Id
* Object
* Owner where accessible
* Created
* Modified
* Parent relations
* child relationship counts

Do not confuse record relationships with metadata dependencies.

---

# PHASE 3 — DEPENDENCY COVERAGE

The existing project reports these scanners:

* Object
* Field
* Apex Class
* Apex Trigger
* Flow
* Permission Set

Preserve them.

Verify every generated edge.

---

# TOOLING API

The current status reports:

`OI_ToolingApiAdapter` does not exist.

Do not build it blindly.

First list exactly which missing dependency requirements require Tooling API.

Then design ONE package-safe adapter.

Requirements:

* Named Credential / secure endpoint strategy
* no hardcoded org URL
* testable abstraction
* callout limits
* retry/error handling
* security review readiness

Implement only if required to close actual dependency gaps.

---

# FIELD IMPACT PRIORITY

Field dependency analysis is currently incomplete.

Prioritize coverage necessary to answer:

> What breaks if I change this Field?

Target relationships:

* Apex → Field
* Trigger → Field
* Flow → Field
* Validation Rule → Field
* Formula → Field
* FieldPermissions → Field
* Reports → Field

For every scanner/adapter:

* produce real graph edges
* prevent dangling endpoints
* test edge correctness
* document exact/heuristic confidence

---

# DEPENDENCY CONFIDENCE

Relationships must carry or derive confidence classification.

Examples:

* Exact
* Parsed
* Heuristic

The UI should not present heuristic Apex reference detection with the same certainty as an exact trigger-object relationship.

---

# PHASE 4 — ORG HEALTH

Only begin once Explorer + Intelligence Panel are stable.

Add a real Lightning App navigation item:

**Org Health**

---

# ORG HEALTH DATA MODEL

Prefer deriving insights from:

* current graph
* scan metadata
* Salesforce limits
* bounded live queries

Do not introduce unnecessary persistent analytics objects unless justified.

---

# DASHBOARD SECTIONS

## Org Overview

Show:

* Objects
* Fields
* Apex
* Triggers
* Flows
* Permission Sets
* dependencies
* relationships

---

## Metadata Health

Calculate real insights:

* high-field-count Objects
* high-degree Objects
* orphan / low-connectivity metadata
* potential unused Fields
* dependency density

Always expose analysis coverage.

---

## Automation Health

Show:

* automation per Object
* high fan-in/fan-out
* cycles
* high-impact components

---

## Code Health

Use measurable facts.

Examples:

* Apex count
* trigger count
* test coverage
* dependency fan-in/out
* cycles
* old API versions where accessible

Any score must expose formula.

---

## Security Health

Build only evidence-based checks.

Examples:

* broad Object grants
* sensitive metadata with broad grants
* Permission Set coverage
* elevated permissions

No fake score.

---

## Data Health

Implement bounded, configurable analysis.

Potential indicators:

* Record Count
* stale records
* null density
* data completeness
* high-volume Objects

Never run unbounded full-org data profiling synchronously.

---

## Storage

Show real Salesforce limits:

* Data Used
* Data Remaining
* File Used
* File Remaining

If some desired metric is not actually obtainable, state it.

---

# PHASE 5 — MULTI-HIERARCHY VALIDATION

Do not rebuild the Hierarchy Accelerator.

Audit it against the FRD.

Verify:

* Hierarchy Definitions
* Levels
* multiple memberships
* multiple parents
* interactive tree
* switcher
* search
* ancestors
* descendants
* path
* history
* effective dating
* record page integration
* permissions
* reporting

The FRD explicitly requires interactive visualization, hierarchy switching, ancestor/descendant navigation, path display, security, and reusable Lightning components. Preserve these behaviors.
Do not mix Hierarchy Relationship data into metadata Graph Nodes.

---

# PHASE 6 — UI PRODUCT POLISH

Once functionality is correct:

Improve:

* spacing
* visual hierarchy
* typography
* panel grouping
* empty states
* loading states
* error states
* selection states
* controls
* graph readability

Use SLDS.

For Object Analyze mode, use SLDS tokens and accessible patterns while matching the approved reference. A Lightning base component is not mandatory when its shadow-DOM styling boundary prevents the specified appearance; custom semantic markup/CSS is allowed under `VisualDesignSpecification.md` and Coding Standards. Visual validation requires a same-viewport real-org screenshot comparison, not source inspection alone.

Do not use cosmetic improvements as substitutes for broken interactions.

---

# LIGHTNING APP

Verify application navigation contains:

* Explorer
* Org Health
* Multi-Hierarchy
* Scan Management
* Settings

A user must not require manually entering URLs.

Verify:

* tabs
* FlexiPages
* app visibility
* Permission Sets
* navigation ordering

against `entTrial`.

---

# REAL-ORG VALIDATION

After each major implementation group:

Deploy to:

`entTrial`

Use real Salesforce metadata/data.

Do not rely only on mocks.

---

# EXPLORER TEST SCENARIOS

## Object

Use at least one real standard Object and one custom Object.

Validate:

* hierarchy
* fields
* relationships
* Apex
* Flow
* Trigger
* Permission Sets
* impact

---

## Field

Object → Field

Validate:

* parent
* target
* dependencies
* impact

Use both:

* relationship Field
* normal Field

---

## Record

Object → real Record

Validate:

* search
* selection
* parent
* children
* record detail

---

# GRAPH INTERACTION TEST

Manual browser validation must explicitly cover:

* canvas pan
* wheel zoom
* button zoom
* fit
* reset
* center
* node drag
* expand
* collapse
* minimap
* filter
* breadcrumb

Do not mark these complete based solely on Jest.

---

# ORG HEALTH VALIDATION

For every displayed number:

state its source.

One of:

* Scan-derived
* Live Salesforce
* Calculated heuristic

Validate several metrics manually against Salesforce Setup/SOQL.

---

# TEST REQUIREMENTS

Maintain or improve the current baseline.

Run:

* all Apex tests
* all Jest tests
* architecture lint
* deployment validation

Never delete tests just to pass.

Never weaken assertions around broken behavior.

---

# CHANGE CONTROL

Do NOT:

* rewrite Graph Engine unnecessarily
* redesign the data model unnecessarily
* replace real functionality with mock data
* implement unrelated roadmap features
* create a parallel UI architecture
* rename major components without reason
* silently change public contracts

If architecture must change:

document:

1. problem
2. existing design limitation
3. proposed change
4. migration impact
5. tests required

---

# EXECUTION ORDER

Execute in this exact order:

1. Repository audit
2. Explorer interaction fixes
3. Object flow
4. Field flow
5. Record flow
6. Intelligence Panel
7. Dependency coverage
8. Impact completeness
9. Org Health
10. Multi-Hierarchy FRD audit
11. Lightning navigation integration
12. Browser validation
13. Final regression testing
14. Deployment readiness

Do not skip forward because a later feature is more interesting.

---

# REPORTING FORMAT

After each execution phase, provide ONLY:

## Completed

## Real-org validation

## Tests

## Remaining blockers

## Next phase

Do not repeat the entire project history after every task.

---

# FINAL COMPLETION REPORT

When all approved scope is complete, report:

## Explorer

* Object
* Field
* Record

## Graph Interactions

* pan
* zoom
* drag
* expand/collapse
* layout
* minimap
* filters
* breadcrumb

## Dependencies

Coverage matrix by metadata type.

## Impact

Coverage matrix and known gaps.

## Intelligence Panel

Object / Field / Record metrics.

## Org Health

Every metric and source.

## Multi-Hierarchy

FRD requirement matrix.

## Security

Verified behavior.

## Performance

Real-org measurements.

## Tests

Exact Apex/Jest results.

## Deployment

Exact target and result.

## Remaining limitations

No vague statements.

---

# NON-NEGOTIABLE PRODUCT RULE

Always return to this question when deciding whether work belongs in scope:

> Does this help a Salesforce user understand the hierarchy, relationship, dependency, impact, health, or business hierarchy of their org?

If not, do not build it unless explicitly requested.

Start now with the **repository audit only**.

Do not modify code until you have produced the requirement-to-implementation matrix.
