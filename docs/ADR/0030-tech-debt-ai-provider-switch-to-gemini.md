# ADR-0030: Tech Debt "Explain with AI" Switched from Anthropic to Google Gemini (Free Tier)

## Status

Accepted for the development org (`devEditionProject`). **Must be revisited before any AppExchange release** (see Consequences).

## Context

The Tech Debt tab's "Explain with AI" feature (`OI_TD_Controller.explainFinding` / `explainComponent`) sends one prompt per click to an LLM and shows the reply. `OI_TD_AiService` is the only class that talks to the provider; it called the Anthropic Messages API through the `OI_Anthropic` Named Credential, whose `OI_Anthropic_Credential` External Credential (Custom protocol) injected the `x-api-key` header from the `OI_Anthropic_Principal` principal's `ApiKey` parameter.

For the new development org the team wants a provider that costs nothing while the feature is being built and demoed. Google's Gemini API offers a free tier with a key from Google AI Studio.

## Decision

`OI_TD_AiService` now calls Gemini's `generateContent` endpoint instead of Anthropic's Messages API. The switch keeps the same credential pattern and the same public contract:

- **Credentials.** A new Named Credential, `OI_Gemini` (`https://generativelanguage.googleapis.com`), is backed by the External Credential `OI_Gemini_Credential`. It uses the Custom protocol with the Named Principal `OI_Gemini_Principal`. Its `x-goog-api-key` AuthHeader resolves `{!$Credential.OI_Gemini_Credential.ApiKey}`. The key is entered by hand on the principal in each org; it never appears in metadata, code or data. `OI_Administrator` and `OI_Power_User` get principal access to it.
- **Request.** The service sends `POST callout:OI_Gemini/v1beta/models/<MODEL>:generateContent` with the body `{"contents":[{"role":"user","parts":[{"text":…}]}],"generationConfig":{"maxOutputTokens":1200,"thinkingConfig":{"thinkingLevel":"low"}}}`.
- **Model.** `gemini-3.8-flash` lives in the single constant `OI_TD_AiService.MODEL`. It is the newest stable (non-preview) Flash model, and Google's model docs recommend it for new projects. It is also free-of-charge on the free tier. Flash-Lite would give higher free-tier rate limits, but its explanations of code are weaker. For a click-per-request feature, answer quality matters more than throughput.
- **Thinking level.** Gemini 3.x Flash models "think" by default, and those thinking tokens count against `maxOutputTokens`. Leaving the default in place could spend the 1200-token budget on reasoning and return an empty or truncated answer. Pinning `thinkingLevel` to `low` avoids that. Thinking cannot be switched off entirely on Flash.
- **Reply parsing.** The service joins `candidates[0].content.parts[].text` and skips parts marked `thought: true`. It raises a clear `OI_IntegrationException`, and does not retry, in three cases:
  - an empty or missing `candidates` array, reporting `promptFeedback.blockReason` when present;
  - a candidate with no text, reporting its `finishReason`, for example `SAFETY`;
  - an unreadable body.
- **Errors.** Gemini errors (`{error:{code,message,status}}`) are reported as `AI provider error <code>: <status> — <message>`.
- **Retries.** The transient-error pattern now also covers `429`, `RESOURCE_EXHAUSTED`, `UNAVAILABLE` and `503`. These matter on the free tier, which has low per-minute rate limits.
- **Public contract.** `explainFinding`, `explainComponent`, `clip`, `SOURCE_CHAR_LIMIT` and `FindingExplanation` are unchanged, and `OI_TD_Controller` needed no changes.

The Anthropic Named Credential, External Credential and permission-set grants stay deployed for now. No code references them any more.

## Consequences

- **Positive:** there is no provider cost in the development org.
- **Positive:** the provider-specific code stays confined to `OI_TD_AiService`, so switching back or adding another provider touches one class and its credentials.
- **Negative — data use (the key trade-off):** Google's pricing page says free-tier content **is used to improve Google's products**; paid-tier content is not. This feature's prompts include org metadata and **customer source code**: Apex classes, triggers, LWC and Visualforce, clipped to `SOURCE_CHAR_LIMIT` characters. That is acceptable for this development org, which holds only our own code. It is **not acceptable for a distributed package**, where the code belongs to the customer. Before AppExchange, this must move to one of these:
  1. a paid Gemini tier, where content is not used for training;
  2. a configurable provider, where the customer admin chooses the provider and supplies their own key and terms, and the provider is selected via Custom Metadata behind an interface;
  3. an explicit opt-in consent step shown before any source code is sent.

  Security Review will ask about this regardless.

- **Negative — rate limits:** Apex cannot sleep, so retries fire immediately. A per-minute 429 may still be in effect after both retries, and the user then sees the rate-limit error. That is acceptable for a click-driven feature; a Queueable-based delayed retry would be the fix if it becomes a problem.
- **Negative — setup:** each org's admin must add the `ApiKey` authentication parameter on `OI_Gemini_Principal` by hand, as with any Named Principal secret.
- **Risk:** the `thinkingConfig.thinkingLevel` field is specific to the Gemini 3 family. If `MODEL` is changed to a model that rejects it, the call returns HTTP 400 and the parameter must be adjusted, for example to `thinkingBudget` on 2.5-series models.

## Alternatives Considered

- **Keep Anthropic.** Rejected for the development org because of cost; it remains a good candidate for the paid or configurable option above.
- **Gemini Flash-Lite.** It has higher free-tier limits but weaker explanations of code; it is easy to switch to later by changing `MODEL`.
- **A provider abstraction built now** (an interface plus Custom Metadata selection). Deferred: nothing needs a second provider yet (CLAUDE.md: "do not introduce unnecessary complexity"). It is the likely shape of consequence option 2.
- **An API key in a Custom Setting or Custom Metadata.** Rejected outright: secrets belong in External Credential principals, which Salesforce encrypts and never exposes to Apex.

## Related

`OI_TD_AiService.cls`, `OI_TD_AiServiceTest.cls`, `OI_TD_Controller.cls`; `namedCredentials/OI_Gemini`, `externalCredentials/OI_Gemini_Credential`; [ADR-0029](0029-tooling-api-self-callout-via-named-credential.md), which uses the same Named/External Credential pattern.
