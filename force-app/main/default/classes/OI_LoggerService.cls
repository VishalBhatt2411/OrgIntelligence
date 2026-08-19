/**
 * Purpose: The single entry point for structured logging across every layer
 *          (Architecture.md §13) — no class writes logs by any other means.
 * Responsibilities: Publish OI_Log_Event__e so logging is decoupled from the caller's
 *                    transaction (never consumes the caller's DML/CPU budget or risks a
 *                    rollback on a logging failure). Filters by the configured
 *                    Log_Level__c threshold before publishing.
 * Dependencies: OI_SettingsService (for the configured threshold).
 * Limitations: Does not itself write OI_Log__c — that happens asynchronously via
 *              OI_LogEventTrigger -> OI_LogEventTriggerHandler -> OI_LogRepository.
 */
public class OI_LoggerService {
    private static final Map<String, Integer> LEVEL_RANK = new Map<String, Integer>{ 'DEBUG' => 0, 'INFO' => 1, 'WARN' => 2, 'ERROR' => 3 };

    public void debug(String message, String source, String correlationId) {
        log('DEBUG', message, source, correlationId, null);
    }

    public void info(String message, String source, String correlationId) {
        log('INFO', message, source, correlationId, null);
    }

    public void warn(String message, String source, String correlationId) {
        log('WARN', message, source, correlationId, null);
    }

    public void error(String message, String source, String correlationId, String stackTrace) {
        log('ERROR', message, source, correlationId, stackTrace);
    }

    private void log(String level, String message, String source, String correlationId, String stackTrace) {
        if (!meetsThreshold(level)) {
            return;
        }
        EventBus.publish(
            new OI_Log_Event__e(
                Level__c = level,
                Message__c = message,
                Source__c = source,
                Correlation_Id__c = correlationId,
                Stack_Trace__c = stackTrace
            )
        );
    }

    private Boolean meetsThreshold(String level) {
        String configuredLevel = new OI_SettingsService().getSettings().Log_Level__c;
        Integer threshold = String.isBlank(configuredLevel) || !LEVEL_RANK.containsKey(configuredLevel) ? LEVEL_RANK.get('WARN') : LEVEL_RANK.get(configuredLevel);
        Integer rank = LEVEL_RANK.containsKey(level) ? LEVEL_RANK.get(level) : LEVEL_RANK.get('INFO');
        return rank >= threshold;
    }
}
