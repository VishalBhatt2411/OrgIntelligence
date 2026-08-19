/**
 * Purpose: Subscribes to OI_Log_Event__e to persist structured logs asynchronously
 *          (Architecture.md §13).
 * Responsibilities: Validate context and delegate — no business logic here
 *                    (CLAUDE.md §Trigger Rules, CodingStandards.md §3).
 */
trigger OI_LogEventTrigger on OI_Log_Event__e(after insert) {
    new OI_LogEventTriggerHandler().handleAfterInsert(Trigger.new);
}
