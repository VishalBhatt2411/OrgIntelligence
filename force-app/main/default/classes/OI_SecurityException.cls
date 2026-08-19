/**
 * Purpose: Signals a CRUD/FLS/sharing/Custom Permission denial (Architecture.md §12, §14).
 * Responsibilities: Thrown by OI_SecurityService when the running user lacks a required
 *                    Custom Permission; carries no information about *why* beyond that fact,
 *                    so a Controller-boundary catch never leaks internal permission names.
 * Dependencies: None.
 * Limitations: None.
 */
public class OI_SecurityException extends OI_ApplicationException {
}
