/**
 * Purpose: Where clicking a drill-down row should take the user, resolved server-side into a
 *          shape the LWC can hand straight to NavigationMixin.
 * Responsibilities: Carry a navigation kind plus exactly the identifiers that kind needs, or an
 *                    honest reason why this component cannot be navigated to. Pure data.
 * Dependencies: None.
 *
 * Why navigation is resolved in Apex rather than built in the LWC: Salesforce Setup pages are
 * addressed by DURABLE IDs, not API names, and the mapping is not guessable — verified against a
 * real org, the field `Account.OwnerId` has DurableId `Account.Owner` (the "Id" suffix is
 * dropped for relationship fields), and a custom object is addressed as `01If6000002DBBv`, not
 * by its API name. A component that assembled URLs from API names would therefore break on
 * exactly the fields users click most: lookups. Resolution needs SOQL, so it belongs here, and
 * centralising it means no LWC ever contains a Setup URL.
 *
 * URLs are always RELATIVE (`/lightning/setup/...`) so nothing is tied to a My Domain or org
 * host — a package-safety requirement, not a preference.
 */
public class OI_NavigationTargetDTO {
    /** Navigate via NavigationMixin's standard__recordPage — a real record, the only kind with first-class navigation support. */
    public static final String KIND_RECORD = 'record';
    /** Navigate via standard__webPage to a relative Setup URL. */
    public static final String KIND_SETUP_PAGE = 'setupPage';
    /** Navigation is genuinely not available for this component type; `reason` explains why. */
    public static final String KIND_UNSUPPORTED = 'unsupported';

    @AuraEnabled
    public String kind;
    /** Relative Setup URL for KIND_SETUP_PAGE. Never absolute. */
    @AuraEnabled
    public String url;
    /** Record id for KIND_RECORD. */
    @AuraEnabled
    public String recordId;
    /** Object API name for KIND_RECORD, which standard__recordPage needs alongside the id. */
    @AuraEnabled
    public String objectApiName;
    /** Plain-language explanation shown to the user when navigation is unsupported or only partially possible — never a dead link and never a silent no-op. */
    @AuraEnabled
    public String reason;
    /** What the destination actually is, so the UI can label the action honestly (e.g. "Open in Object Manager" vs "Open Flows list"). */
    @AuraEnabled
    public String destinationLabel;

    private OI_NavigationTargetDTO(String kind) {
        this.kind = kind;
    }

    public static OI_NavigationTargetDTO record(String recordId, String objectApiName, String destinationLabel) {
        OI_NavigationTargetDTO target = new OI_NavigationTargetDTO(KIND_RECORD);
        target.recordId = recordId;
        target.objectApiName = objectApiName;
        target.destinationLabel = destinationLabel;
        return target;
    }

    public static OI_NavigationTargetDTO setupPage(String url, String destinationLabel) {
        OI_NavigationTargetDTO target = new OI_NavigationTargetDTO(KIND_SETUP_PAGE);
        target.url = url;
        target.destinationLabel = destinationLabel;
        return target;
    }

    /** A partially-supported destination: navigation works, but lands on a management screen rather than the exact component. The reason must say so, so the user is never surprised. */
    public static OI_NavigationTargetDTO setupPageWithCaveat(String url, String destinationLabel, String reason) {
        OI_NavigationTargetDTO target = setupPage(url, destinationLabel);
        target.reason = reason;
        return target;
    }

    public static OI_NavigationTargetDTO unsupported(String reason) {
        OI_NavigationTargetDTO target = new OI_NavigationTargetDTO(KIND_UNSUPPORTED);
        target.reason = reason;
        return target;
    }
}
