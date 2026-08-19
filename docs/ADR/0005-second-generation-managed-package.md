# ADR-0005: Second-Generation Managed Package for AppExchange Distribution

## Status
Accepted

## Context
The platform is explicitly a commercial AppExchange product (`CLAUDE.md`: "not a demo project... commercial-grade Salesforce application distributed through AppExchange"). Salesforce offers two packaging models suited to this: Unlocked Packages and Second-Generation (2GP) Managed Packages. The choice affects IP protection, upgrade behavior, and Security Review expectations.

## Decision
Target a **2GP Managed Package** as the distribution vehicle, with a registered namespace and package ancestry maintained across every version intended for promotion.

## Consequences
- **Positive**: Apex source is protected (subscribers cannot view/modify managed package Apex), which matters for a paid commercial product's IP.
- **Positive**: managed packaging gives a well-defined, Salesforce-supported upgrade path (push upgrades, ancestry-tracked versioning) that AppExchange listing and enterprise customers expect.
- **Positive**: namespace injection at build time is exactly what forces the "no hardcoded IDs, no cross-object hardcoded field literals for our own objects" discipline (Architecture §15) to actually be validated pre-release, rather than discovered post-install.
- **Negative**: managed packages carry stricter Security Review scrutiny and less customer-side customizability of packaged components than Unlocked — accepted as inherent to the IP-protection trade-off, and appropriate for a commercial listing rather than an internal/open-source tool.
- **Negative**: namespace must be reserved and locked in early; changing it later is disruptive — mitigated by developing without a namespace initially (current `sfdx-project.json` has `namespace: ""`) and only binding the namespace once ready to cut the first packaged version.

## Alternatives Considered
- **Unlocked Package** — rejected for the GA product: source isn't protected, which is a poor fit for a paid commercial listing; better suited to internal tooling or open-source distribution, neither of which describes this product's stated goal.
- **Unmanaged / metadata-only distribution** — rejected: no upgrade path, no IP protection, not a realistic AppExchange listing model for a maintained commercial product.

## Related
Architecture.md §15; Roadmap.md Phase 5–6.
