/**
 * Purpose: Chunked JSON storage for a Tech Debt scan's component inventory (OI_TD_Scan_Data__c).
 * Responsibilities: Split a JSON payload into ≤ CHUNK_SIZE character records keyed by
 *                    (scan, kind, seq) and reassemble it on read. One logical payload per kind,
 *                    except "packs" (fields shards, haystack packs) which are addressed by seq.
 * Dependencies: OI_TD_Scan_Data__c.
 * Limitations: Long Text Area caps a record at 131,072 characters; every record costs a flat
 *              2 KB of data storage regardless of size, so a few large records are far cheaper
 *              on Developer Edition storage than one record per component.
 */
public with sharing class OI_TD_DataStore {
  public static final Integer CHUNK_SIZE = 130000;

  /** Builds (but does not insert) the chunk records for a whole payload. */
  public static List<OI_TD_Scan_Data__c> chunks(
    Id scanId,
    String kind,
    String payload
  ) {
    List<OI_TD_Scan_Data__c> rows = new List<OI_TD_Scan_Data__c>();
    String text = payload == null ? '' : payload;
    Integer seq = 0;
    Integer pos = 0;
    do {
      Integer endPos = Math.min(pos + CHUNK_SIZE, text.length());
      rows.add(
        new OI_TD_Scan_Data__c(
          Scan__c = scanId,
          Kind__c = kind,
          Seq__c = seq,
          Data__c = text.substring(pos, endPos)
        )
      );
      pos = endPos;
      seq++;
    } while (pos < text.length());
    return rows;
  }

  /** Builds one addressable pack record (payload must fit in one chunk). */
  public static OI_TD_Scan_Data__c pack(
    Id scanId,
    String kind,
    Integer seq,
    String payload
  ) {
    return new OI_TD_Scan_Data__c(
      Scan__c = scanId,
      Kind__c = kind,
      Seq__c = seq,
      Data__c = payload
    );
  }

  /** Reassembles a chunked payload, or null when it was never written. */
  public static String read(Id scanId, String kind) {
    List<String> parts = new List<String>();
    for (OI_TD_Scan_Data__c row : [
      SELECT Data__c
      FROM OI_TD_Scan_Data__c
      WHERE Scan__c = :scanId AND Kind__c = :kind
      ORDER BY Seq__c
    ]) {
      parts.add(row.Data__c == null ? '' : row.Data__c);
    }
    return parts.isEmpty() ? null : String.join(parts, '');
  }

  /** Reads one pack record by seq. */
  public static String readPack(Id scanId, String kind, Integer seq) {
    List<OI_TD_Scan_Data__c> rows = [
      SELECT Data__c
      FROM OI_TD_Scan_Data__c
      WHERE Scan__c = :scanId AND Kind__c = :kind AND Seq__c = :seq
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].Data__c;
  }

  public static Integer countPacks(Id scanId, String kind) {
    return [
      SELECT COUNT()
      FROM OI_TD_Scan_Data__c
      WHERE Scan__c = :scanId AND Kind__c = :kind
    ];
  }

  /** Parses a stored JSON array payload; empty list when missing. */
  public static List<Object> readList(Id scanId, String kind) {
    String json = read(scanId, kind);
    if (String.isBlank(json)) {
      return new List<Object>();
    }
    return (List<Object>) System.JSON.deserializeUntyped(json);
  }

  /** Existing rows for a kind — used to replace a payload in place. */
  public static List<OI_TD_Scan_Data__c> existing(Id scanId, String kind) {
    return [
      SELECT Id
      FROM OI_TD_Scan_Data__c
      WHERE Scan__c = :scanId AND Kind__c = :kind
    ];
  }
}
