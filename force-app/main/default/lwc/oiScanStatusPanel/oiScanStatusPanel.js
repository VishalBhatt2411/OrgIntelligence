/**
 * Purpose: The first LWC in this package (Sprint 9) — minimal scan status/control panel
 *          (Backlog UI-7, Roadmap Phase 1's "visible progress" exit criterion). Backs
 *          onto OI_ScanController only.
 * Responsibilities: Show the most recent scan's status, subscribe to OI_Scan_Progress__e
 *                    for live updates while a scan is Running, and offer Start/Cancel
 *                    actions. No business logic — every decision (single-flight, retire
 *                    chunking, cancellation semantics) lives server-side in
 *                    OI_ScanOrchestratorQueueable; this component only reflects state and
 *                    dispatches the two mutating calls.
 * Note: Deliberately not split into container/presentational components the way the
 *       Graph Canvas family is (GraphUI.md §3) — Backlog describes oiScanStatusPanel as a
 *       single admin-console-style widget (alongside oiSettingsPanel/oiAdminConsole), not
 *       a Graph UI component, and splitting a single-purpose status panel into two files
 *       for a permission-gated internal tool would be exactly the premature structural
 *       complexity Sprint 9 was asked to avoid.
 */
import { LightningElement } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import startScan from '@salesforce/apex/OI_ScanController.startScan';
import cancelScan from '@salesforce/apex/OI_ScanController.cancelScan';
import getScanHistory from '@salesforce/apex/OI_ScanController.getScanHistory';

const PROGRESS_CHANNEL = '/event/OI_Scan_Progress__e';
const STATUS_RUNNING = 'Running';

export default class OiScanStatusPanel extends LightningElement {
    scanRunId;
    status;
    message;
    isLoading = false;
    subscription;

    connectedCallback() {
        this.loadMostRecentScan();
        this.subscribeToProgress();
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = undefined;
        }
    }

    async loadMostRecentScan() {
        try {
            const history = await getScanHistory({ pageSize: 1, pageCursor: null });
            if (history && history.length > 0) {
                this.applyStatus(history[0]);
            }
        } catch (error) {
            this.showError(error);
        }
    }

    subscribeToProgress() {
        onError((error) => {
            this.showError(error);
        });
        subscribe(PROGRESS_CHANNEL, -1, (event) => this.handleProgressEvent(event)).then((response) => {
            this.subscription = response;
        });
    }

    handleProgressEvent(event) {
        const payload = event.data.payload;
        if (this.scanRunId && payload.Scan_Run_Id__c && payload.Scan_Run_Id__c !== this.scanRunId) {
            return;
        }
        if (payload.Scan_Run_Id__c) {
            this.scanRunId = payload.Scan_Run_Id__c;
        }
        this.status = payload.Status__c;
        this.message = payload.Message__c;
    }

    applyStatus(dto) {
        this.scanRunId = dto.scanRunId;
        this.status = dto.status;
        this.message = null;
    }

    get isRunning() {
        return this.status === STATUS_RUNNING;
    }

    get statusLabel() {
        return this.status ? this.status : 'No scans yet';
    }

    async handleStartScan() {
        this.isLoading = true;
        try {
            const dto = await startScan({ scanType: 'Full', metadataTypeOverride: null });
            this.applyStatus(dto);
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleCancelScan() {
        this.isLoading = true;
        try {
            await cancelScan({ scanRunId: this.scanRunId });
            this.status = 'Cancelled';
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    showError(error) {
        const message = (error && error.body && error.body.message) || 'Something went wrong with the scan.';
        this.dispatchEvent(new ShowToastEvent({ title: 'Scan Error', message, variant: 'error' }));
    }
}
