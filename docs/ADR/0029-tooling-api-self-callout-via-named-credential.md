# ADR-0029: Tooling API Self-Callout Authenticated via a Packaged Named Credential (Not the Running User's Session)

## Status

Accepted — implemented and live-verified in `OI_ToolingApiAdapter` (backing `OI_ObjectSharingSettingsService`, the Object panel's Sharing Settings section).

## Context

`OI_ObjectScanner` has a documented gap: Apex Describe has no accessor for an object's Sharing Model (Org-Wide Default). The only way to read it is the Tooling API's `EntityDefinition.InternalSharingModel`/`ExternalSharingModel` fields, which requires an HTTP callout back to the org's own REST/Tooling API — this platform's first callout of any kind (Architecture.md's stated "no external services in v1" was written before this gap was discovered; a same-org self-callout is not an external service, but it is still a callout with real Security Review weight, per Backlog.md DE-15).

`OI_ToolingApiAdapter` was first built authenticating with the running user's own session (`UserInfo.getSessionId()`) rather than a Named Credential, specifically to keep this feature **zero-config**: no admin setup step, no Connected App, no OAuth — a callout back to the same org that issued the current session needs no Remote Site Setting, and (the reasoning went) elevates nothing beyond what that user could already see.

That reasoning was never live-tested against the actual invocation path before being written down, and it turned out to be wrong for this platform's real call shape.

## What Went Wrong

Every caller of `OI_ToolingApiAdapter` reaches it through `OI_GraphController`, an `@AuraEnabled` Apex controller invoked from the LWC (`oiNodeDetailPanel`) — never from Visualforce, never from the API directly. Live verification exposed a hard platform behavior:

- `sf apex run` (a CLI/API-scoped session) calling `OI_GraphController.getObjectSharingSettings('Account')` → **200, correct data**.
- The identical Apex, invoked through the real Lightning/Aura UI → **401 Unauthorized** on the exact same Tooling API callout.

Salesforce deliberately scopes down the session ID handed to the Lightning Component framework so it cannot be reused to authenticate arbitrary API/Tooling callouts — a CSRF-hardening measure preventing a compromised or malicious LWC from making out-of-band API calls using the page's own session. `UserInfo.getSessionId()` inside an `@AuraEnabled` method is exactly this scoped-down session. This is not a bug to fix in Apex; it's a platform boundary that makes the original design's premise false for every real caller this Adapter has.

## Decision

Replace session-based authentication with a **Named Credential** (`OI_Self_Callout`) backed by an **External Credential** (`OI_Self_Callout_Credential`, OAuth 2.0 Client Credentials flow) pointing at the same org's own token endpoint. `OI_ToolingApiAdapter.query()` now calls `callout:OI_Self_Callout/services/data/v67.0/tooling/query/?q=...` with no explicit `Authorization` header — the Named Credential injects it.

This trades away the "zero-config" property for a documented **one-time post-install admin setup**, explicitly accepted (user-confirmed 2026-09-21) as the only real fix, given that:

- A Visualforce-style session-based self-callout does not work from LWC/Aura at all.
- Any alternative that avoids OAuth setup (e.g., asking the org to relax session security policies) would be a far worse trade-off — weakening a platform CSRF protection org-wide to work around one feature is not acceptable.

### One-time setup performed in the target org (must be repeated by every installing admin until this is automated by packaging tooling)

1. **External Client App** (`OI Self Callout`): OAuth enabled, scope `Manage user data via APIs (api)`, **Client Credentials Flow** enabled at the app level.
2. On the app's **Policies → OAuth Policies**: enable Client Credentials Flow and set **Run As** to the identity the callout executes as (this identity's CRUD/FLS/sharing governs what the callout can see — see Security below).
3. Retrieve the app's **Consumer Key/Secret** (Settings tab → Consumer Key and Secret).
4. **External Credential** `OI_Self_Callout_Credential`: OAuth 2.0, Client Credentials with Client Secret flow, Identity Provider URL = the org's own `/services/oauth2/token` endpoint, **no `Scope` parameter** (the org's Client Credentials token endpoint rejects an explicit `scope` query parameter — `invalid_request: scope parameter not supported` — the scope is already fixed by the app's own OAuth Scopes configuration from step 1).
5. External Credential **Principal** (`OI_Self_Callout_Principal`, Named Principal): Client Id/Secret = the values from step 3.
6. **Named Credential** `OI_Self_Callout`: URL = the org's own My Domain URL, External Credential = `OI_Self_Callout_Credential`.
7. Grant the relevant permission set (`OI_Administrator`) **External Credential Principal Access** to `OI_Self_Callout_Credential` / `OI_Self_Callout_Principal`.

Steps 1–2 and 4–6 are deployable metadata (`force-app/main/default/namedCredentials`, `externalCredentials`); the Consumer Secret and Principal authentication parameters are never stored in metadata (Salesforce encrypts them server-side) and must be entered by hand in every org, including this one.

## Consequences

- **Positive**: the actual, real-world call path (LWC → Aura → Apex) now authenticates correctly; live-verified end to end (both the CLI and the real Graph Explorer UI return `Internal Sharing Model: ReadWrite, External Sharing Model: Private` for Account, no error).
- **Positive**: the Adapter's contract (`query(soql)`, throws `OI_ServiceException`/`OI_ValidationException`, `parseRecords` isolation) is completely unchanged — only the transport/auth concern inside `query()` changed, so `OI_ObjectSharingSettingsService`, its DTO, `OI_GraphController`, and the LWC needed zero changes.
- **Negative — package-compatibility regression**: this feature is no longer zero-config. Every installing org's admin must complete the setup above once after installing the package. This must be called out explicitly in install/setup documentation (ProductSpecs.md §"Named Credential / secure endpoint strategy" already anticipated this generally).
- **Negative**: the callout's effective access is governed by the **Run As** user configured in step 2, not the actual end user viewing the panel — an end user with narrower sharing/FLS than the Run As identity could theoretically see a sharing-model fact for an object they otherwise couldn't fully describe. This is a deliberate, documented trade-off (Sharing Settings values are org-wide, non-record-specific facts — not per-user-sensitive data — so this is judged acceptable, but it must be re-examined if this Adapter is ever reused for a query that returns anything more sensitive).
- **Follow-up**: whether/how to script or partially automate this setup (e.g., a post-install Apex trigger prompting the admin, or an LWC-driven setup wizard) is not solved here — tracked as a new Backlog item, deliberately not built speculatively now.

## Alternatives Considered

- **Keep session-based auth, drop the Sharing Settings feature** — rejected: throws away real, already-built, already-tested functionality over a fixable platform gap; the fix (Named Credential) is a well-supported, standard Salesforce pattern for exactly this "call your own org's API from Apex" need.
- **JWT Bearer Flow with a self-signed certificate** — rejected for v1: avoids a stored Client Secret, but requires certificate generation/rotation and Digital Signature configuration — meaningfully more setup complexity than Client Credentials flow for no security benefit in a same-org self-callout, where the secret never leaves the org.
- **Per-user Named Principal (each viewing user authorizes individually)** — rejected: reintroduces an interactive OAuth authorization step for every user of the panel, not just the installing admin, which is worse UX than the one-time admin setup chosen; a Named Principal (shared, `Run As` one identity) is the right fit since this fact is org-wide and non-user-specific.
- **Relaxing the org's session security policies to let UI sessions call the API** — rejected outright: this would weaken a platform-wide CSRF protection to work around one feature; never an acceptable trade-off.

## Related

`OI_ToolingApiAdapter.cls`, `OI_ObjectSharingSettingsService.cls`, `OI_ObjectSharingSettingsDTO.cls`, `OI_GraphController.getObjectSharingSettings`; `docs/Backlog.md` DE-15 (MS-2, this Adapter's original ticket); `docs/ProductSpecs.md` §"Named Credential / secure endpoint strategy"; `docs/Architecture.md` §"Native Salesforce stack only... Named Credentials".
