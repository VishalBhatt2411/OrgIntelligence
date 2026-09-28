import { LightningElement, api } from "lwc";
import getSetupLink from "@salesforce/apex/OI_TD_Controller.getSetupLink";

// Types that don't map to a specific Salesforce Setup page (org-wide findings, etc.)
const UNLINKABLE_TYPES = new Set(["Organization"]);

/**
 * "Open in Salesforce" icon button (reference: components/OpenInSalesforceButton.tsx).
 * Resolves the component's Setup URL server-side and opens it in a new tab.
 */
export default class OiTdOpenInSalesforce extends LightningElement {
  @api scanId;
  @api type;
  @api name;
  loading = false;

  get linkable() {
    return !UNLINKABLE_TYPES.has(this.type);
  }

  async handleClick(event) {
    event.stopPropagation();
    // Open the tab synchronously in the click handler so browsers don't treat the
    // later navigation (after the async lookup below) as a blocked popup.
    const tab = window.open("", "_blank");
    this.loading = true;
    try {
      const url = await getSetupLink({
        scanId: this.scanId,
        type: this.type,
        name: this.name
      });
      if (url && tab) {
        tab.location.href = url;
      } else {
        if (tab) tab.close();
        this.toast(
          "Couldn't find this component in the org (it may have been removed since the scan)",
          "error"
        );
      }
    } catch {
      if (tab) tab.close();
      this.toast("Couldn't open Salesforce Setup for this component", "error");
    } finally {
      this.loading = false;
    }
  }

  toast(message, variant) {
    this.dispatchEvent(
      new CustomEvent("toast", {
        detail: { message, variant },
        bubbles: true,
        composed: true
      })
    );
  }
}
