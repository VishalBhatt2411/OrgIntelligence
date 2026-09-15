/**
 * Purpose: Org Health's Storage detail container (ADR-0026 Tier 1 — live, unpersisted).
 * Responsibilities: Call OI_OrgHealthController.getStorageDetail, shape the DTO into KPI
 *                    tiles, and render the state-contract's "not obtainable" banner for any
 *                    limit type this org edition doesn't expose (never assume it's zero).
 * Dependencies: OI_OrgHealthController.getStorageDetail, oiHealthKpiTile, oiStateBanner, oiSkeleton.
 */
import { LightningElement } from "lwc";
import getStorageDetail from "@salesforce/apex/OI_OrgHealthController.getStorageDetail";

export default class OiHealthStorage extends LightningElement {
  isLoading = true;
  loadError;
  storage;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.isLoading = true;
    this.loadError = undefined;
    try {
      this.storage = await getStorageDetail();
    } catch (error) {
      this.loadError =
        (error && error.body && error.body.message) ||
        "Something went wrong loading Storage.";
    } finally {
      this.isLoading = false;
    }
  }

  get hasError() {
    return !!this.loadError;
  }

  get hasStorage() {
    return !this.isLoading && !this.hasError && !!this.storage;
  }

  get kpiTiles() {
    if (!this.storage) {
      return [];
    }
    const tiles = [];
    if (
      this.storage.dataUsedMb !== null &&
      this.storage.dataUsedMb !== undefined
    ) {
      tiles.push({
        key: "dataUsed",
        label: "Data storage used",
        value: `${this.storage.dataUsedMb.toLocaleString()} MB`
      });
      tiles.push({
        key: "dataLimit",
        label: "Data storage limit",
        value: `${this.storage.dataLimitMb.toLocaleString()} MB`
      });
      tiles.push({
        key: "dataRemaining",
        label: "Data storage remaining",
        value: `${this.storage.dataRemainingMb.toLocaleString()} MB`
      });
    }
    if (
      this.storage.fileUsedMb !== null &&
      this.storage.fileUsedMb !== undefined
    ) {
      tiles.push({
        key: "fileUsed",
        label: "File storage used",
        value: `${this.storage.fileUsedMb.toLocaleString()} MB`
      });
      tiles.push({
        key: "fileLimit",
        label: "File storage limit",
        value: `${this.storage.fileLimitMb.toLocaleString()} MB`
      });
      tiles.push({
        key: "fileRemaining",
        label: "File storage remaining",
        value: `${this.storage.fileRemainingMb.toLocaleString()} MB`
      });
    }
    return tiles;
  }

  get hasUnavailableMetrics() {
    return (
      this.storage &&
      this.storage.unavailableMetrics &&
      this.storage.unavailableMetrics.length > 0
    );
  }

  get unavailableMetricsMessage() {
    return this.storage
      ? `Not exposed by this org's API version: ${this.storage.unavailableMetrics.join(", ")}.`
      : "";
  }

  handleRetry() {
    this.load();
  }
}
