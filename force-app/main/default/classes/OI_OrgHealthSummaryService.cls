/**
 * Purpose: Assembles the Org Health landing grid (ADR-0026) — the one orchestration point
 *          that knows all seven sections exist, via OI_Org_Health_Section_Config__mdt
 *          rather than a hardcoded list, so a future section only needs a new CMDT row and
 *          Service, never a change here.
 * Responsibilities: Read the section registry in Display_Order__c order; for each section
 *                    whose Service exists yet (Org Overview, Storage — Phase 1; Metadata
 *                    Health — Phase 2; Automation Health, Code Health — Phase 3; Security
 *                    Health — Phase 4; Data Health — Phase 5), call it and build a real summary
 *                    card; for every other section, return an isImplemented=false stub card so
 *                    the landing grid can render a "coming soon" state honestly rather than
 *                    omitting the card entirely.
 * Dependencies: OI_OrgOverviewService, OI_StorageHealthService, OI_MetadataHealthService,
 *               OI_AutomationHealthService, OI_CodeHealthService, OI_SecurityHealthService,
 *               OI_DataHealthService, OI_Org_Health_Section_Config__mdt.
 * Limitations: The per-section branch is a deliberate if/else keyed on Section_Key__c — all
 *              seven sections in this package version now have a real branch, but the
 *              not-implemented fallback stays in place for any future section a newer package
 *              version might introduce ahead of this class's own update. If this grows further
 *              without a cleaner per-section strategy (e.g. a registry of Service instances
 *              keyed by Section_Key__c), that refactor should happen then, not be speculatively
 *              built now.
 */
