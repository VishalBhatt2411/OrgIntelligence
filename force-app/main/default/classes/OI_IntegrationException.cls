/**
 * Purpose: Signals a Tooling/Metadata/Describe API failure (Architecture.md §12).
 * Responsibilities: Wraps the original platform/callout cause so Adapters never let a raw
 *                    HttpResponse/DescribeResult failure shape leak past the Integration layer.
 * Dependencies: None.
 * Limitations: None.
 */
public class OI_IntegrationException extends OI_ApplicationException {
}
