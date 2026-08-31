/**
 * Purpose: The connector-click detail surface for the shared relationship lane canvas
 *          (GraphUI.md §42.4, ADR-0023; generalized to Record mode by ADR-0024) — one aggregated
 *          relationship's own detail: source, field(s) (Object mode only), relationship type,
 *          target, direction, and Open Source/Field/Target actions.
 * Responsibilities: Render the connector descriptor oiRelationshipCanvas's edgeclick event
 *                    already carries (no re-fetch of the relationship itself). Object mode
 *                    resolves navigation for source/target objects and each individual field via
 *                    the existing, generic OI_GraphController.getNavigationTarget +
 *                    c/metadataNavigation — the same navigation path oiIntelligenceDrilldown
 *                    already uses, reused here rather than reimplemented. Record mode's
 *                    source/target are live records, not metadata — getNavigationTarget's
 *                    Setup-URL-oriented resolution does not apply to them, so Open Source/Target
 *                    there builds a standard__recordPage navigation target directly, client-side
 *                    only, from the objectApiName/recordId c/recordRelationshipView already
 *                    parsed onto each ref (c/recordNodeKey) — no Apex call at all, and no new
 *                    navigation kind: c/metadataNavigation's navigateToTarget already handles a
 *                    NAVIGATION_KIND_RECORD target exactly this shape.
 * Dependencies: OI_GraphController.getNavigationTarget, c/metadataNavigation,
 *               c/objectRelationshipView (OBJECT_TYPE_KEY/FIELD_TYPE_KEY constants only).
 * Limitations: This is a single connector's own detail, not a searchable/paged list — for that
 *              broader question ("show me every X"), oiIntelligenceDrilldown remains the
 *              reusable surface; the two are deliberately not merged (GraphUI.md §42.4). Record
 *              mode's connector has no fields[] to browse (c/recordRelationshipView's own
 *              limitation), so the Fields section is omitted entirely there rather than shown
 *              empty.
 */
import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getNavigationTarget from '@salesforce/apex/OI_GraphController.getNavigationTarget';
import { navigateToTarget, NAVIGATION_KIND_RECORD } from 'c/metadataNavigation';
import { OBJECT_TYPE_KEY, FIELD_TYPE_KEY } from 'c/objectRelationshipView';

const MODE_RECORD = 'Record';

export default class OiRelationshipConnectorDetail extends NavigationMixin(LightningElement) {
    /** The connector descriptor from oiRelationshipCanvas's edgeclick event detail — already carries everything needed to render; no independent fetch of the relationship itself. */
    @api connector;
    /** The centered object/record, from the same edgeclick event detail. */
    @api rootObject;
    /** 'Object' (default) or 'Record' — mirrors oiRelationshipCanvas's own mode prop; oiGraphExplorer passes its analyzeMode through unchanged. */
    @api mode = 'Object';

    @track actionMessage = null;

    get isRecordMode() {
        return this.mode === MODE_RECORD;
    }

    get sourceObject() {
        if (!this.connector) {
            return null;
        }
        return this.connector.direction === 'incoming' ? this.connector.counterpartObject : this.rootObject;
    }

    get targetObject() {
        if (!this.connector) {
            return null;
        }
        return this.connector.direction === 'incoming' ? this.rootObject : this.connector.counterpartObject;
    }

    get directionLabel() {
        if (!this.connector || !this.sourceObject || !this.targetObject) {
            return '';
        }
        return `${this.sourceObject.label} → ${this.targetObject.label}`;
    }

    /** Record-mode connectors already carry their own relationshipTypeLabel ("Related Record"/"Related Records", c/recordRelationshipView) — Object mode's Master-Detail/Lookup derivation from primaryRelationshipType stays exactly as before. */
    get relationshipTypeLabel() {
        if (!this.connector) {
            return '';
        }
        if (this.connector.relationshipTypeLabel) {
            return this.connector.relationshipTypeLabel;
        }
        return this.connector.primaryRelationshipType === 'MasterDetail' ? 'Master-Detail' : 'Lookup';
    }

    /** "Lookup Relationship" reads correctly for Object mode; "Related Record" already says what it is, so appending "Relationship" again would just repeat itself. */
    get subtitleLabel() {
        return this.isRecordMode ? this.relationshipTypeLabel : `${this.relationshipTypeLabel} Relationship`;
    }

    get sourceDtLabel() {
        return this.isRecordMode ? 'Source Record' : 'Source Object';
    }

    get targetDtLabel() {
        return this.isRecordMode ? 'Target Record' : 'Target Object';
    }

    get fields() {
        return this.connector ? this.connector.fields : [];
    }

    get hasFields() {
        return this.fields.length > 0;
    }

    get plural() {
        return this.fields.length === 1 ? '' : 's';
    }

    get hasActionMessage() {
        return !!this.actionMessage;
    }

    get headingId() {
        return 'oi-relationship-connector-detail-heading';
    }

    async handleOpenSource() {
        await this.openObject(this.sourceObject);
    }

    async handleOpenTarget() {
        await this.openObject(this.targetObject);
    }

    async handleOpenField(event) {
        const fieldApiName = event.currentTarget.dataset.fieldSecondaryKey;
        const field = this.fields.find((candidate) => candidate.fieldSecondaryKey === fieldApiName);
        if (!field || !field.fieldSecondaryKey) {
            this.actionMessage = 'This field could not be identified.';
            return;
        }
        await this.openTarget(FIELD_TYPE_KEY, field.fieldSecondaryKey);
    }

    /**
     * Object mode's object/target ref carries a metadata secondaryKey (an API name) resolved
     * server-side via getNavigationTarget/OI_MetadataNavigationService — unchanged. Record
     * mode's ref is a live record (objectApiName/recordId, already parsed onto it by
     * c/recordRelationshipView via c/recordNodeKey) — a standard record page needs no Setup-URL
     * resolution at all, so this builds the NAVIGATION_KIND_RECORD target directly, client-side,
     * and hands it to the exact same navigateToTarget c/metadataNavigation already exposes.
     */
    async openObject(object) {
        if (this.isRecordMode) {
            if (!object || !object.recordId) {
                this.actionMessage = 'This record could not be identified.';
                return;
            }
            this.actionMessage = null;
            const result = navigateToTarget(this, { kind: NAVIGATION_KIND_RECORD, recordId: object.recordId, objectApiName: object.objectApiName });
            if (result.message) {
                this.actionMessage = result.message;
            }
            return;
        }
        if (!object || !object.secondaryKey) {
            this.actionMessage = 'This object could not be identified.';
            return;
        }
        await this.openTarget(OBJECT_TYPE_KEY, object.secondaryKey);
    }

    async openTarget(typeKey, apiName) {
        this.actionMessage = null;
        try {
            const target = await getNavigationTarget({ typeKey, apiName });
            const result = navigateToTarget(this, target);
            if (result.message) {
                this.actionMessage = result.message;
            }
        } catch (error) {
            this.actionMessage = this.extractError(error);
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    /** Escape closes the dialog — the same minimum keyboard-user affordance oiIntelligenceDrilldown already provides. */
    handleKeyDown(event) {
        if (event.key === 'Escape') {
            this.handleClose();
        }
    }

    extractError(error) {
        return (error && error.body && error.body.message) || 'Something went wrong opening this component.';
    }
}
