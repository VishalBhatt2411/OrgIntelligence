/**
 * Purpose: Org Health's Storage section (ADR-0026 Tier 1 — live, unpersisted) —
 *          ProductSpecs.md Phase 4 "Storage": Data Used, Data Remaining, File Used, File
 *          Remaining, real org limits only.
 * Responsibilities: Read System.OrgLimits, translate Data/File Storage into the DTO. No
 *                    scoring — the spec asks this section for facts, not a score.
 * Dependencies: System.OrgLimits (platform static).
 * Limitations: OrgLimits reports whichever limit types this org edition exposes; a limit
 *              type absent from OrgLimits.getMap() is reported via unavailableMetrics
 *              rather than assumed to be zero.
 */
public with sharing class OI_StorageHealthService {
  private static final String DATA_STORAGE_MB = 'DataStorageMB';
  private static final String FILE_STORAGE_MB = 'FileStorageMB';

  public OI_StorageHealthDTO getStorageHealth() {
    OI_StorageHealthDTO dto = new OI_StorageHealthDTO();
    Map<String, System.OrgLimit> limits = OrgLimits.getMap();

    applyLimit(dto, limits, DATA_STORAGE_MB, 'data');
    applyLimit(dto, limits, FILE_STORAGE_MB, 'file');

    return dto;
  }

  private void applyLimit(
    OI_StorageHealthDTO dto,
    Map<String, System.OrgLimit> limits,
    String limitName,
    String kind
  ) {
    System.OrgLimit orgLimit = limits.get(limitName);
    if (orgLimit == null) {
      dto.unavailableMetrics.add(limitName);
      return;
    }
    Integer usedValue = orgLimit.getValue();
    Integer limitValue = orgLimit.getLimit();
    Integer remainingValue = limitValue - usedValue;
    if (kind == 'data') {
      dto.dataUsedMb = usedValue;
      dto.dataLimitMb = limitValue;
      dto.dataRemainingMb = remainingValue;
    } else {
      dto.fileUsedMb = usedValue;
      dto.fileLimitMb = limitValue;
      dto.fileRemainingMb = remainingValue;
    }
  }
}
