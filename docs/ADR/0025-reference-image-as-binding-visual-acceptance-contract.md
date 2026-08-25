# ADR-0025: Reference Image Is the Binding Visual Contract for Object Analyze Mode

## Status

Accepted

## Context

The project documents previously described capabilities and broad visual principles but did not define measurable geometry or require screenshot comparison. This allowed implementations to satisfy “SLDS,” “directional lanes,” and “Intelligence Panel” while remaining visibly different from the product owner’s approved reference. The existing radial and lane-layout ADRs decide topology and responsibility, not exact visual composition.

## Decision

Adopt `VisualDesignSpecification.md` as the authoritative visual contract for Object Analyze mode. Preserve ADR-0023’s directional lane model, but judge its presentation against the supplied reference image. Pixel-level fidelity applies to the application-owned workspace; Salesforce-owned global chrome is explicitly excluded because packaged LWCs cannot control it.

Visual acceptance requires a same-viewport real-org screenshot and overlay/perceptual comparison. Unit tests, DOM assertions, and source review are necessary but insufficient.

Base Lightning components remain preferred where their public styling surface can achieve the contract. Custom semantic HTML/CSS is permitted where a base component’s shadow boundary prevents the required appearance, provided SLDS tokens, accessibility, security, and package compatibility are preserved.

## Consequences

- Agents no longer have discretion to reinterpret the reference as a loose inspiration.
- Visual fidelity becomes objectively reviewable instead of a subjective “polish” task.
- Exact Salesforce global-header reproduction remains out of scope and must not be represented as achievable by an LWC.
- A current-app screenshot becomes required evidence for gap analysis.
- Some future implementation work may require CSS/template changes, but this ADR authorizes no code change by itself.

## Related

`VisualDesignSpecification.md`; `GraphUI.md`; ADR-0019; ADR-0020; ADR-0023; `ProductSpecs.md`; `CodingStandards.md`.
