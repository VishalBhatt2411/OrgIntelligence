/**
 * Purpose: Org Health's severity/score-band registry (ADR-0026), reading
 *          OI_Health_Severity_Descriptor__mdt — extends the Node/Edge Type Descriptor
 *          registry pattern (GraphUI.md §20-21) onto a score-band axis.
 * Responsibilities: Expose the full registry for client-side lookup rendering, and resolve
 *                    a raw score to its severity key server-side for any section DTO that
 *                    needs one. Mandatory generic-fallback behavior: a score outside every
 *                    configured band, or a null score, resolves to null (the caller/UI
 *                    renders a neutral "not scored" state) rather than throwing or guessing.
 * Dependencies: OI_Health_Severity_Descriptor__mdt.
 * Limitations: Bands are assumed non-overlapping; if package configuration ever creates
 *              overlapping bands, the first match in CMDT-returned order wins — not
 *              validated here, since CMDT records are admin/package-managed, not
 *              user-editable data (Architecture.md §4's "does not own" column).
 */
public with sharing class OI_HealthSeverityService {
  public List<OI_HealthSeverityDescriptorDTO> getSeverityRegistry() {
    List<OI_HealthSeverityDescriptorDTO> registry = new List<OI_HealthSeverityDescriptorDTO>();
    for (
      OI_Health_Severity_Descriptor__mdt row : OI_Health_Severity_Descriptor__mdt.getAll()
        .values()
    ) {
      registry.add(new OI_HealthSeverityDescriptorDTO(row));
    }
    return registry;
  }

  /** Null score or a score outside every configured band both resolve to null — never a guessed severity. */
  public String resolveSeverityKey(Decimal score) {
    if (score == null) {
      return null;
    }
    for (
      OI_Health_Severity_Descriptor__mdt row : OI_Health_Severity_Descriptor__mdt.getAll()
        .values()
    ) {
      if (score >= row.Min_Score__c && score <= row.Max_Score__c) {
        return row.Severity_Key__c;
      }
    }
    return null;
  }
}
