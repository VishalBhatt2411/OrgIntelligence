/**
 * Purpose: One independent, explainable piece of evidence feeding a single Org Health
 *          finding's severity — the input shape OI_HealthScoringEngine combines into a score.
 * Responsibilities: Carry a rule's raw magnitude judgment (value vs. threshold) alongside the
 *                    dampeners/amplifiers that turn a bare count into a defensible severity:
 *                    confidence in the detection, how bad this issue type is if fully
 *                    confirmed (impact), how far its blast radius reaches (exposure), and
 *                    whether an administrator has already recorded a mitigation. A rule that
 *                    genuinely has more than one independent signal (e.g. "elevated
 *                    permissions" and "broad object grants" on the same Permission Set) passes
 *                    one instance per signal; correlationGroup lets two signals that measure
 *                    overlapping evidence combine by their strongest member instead of summing
 *                    (OI_HealthScoringEngine's own doc comment).
 * Dependencies: None.
 * Limitations: magnitude is expected pre-normalized to "1.0 == exactly at the configured
 *              threshold" (value / threshold) — the engine saturates it, it does not compute
 *              the ratio itself, since only the calling rule knows what its own threshold means.
 */
public class OI_HealthSignal {
  public String key;
  public String label;
  /** 0–100: how many badness points this signal can contribute at full magnitude, confidence, impact, and exposure. Independent signals on one finding should sum their weights to roughly 100 so a single fully-confirmed, high-impact, high-exposure signal alone can reach Critical — exactly as intended when the evidence genuinely warrants it. */
  public Decimal weight;
  /** value / threshold. 1.0 = at the threshold, 1.5+ = saturates the signal's full weight. Never negative. */
  public Decimal magnitude;
  /** 0.0–1.0 confidence this magnitude reading is accurate; a Low-confidence signal can never alone saturate a finding to Critical. */
  public Decimal confidence = 1.0;
  /** How bad this issue TYPE is if fully confirmed — e.g. a managed-package object's field count is real but not this org's to fix, so it dampens impact without hiding the finding. Default 1.0 = full impact. */
  public Decimal impactMultiplier = 1.0;
  /** Blast-radius/exposure amplifier — e.g. an object that is also heavily referenced, or a permission actually held by active users. Default 1.0 = no adjustment. */
  public Decimal exposureMultiplier = 1.0;
  /** An administrator-recorded compensating control already mitigates this specific signal — halves its contribution without erasing the underlying evidence. */
  public Boolean hasCompensatingControl = false;
  /** Signals sharing a non-blank group combine by MAX contribution, not sum, so two views of the same underlying evidence never double-count. Null/blank = its own independent group. */
  public String correlationGroup;
  /** Human-readable explanation of this signal's value, e.g. "148 fields detected (threshold 60)." — carried straight into the drawer's contributor breakdown. */
  public String note;

  public OI_HealthSignal(
    String key,
    String label,
    Decimal weight,
    Decimal magnitude,
    String note
  ) {
    this.key = key;
    this.label = label;
    this.weight = weight == null ? 0 : weight;
    this.magnitude = magnitude == null ? 0 : magnitude;
    this.note = note;
  }
}
