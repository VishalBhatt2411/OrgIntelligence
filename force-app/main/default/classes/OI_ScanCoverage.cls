/**
 * Purpose: A Scanner's own honest declaration of how complete its relationship extraction was
 *          for one scan task — the mechanism that stops this platform from presenting a graph
 *          that LOOKS complete when dependency discovery was degraded or is simply not
 *          supported yet.
 * Responsibilities: Carry a coverage status, a human-readable reason, and the count of
 *                    relationships the Scanner discovered. Pure data.
 * Dependencies: None (deliberately — a Scanner must be able to describe its own coverage
 *               without reaching for the graph, the orchestrator, or persistence).
 *
 * Why this exists — the defect it closes: a real 2026-08-19 audit of a live org found 122
 * scanned Apex classes and ZERO dependency edges, and nothing anywhere in the product said so.
 * The graph rendered normally, Impact Analysis returned "no dependencies found," and a user had
 * no way to distinguish "this component genuinely has no dependencies" from "this dependency
 * class was never extracted." That ambiguity is the single most trust-destroying thing an
 * intelligence product can do, and no amount of correct traversal code fixes it.
 *
 * The three statuses are deliberately distinct, because they demand different user responses:
 *   COMPLETE      — this Scanner extracted everything it claims to support. Zero relationships
 *                   here is a real finding about the org, not a gap in the tool.
 *   PARTIAL       — this Scanner supports SOME of this type's relationships by design, and
 *                   knowingly does not extract others (e.g. Flow trigger-objects yes, Flow
 *                   internals no). A permanent, documented boundary — not a failure, and not
 *                   something a retry would change.
 *   DEGRADED      — this Scanner SHOULD have extracted relationships on this run but could not
 *                   (source unavailable, access denied, an API failure). Unlike PARTIAL, this
 *                   is situational and may succeed on a later run or with different permissions.
 *
 * Conflating PARTIAL and DEGRADED would be the easy mistake: both mean "incomplete," but only
 * DEGRADED is actionable by the admin, and only PARTIAL is a product roadmap statement. Users
 * chasing a DEGRADED reason that is actually a permanent design boundary waste real time.
 */
public class OI_ScanCoverage {
    public static final String STATUS_COMPLETE = 'Complete';
    public static final String STATUS_PARTIAL = 'Partial';
    public static final String STATUS_DEGRADED = 'Degraded';

    /** One of STATUS_COMPLETE / STATUS_PARTIAL / STATUS_DEGRADED. */
    public final String status;
    /** Plain-language explanation shown to an admin. Null only when status is COMPLETE, where there is by definition nothing to explain. */
    public final String reason;
    /** How many relationships this Scanner discovered — the "discovered" half of the discovered-vs-ingested reconciliation the orchestrator completes later. */
    public final Integer relationshipsDiscovered;

    private OI_ScanCoverage(String status, String reason, Integer relationshipsDiscovered) {
        this.status = status;
        this.reason = reason;
        this.relationshipsDiscovered = relationshipsDiscovered == null ? 0 : relationshipsDiscovered;
    }

    /** Everything this Scanner supports was extracted successfully. */
    public static OI_ScanCoverage complete(Integer relationshipsDiscovered) {
        return new OI_ScanCoverage(STATUS_COMPLETE, null, relationshipsDiscovered);
    }

    /** A permanent, by-design boundary on what this Scanner extracts — state precisely WHAT is not covered, so the reason is useful rather than a shrug. */
    public static OI_ScanCoverage partial(Integer relationshipsDiscovered, String reason) {
        return new OI_ScanCoverage(STATUS_PARTIAL, reason, relationshipsDiscovered);
    }

    /** This run could not extract what it normally would — state the concrete cause, since unlike PARTIAL this may be fixable by the admin. */
    public static OI_ScanCoverage degraded(Integer relationshipsDiscovered, String reason) {
        return new OI_ScanCoverage(STATUS_DEGRADED, reason, relationshipsDiscovered);
    }

    public Boolean isComplete() {
        return STATUS_COMPLETE.equals(status);
    }
}
