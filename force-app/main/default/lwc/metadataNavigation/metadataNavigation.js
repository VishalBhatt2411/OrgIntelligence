/**
 * Purpose: The only place in the UI that performs navigation to a Salesforce metadata
 *          component's real configuration screen or record page.
 * Responsibilities: Turn a server-resolved OI_NavigationTargetDTO into an actual navigation via
 *                    NavigationMixin. Never constructs a URL, never decides an identifier.
 *
 * Why this is a plain module rather than logic inside each component: Setup pages are addressed
 * by durable identifiers that cannot be derived from an API name (a lookup field's durable id
 * drops its "Id" suffix; custom objects are not addressable by API name at all — both verified
 * against a real org, see OI_MetadataNavigationService). All of that resolution happens in Apex.
 * What is left for the client is a single decision — record page vs Setup page vs "not
 * supported" — and centralising it means a future navigation type is added in one file instead of
 * scattered across every table and card that can be clicked.
 *
 * The caller supplies its own NavigationMixin-enabled component as `navigator`, because
 * NavigationMixin can only be applied to a LightningElement class — a bare module cannot navigate
 * on its own. That keeps this module free of component state while still owning the behaviour.
 */
import { NavigationMixin } from 'lightning/navigation';

export const NAVIGATION_KIND_RECORD = 'record';
export const NAVIGATION_KIND_SETUP_PAGE = 'setupPage';
export const NAVIGATION_KIND_UNSUPPORTED = 'unsupported';

/**
 * Navigates using an already-resolved target.
 *
 * Returns a result object rather than throwing or silently failing, so the caller can surface an
 * honest message when a component genuinely cannot be opened. A dead click with no feedback is
 * exactly the kind of thing that makes a product feel broken, so "unsupported" is treated as a
 * real outcome to communicate, not an error to swallow.
 *
 * @param {LightningElement} navigator a component built with NavigationMixin
 * @param {object} target an OI_NavigationTargetDTO shape from Apex
 * @returns {{navigated: boolean, message: string|null}}
 */
export function navigateToTarget(navigator, target) {
    if (!navigator || !target) {
        return { navigated: false, message: 'There is nothing to open here.' };
    }
    if (target.kind === NAVIGATION_KIND_UNSUPPORTED) {
        return { navigated: false, message: target.reason || 'This component cannot be opened directly.' };
    }
    if (target.kind === NAVIGATION_KIND_RECORD) {
        if (!target.recordId) {
            return { navigated: false, message: 'This record could not be identified.' };
        }
        navigator[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: target.recordId,
                objectApiName: target.objectApiName,
                actionName: 'view'
            }
        });
        return { navigated: true, message: null };
    }
    if (target.kind === NAVIGATION_KIND_SETUP_PAGE) {
        if (!target.url) {
            return { navigated: false, message: 'This component cannot be opened directly.' };
        }
        /**
         * standard__webPage with a RELATIVE url — never an absolute host. Setup routes have no
         * dedicated NavigationMixin page type, and hardcoding a My Domain would break the moment
         * the package is installed anywhere else, so a relative path is both the supported and
         * the only package-safe option.
         */
        navigator[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: target.url }
        });
        /** A caveat is not a failure: navigation happened, but the destination is a management screen rather than the exact component, and the user deserves to know which. */
        return { navigated: true, message: target.reason || null };
    }
    return { navigated: false, message: 'This component cannot be opened directly.' };
}

/** True when a target will actually go somewhere — lets a caller render a row as plainly non-clickable instead of offering a click that does nothing. */
export function isNavigable(target) {
    return !!target && target.kind !== NAVIGATION_KIND_UNSUPPORTED;
}
