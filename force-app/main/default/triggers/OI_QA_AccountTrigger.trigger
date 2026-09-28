/**
 * QA-only trigger created to verify the Object Intelligence Panel's Automation/Code sections
 * render real Apex Trigger data for a standard object. No business logic — safe to remove once
 * the panel's Automation/Code rendering has been confirmed.
 */
trigger OI_QA_AccountTrigger on Account(before insert, before update) {
}
