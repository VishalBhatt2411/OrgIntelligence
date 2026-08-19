/**
 * Purpose: Signals a detected write conflict inside OI_GraphRepository.commitVersion
 *          (GraphRepository.md §15, ADR-0016).
 * Responsibilities: Gives OI_GraphBuilder a typed signal to catch-and-retry exactly once,
 *                    rather than string-matching a raw DmlException message.
 * Dependencies: None.
 * Limitations: The only exception type OI_GraphBuilder is expected to specifically retry on.
 */
public class OI_ConcurrencyException extends OI_ServiceException {
}
