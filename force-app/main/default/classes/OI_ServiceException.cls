/**
 * Purpose: Signals a business-rule violation raised inside a Service (Architecture.md §12).
 * Responsibilities: Base type for Service-layer failures; Controllers catch this (and its
 *                    subtypes) and translate to AuraHandledException with a sanitized message.
 * Dependencies: None.
 * Limitations: None.
 */
public virtual class OI_ServiceException extends OI_ApplicationException {
}