public with sharing class OI_OrgHealthSummaryService {
  private static final String ORG_OVERVIEW_SECTION_KEY = 'OrgOverview';
  private static final String STORAGE_SECTION_KEY = 'Storage';
  private static final String METADATA_HEALTH_SECTION_KEY = 'MetadataHealth';
  private static final String AUTOMATION_HEALTH_SECTION_KEY = 'AutomationHealth';
  private static final String CODE_HEALTH_SECTION_KEY = 'CodeHealth';
  private static final String SECURITY_HEALTH_SECTION_KEY = 'SecurityHealth';
  private static final String DATA_HEALTH_SECTION_KEY = 'DataHealth';

  private final OI_OrgOverviewService orgOverviewService;
  private final OI_StorageHealthService storageHealthService;
  private final OI_MetadataHealthService metadataHealthService;
  private final OI_AutomationHealthService automationHealthService;
  private final OI_CodeHealthService codeHealthService;
  private final OI_SecurityHealthService securityHealthService;
  private final OI_DataHealthService dataHealthService;

  public OI_OrgHealthSummaryService() {
    this(
      new OI_OrgOverviewService(),
      new OI_StorageHealthService(),
      new OI_MetadataHealthService(),
      new OI_AutomationHealthService(),
      new OI_CodeHealthService(),
      new OI_SecurityHealthService(),
      new OI_DataHealthService()
    );
  }

  public OI_OrgHealthSummaryService(
    OI_OrgOverviewService orgOverviewService,
    OI_StorageHealthService storageHealthService,
    OI_MetadataHealthService metadataHealthService,
    OI_AutomationHealthService automationHealthService,
    OI_CodeHealthService codeHealthService,
    OI_SecurityHealthService securityHealthService,
    OI_DataHealthService dataHealthService
  ) {
    this.orgOverviewService = orgOverviewService;
    this.storageHealthService = storageHealthService;
    this.metadataHealthService = metadataHealthService;
    this.automationHealthService = automationHealthService;
    this.codeHealthService = codeHealthService;
    this.securityHealthService = securityHealthService;
    this.dataHealthService = dataHealthService;
  }

  public OI_OrgHealthSummaryDTO getSummary() {
    OI_OrgOverviewDTO overview = orgOverviewService.getOrgOverview();

    OI_OrgHealthSummaryDTO summary = new OI_OrgHealthSummaryDTO();
    summary.overview = overview;

    for (
      OI_Org_Health_Section_Config__mdt sectionConfig : loadSectionConfigsOrdered()
    ) {
      if (sectionConfig.Section_Key__c == ORG_OVERVIEW_SECTION_KEY) {
        summary.sections.add(buildOrgOverviewCard(sectionConfig, overview));
      } else if (sectionConfig.Section_Key__c == STORAGE_SECTION_KEY) {
        summary.sections.add(buildStorageCard(sectionConfig));
      } else if (sectionConfig.Section_Key__c == METADATA_HEALTH_SECTION_KEY) {
        summary.sections.add(buildMetadataHealthCard(sectionConfig));
      } else if (
        sectionConfig.Section_Key__c == AUTOMATION_HEALTH_SECTION_KEY
      ) {
        summary.sections.add(buildAutomationHealthCard(sectionConfig));
      } else if (sectionConfig.Section_Key__c == CODE_HEALTH_SECTION_KEY) {
        summary.sections.add(buildCodeHealthCard(sectionConfig));
      } else if (sectionConfig.Section_Key__c == SECURITY_HEALTH_SECTION_KEY) {
        summary.sections.add(buildSecurityHealthCard(sectionConfig));
      } else if (sectionConfig.Section_Key__c == DATA_HEALTH_SECTION_KEY) {
        summary.sections.add(buildDataHealthCard(sectionConfig));
      } else {
        summary.sections.add(buildNotImplementedCard(sectionConfig));
      }
    }
    return summary;
  }

  private List<OI_Org_Health_Section_Config__mdt> loadSectionConfigsOrdered() {
    List<OI_Org_Health_Section_Config__mdt> configs = OI_Org_Health_Section_Config__mdt.getAll()
      .values();
    List<OI_Org_Health_Section_Config__mdt> sorted = configs.clone();
    sorted.sort(new BySectionDisplayOrder());
    return sorted;
  }

  private OI_OrgHealthSectionSummaryDTO buildOrgOverviewCard(
    OI_Org_Health_Section_Config__mdt sectionConfig,
    OI_OrgOverviewDTO overview
  ) {
    OI_OrgHealthSectionSummaryDTO card = baseCard(sectionConfig, true);
    card.topSignals.add(
      new OI_HealthKeyValueDTO('Objects', String.valueOf(overview.objectCount))
    );
    card.topSignals.add(
      new OI_HealthKeyValueDTO('Fields', String.valueOf(overview.fieldCount))
    );
    card.topSignals.add(
      new OI_HealthKeyValueDTO(
        'Apex Classes',
        String.valueOf(overview.apexClassCount)
      )
    );
    card.coverageNote = overview.lastScannedAt == null
      ? 'No scan has completed yet.'
      : 'Last scanned ' + overview.lastScannedAt.format();
    return card;
  }

  private OI_OrgHealthSectionSummaryDTO buildStorageCard(
    OI_Org_Health_Section_Config__mdt sectionConfig
  ) {
    OI_OrgHealthSectionSummaryDTO card = baseCard(sectionConfig, true);
    OI_StorageHealthDTO storage = storageHealthService.getStorageHealth();
    if (storage.dataUsedMb != null && storage.dataLimitMb != null) {
      card.topSignals.add(
        new OI_HealthKeyValueDTO(
          'Data storage used',
          storage.dataUsedMb + ' / ' + storage.dataLimitMb + ' MB'
        )
      );
    }
    if (storage.fileUsedMb != null && storage.fileLimitMb != null) {
      card.topSignals.add(
        new OI_HealthKeyValueDTO(
          'File storage used',
          storage.fileUsedMb + ' / ' + storage.fileLimitMb + ' MB'
        )
      );
    }
    card.coverageNote = storage.unavailableMetrics.isEmpty()
      ? 'Live org limits.'
      : 'Not obtainable: ' + String.join(storage.unavailableMetrics, ', ');
    return card;
  }

  private OI_OrgHealthSectionSummaryDTO buildMetadataHealthCard(
    OI_Org_Health_Section_Config__mdt sectionConfig
  ) {
    OI_OrgHealthSectionSummaryDTO card = baseCard(sectionConfig, true);
    OI_MetadataHealthDTO metadataHealth = metadataHealthService.getMetadataHealthDetail();
    card.score = metadataHealth.score;
    card.severityKey = metadataHealth.severityKey;
    // Landing-grid cards show 2-3 top signals (OrgHealthVisualDesignSpecification.md §3.2); the
    // detail view's own 4-tile KPI row is where the full set (including High-degree objects) lives.
    for (OI_HealthKeyValueDTO tile : metadataHealth.kpiTiles) {
      if (
        tile.label == 'High field-count objects' ||
        tile.label == 'No incoming references detected' ||
        tile.label == 'Dependency density'
      ) {
        card.topSignals.add(tile);
      }
    }
    card.coverageNote = metadataHealth.coverageNote;
    return card;
  }

  /** Facts-only card (Is_Scored__c = false, §0.3) — score/severityKey stay null, matching baseCard's default; the landing grid renders the "Facts only" badge instead of a score ring. */
  private OI_OrgHealthSectionSummaryDTO buildAutomationHealthCard(
    OI_Org_Health_Section_Config__mdt sectionConfig
  ) {
    OI_OrgHealthSectionSummaryDTO card = baseCard(sectionConfig, true);
    OI_AutomationHealthDTO automationHealth = automationHealthService.getAutomationHealthDetail();
    for (OI_HealthKeyValueDTO tile : automationHealth.kpiTiles) {
      if (
        tile.label == 'Triggers scanned' ||
        tile.label == 'Flows scanned' ||
        tile.label == 'High fan-in/out components'
      ) {
        card.topSignals.add(tile);
      }
    }
    card.coverageNote = automationHealth.coverageNote;
    return card;
  }

  private OI_OrgHealthSectionSummaryDTO buildCodeHealthCard(
    OI_Org_Health_Section_Config__mdt sectionConfig
  ) {
    OI_OrgHealthSectionSummaryDTO card = baseCard(sectionConfig, true);
    OI_CodeHealthDTO codeHealth = codeHealthService.getCodeHealthDetail();
    card.score = codeHealth.score;
    card.severityKey = codeHealth.severityKey;
    for (OI_HealthKeyValueDTO tile : codeHealth.kpiTiles) {
      if (
        tile.label == 'High-dependency classes' ||
        tile.label == 'Stale API version classes' ||
        tile.label == 'Classes in dependency cycles'
      ) {
        card.topSignals.add(tile);
      }
    }
    card.coverageNote = codeHealth.coverageNote;
    return card;
  }

  /** Facts-only card (Is_Scored__c = false, §0.3) — score/severityKey stay null, matching baseCard's default; the landing grid renders the "Facts only" badge instead of a score ring. */
  private OI_OrgHealthSectionSummaryDTO buildSecurityHealthCard(
    OI_Org_Health_Section_Config__mdt sectionConfig
  ) {
    OI_OrgHealthSectionSummaryDTO card = baseCard(sectionConfig, true);
    OI_SecurityHealthDTO securityHealth = securityHealthService.getSecurityHealthDetail();
    for (OI_HealthKeyValueDTO tile : securityHealth.kpiTiles) {
      if (
        tile.label == 'Elevated permission sets' ||
        tile.label == 'Permission sets with broad grants' ||
        tile.label == 'Sensitive object grants'
      ) {
        card.topSignals.add(tile);
      }
    }
    card.coverageNote = securityHealth.coverageNote;
    return card;
  }

  /** Scored (Is_Scored__c = true), but async — score/severityKey/topSignals stay honestly empty until a run has completed; getDataHealthDetail's own coverageNote already says so ("has not been computed yet"). */
  private OI_OrgHealthSectionSummaryDTO buildDataHealthCard(
    OI_Org_Health_Section_Config__mdt sectionConfig
  ) {
    OI_OrgHealthSectionSummaryDTO card = baseCard(sectionConfig, true);
    OI_DataHealthDTO dataHealth = dataHealthService.getDataHealthDetail();
    card.score = dataHealth.score;
    card.severityKey = dataHealth.severityKey;
    for (OI_HealthKeyValueDTO tile : dataHealth.kpiTiles) {
      if (
        tile.label == 'Objects scanned' ||
        tile.label == 'Stale records' ||
        tile.label == 'Duplicate records'
      ) {
        card.topSignals.add(tile);
      }
    }
    card.coverageNote = dataHealth.coverageNote;
    return card;
  }

  private OI_OrgHealthSectionSummaryDTO buildNotImplementedCard(
    OI_Org_Health_Section_Config__mdt sectionConfig
  ) {
    OI_OrgHealthSectionSummaryDTO card = baseCard(sectionConfig, false);
    card.coverageNote = 'Not yet available in this package version.';
    return card;
  }

  private OI_OrgHealthSectionSummaryDTO baseCard(
    OI_Org_Health_Section_Config__mdt sectionConfig,
    Boolean isImplemented
  ) {
    OI_OrgHealthSectionSummaryDTO card = new OI_OrgHealthSectionSummaryDTO();
    card.sectionKey = sectionConfig.Section_Key__c;
    card.displayLabel = sectionConfig.Display_Label__c;
    card.isImplemented = isImplemented;
    card.isScored = sectionConfig.Is_Scored__c;
    card.score = null;
    card.severityKey = null;
    return card;
  }

  private class BySectionDisplayOrder implements Comparator<OI_Org_Health_Section_Config__mdt> {
    public Integer compare(
      OI_Org_Health_Section_Config__mdt a,
      OI_Org_Health_Section_Config__mdt b
    ) {
      Decimal orderA = a.Display_Order__c == null ? 0 : a.Display_Order__c;
      Decimal orderB = b.Display_Order__c == null ? 0 : b.Display_Order__c;
      return (orderA - orderB).intValue();
    }
  }
}
