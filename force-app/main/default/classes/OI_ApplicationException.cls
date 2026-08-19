/**
 * Purpose: Root of the platform's exception hierarchy (Architecture.md §12).
 * Responsibilities: Common base for every exception the platform throws deliberately, so
 *                    Controllers can catch one type at the boundary and translate to a
 *                    sanitized, user-safe message.
 * Dependencies: None.
 * Limitations: Never thrown directly — always one of its subtypes.
 */
public abstract class OI_ApplicationException extends Exception {
}
