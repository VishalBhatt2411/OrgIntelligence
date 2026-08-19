# ADR-0003: Layered Architecture with Service/Selector/Repository/Adapter Separation

## Status
Accepted

## Context
`CLAUDE.md` mandates SOLID, Clean Architecture, single responsibility, and low coupling, and explicitly forbids monolithic classes and business logic in Controllers/Triggers/LWCs. Apex has no package-level namespacing for physical folder organization, and the codebase must remain maintainable and testable as it grows to ~15 metadata scanners, four engines, and a full UI shell, while also staying package-ready (namespace-injectable, no hardcoded org assumptions).

## Decision
Adopt a strict layered architecture — Presentation → Controller → Service → Domain/Data Access → Integration → Platform Infrastructure (Architecture §2) — with dependency direction always inward, enforced by naming convention (§CodingStandards §1) and reviewed at PR time (§CodingStandards §2). Services depend on Selector/Repository/Adapter *interfaces* conceptually (constructor/setter injection of concrete implementations), enabling tests to substitute fakes without touching real SOQL or real callouts.

## Consequences
- **Positive**: each class has one reason to change (a Selector changes only if a query shape changes; a Service changes only if a business rule changes) — directly satisfies SRP/OCP.
- **Positive**: Services are unit-testable in isolation with fake dependencies, which is what makes the Testing Strategy's "no test may assume org metadata exists" rule (Architecture §16) practical rather than aspirational.
- **Positive**: new engines (e.g., a future Search backend swap, ADR-0007) can be introduced behind an existing Service's public interface without touching Controllers or LWCs.
- **Negative**: more classes and more indirection than a "just write it in the Controller" approach — accepted, since `CLAUDE.md` explicitly prioritizes maintainability/extensibility over minimizing class count, and Core Principles explicitly warn against complexity for its own sake but not against justified layering.

## Alternatives Considered
- **Thick Controllers, no Service layer** — rejected: directly violates `CLAUDE.md` §Service Layer Rules ("LWCs should never contain business logic... Controllers should remain thin") and would make unit testing without a live org nearly impossible.
- **Physical folder-per-module Apex organization** — not possible; Salesforce stores all Apex classes in one flat `classes` folder regardless of source structure, so logical separation is necessarily convention-based (Architecture §3).

## Related
Architecture.md §2, §3, §4; CodingStandards.md §1–§2; [ADR-0013](0013-graphengine-facade.md) (applies this same service-boundary rule one level deeper, inside the Graph Engine's own internal components).
