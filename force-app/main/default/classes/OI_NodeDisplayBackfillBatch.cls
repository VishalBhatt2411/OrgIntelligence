/**
 * Purpose: A one-time, manually-invoked maintenance operation — NOT a Service-layer pattern
 *          to be reused — correcting two derived/display fields on already-scanned current
 *          CustomObject/CustomField nodes that a code-level ingestion bug (fixed in
 *          OI_MutationGenerator/OI_ObjectScanner) never applied to, because the affected
 *          components' underlying Salesforce metadata has not changed since they were last
 *          scanned: (1) Label__c was written as the API name instead of the friendly
 *          Describe label already captured in Attributes_Json__c.label; (2) CustomObject
 *          Attributes_Json__c predates the namespace attribute OI_ObjectScanner now captures.
 * Responsibilities: Read-only inspect + targeted UPDATE of exactly the fields that were
 *                    mis-derived, on the existing current row, by its existing Id — never an
 *                    insert, never a version bump.
 * Dependencies: OI_JsonUtil, OI_ChecksumUtil, OI_ComponentKeyUtil, OI_LoggerService.
 * Limitations (deliberate, and why this deviates from the platform's normal immutable-
 *              versioning rule — GraphEngine.md §2, ADR-0014, GraphRepository.md §6/§11,
 *              CodingStandards.md §4 — which every other write path in this codebase
 *              follows without exception):
 *              - This is a correction of how a past scan's OWN observation was translated
 *                into storage, not a new observation of the org's metadata. The org's
 *                metadata did not change; inserting a synthetic new version here would
 *                misrepresent scan history — implying a metadata change occurred on the
 *                backfill's run date that never actually happened. An in-place correction of
 *                exactly the two known-wrong fields is the more historically honest choice.
 *              - Checksum__c is recomputed via the same OI_ChecksumUtil formula the live
 *                Scanner uses ONLY when Attributes_Json__c content itself changes (the
 *                namespace addition) — so a future real scan correctly sees "no change" for
 *                an object whose metadata genuinely has not changed, instead of spuriously
 *                creating a redundant version on its next run. Label__c is not itself part
 *                of the checksum formula (it always was, and remains, computed purely from
 *                componentKind + fullyQualifiedName + attributes), so a label-only
 *                correction never touches Checksum__c.
 *              - Idempotent by construction: a second run finds attributes already
 *                containing 'namespace' and Label__c already matching attributes.label, so
 *                it updates nothing. Never inserts, so it can never duplicate a Node_Key__c.
 *              - Scoped to Is_Current__c = true rows of exactly the two affected typeKeys —
 *                never touches ApexClass nodes (no separate friendly label ever existed for
 *                that componentKind), non-current/historical versions, or any edge.
 */
public without sharing class OI_NodeDisplayBackfillBatch implements Database.Batchable<SObject>, Database.Stateful {
    private static final String OBJECT_TYPE_KEY = 'SalesforceMetadata.CustomObject';
    private static final String FIELD_TYPE_KEY = 'SalesforceMetadata.CustomField';
    private static final String OBJECT_COMPONENT_KIND = 'CustomObject';

    public Integer nodesInspected = 0;
    public Integer nodesUpdated = 0;

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator(
            [
                SELECT Id, Node_Type__c, Secondary_Key__c, Label__c, Attributes_Json__c, Checksum__c
                FROM OI_Graph_Node__c
                WHERE Is_Current__c = true
                AND Node_Type__c IN (:OBJECT_TYPE_KEY, :FIELD_TYPE_KEY)
            ]
        );
    }

    public void execute(Database.BatchableContext context, List<OI_Graph_Node__c> scope) {
        List<OI_Graph_Node__c> toUpdate = new List<OI_Graph_Node__c>();
        for (OI_Graph_Node__c node : scope) {
            nodesInspected++;
            Boolean needsUpdate = false;
            Map<String, Object> attributes = OI_JsonUtil.toMap(node.Attributes_Json__c);

            Object friendlyLabel = attributes.get('label');
            if (friendlyLabel instanceof String && String.isNotBlank((String) friendlyLabel) && node.Label__c != (String) friendlyLabel) {
                node.Label__c = (String) friendlyLabel;
                needsUpdate = true;
            }

            if (node.Node_Type__c == OBJECT_TYPE_KEY && !attributes.containsKey('namespace')) {
                Boolean isCustomComponent = attributes.get('custom') == true;
                attributes.put('namespace', isCustomComponent ? OI_ComponentKeyUtil.extractNamespaceFromApiName(node.Secondary_Key__c) : null);
                node.Attributes_Json__c = OI_JsonUtil.toJson(attributes);
                node.Checksum__c = OI_ChecksumUtil.computeChecksum(OBJECT_COMPONENT_KIND, node.Secondary_Key__c, attributes);
                needsUpdate = true;
            }

            if (needsUpdate) {
                toUpdate.add(node);
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
            nodesUpdated += toUpdate.size();
        }
    }

    public void finish(Database.BatchableContext context) {
        new OI_LoggerService()
            .info(
                'OI_NodeDisplayBackfillBatch complete. Inspected=' + nodesInspected + ', Updated=' + nodesUpdated,
                'OI_NodeDisplayBackfillBatch',
                context.getJobId()
            );
    }
}
