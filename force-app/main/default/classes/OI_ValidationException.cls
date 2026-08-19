/**
 * Purpose: Signals bad input detected at a Controller boundary (Architecture.md §12).
 * Responsibilities: Distinguishes "the caller sent something invalid" from a business-rule
 *                    violation (OI_ServiceException) or a security denial (OI_SecurityException).
 * Dependencies: None.
 * Limitations: None.
 */
public class OI_ValidationException extends OI_ApplicationException {
}
