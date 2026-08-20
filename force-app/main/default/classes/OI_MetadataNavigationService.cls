/**
 * Purpose: The single place that knows how to reach a Salesforce metadata component's real
 *          configuration screen — resolving durable identifiers so no LWC ever assembles a Setup
 *          URL or assumes an API name is addressable.
 * Responsibilities: Given a graph nodeKey, resolve a navigation target (or an honest reason why
 *                    one does not exist).
 * Dependencies: OI_ComponentKeyUtil, EntityDefinition, FieldDefinition, ApexClass, ApexTrigger,
 *               PermissionSet, OI_RecordSchemaUtil.
 *
 * The identifier traps this class exists to absorb, each verified against a real org rather than
 * assumed:
 *   - A CUSTOM object's Setup address is its EntityDefinition DurableId (`01If6000002DBBv`), not
 *     its API name. A STANDARD object's happens to equal its API name — which is exactly what
 *     makes hand-built URLs so dangerous: they work in testing on Account and fail on every
 *     custom object.
 *   - A relationship FIELD's DurableId drops the "Id" suffix: `Account.OwnerId` is addressed as
 *     `Account.Owner`. Building the URL from the API name breaks precisely on lookup fields,
 *     which are the ones users most want to inspect.
 *   - Apex classes, triggers and permission sets are addressed by record Id, which the graph does
 *     not store (it stores names), so each needs a resolving query.
 *
 * Resolution is per-click and single-target by design: this runs when a user clicks one row, not
 * in a loop over a rendered table, so a focused query per click is the right trade against
 * carrying identifiers for thousands of unclicked rows.
 *
 * Limitations: Flow has no supported, stable direct-navigation identifier available without
 *              Tooling API — FlowDefinitionView exposes a developer-name DurableId, not the id
 *              Flow Builder addresses. Rather than emit a link that may 404, Flow resolves to the
 *              Flows management list with an explicit caveat (the user's own instruction: never
 *              invent broken links). Setup URL shapes below are the documented Lightning
 *              patterns but have NOT been browser-verified by this class's author; they are
 *              flagged for manual confirmation rather than asserted as working.
 */
public with sharing class OI_MetadataNavigationService {
    private static final String COMPONENT_KIND_OBJECT = 'CustomObject';
    private static final String COMPONENT_KIND_FIELD = 'CustomField';
    private static final String COMPONENT_KIND_APEX_CLASS = 'ApexClass';
    private static final String COMPONENT_KIND_APEX_TRIGGER = 'ApexTrigger';
    private static final String COMPONENT_KIND_FLOW = 'Flow';
    private static final String COMPONENT_KIND_PERMISSION_SET = 'PermissionSet';
    private static final String TYPE_KEY_PREFIX = 'SalesforceMetadata.';

    /**
     * Resolves where a node leads. Accepts a graph nodeKey plus the type/secondaryKey the caller
     * already holds, rather than re-reading the node — the caller (a drill-down row or a graph
     * card) always has both, and re-querying the node to learn what it is would double the cost
     * of every click for no new information.
     */
    public OI_NavigationTargetDTO resolve(String typeKey, String apiName) {
        if (String.isBlank(typeKey) || String.isBlank(apiName)) {
            return OI_NavigationTargetDTO.unsupported('This component does not carry enough information to open it.');
        }
        /** A record node (Record Analysis) is the one case with genuine first-class navigation — handled before metadata kinds because its type key follows a different convention entirely. */
        OI_NavigationTargetDTO recordTarget = resolveRecordTarget(typeKey, apiName);
        if (recordTarget != null) {
            return recordTarget;
        }

        String componentKind = typeKey.startsWith(TYPE_KEY_PREFIX) ? typeKey.substring(TYPE_KEY_PREFIX.length()) : typeKey;
        if (COMPONENT_KIND_OBJECT.equals(componentKind)) {
            return resolveObject(apiName);
        }
        if (COMPONENT_KIND_FIELD.equals(componentKind)) {
            return resolveField(apiName);
        }
        if (COMPONENT_KIND_APEX_CLASS.equals(componentKind)) {
            return resolveApexClass(apiName);
        }
        if (COMPONENT_KIND_APEX_TRIGGER.equals(componentKind)) {
            return resolveApexTrigger(apiName);
        }
        if (COMPONENT_KIND_PERMISSION_SET.equals(componentKind)) {
            return resolvePermissionSet(apiName);
        }
        if (COMPONENT_KIND_FLOW.equals(componentKind)) {
            return resolveFlow();
        }
        return OI_NavigationTargetDTO.unsupported('Opening ' + componentKind + ' components is not supported yet.');
    }

    /** A Record Analysis node carries an object API name and a record id; both are needed for standard__recordPage. */
    private OI_NavigationTargetDTO resolveRecordTarget(String typeKey, String apiName) {
        if (!typeKey.startsWith('SalesforceRecord.')) {
            return null;
        }
        String objectApiName = typeKey.substring('SalesforceRecord.'.length());
        if (String.isBlank(objectApiName) || !(apiName instanceof Id)) {
            return OI_NavigationTargetDTO.unsupported('This record could not be identified well enough to open it.');
        }
        return OI_NavigationTargetDTO.record(apiName, objectApiName, 'Open record');
    }

    /** Object Manager detail page, addressed by EntityDefinition DurableId (never the API name — see this class's doc comment). */
    private OI_NavigationTargetDTO resolveObject(String objectApiName) {
        List<EntityDefinition> definitions = [SELECT DurableId FROM EntityDefinition WHERE QualifiedApiName = :objectApiName LIMIT 1];
        if (definitions.isEmpty()) {
            return OI_NavigationTargetDTO.unsupported('This object is no longer present in the org, or is not visible to you.');
        }
        return OI_NavigationTargetDTO.setupPage(
            '/lightning/setup/ObjectManager/' + definitions[0].DurableId + '/Details/view',
            'Open in Object Manager'
        );
    }

    /**
     * Fields & Relationships detail page. The field's own DurableId is `{entity}.{suffix}` and
     * the Setup URL wants that suffix, which for a relationship field is the RELATIONSHIP name
     * ("Owner"), not the API name ("OwnerId") — the specific trap this method exists to absorb.
     *
     * The incoming apiName is a field's scanned fullyQualifiedName, i.e. "Object.Field".
     */
    private OI_NavigationTargetDTO resolveField(String qualifiedFieldName) {
        List<String> parts = qualifiedFieldName.split('\\.');
        if (parts.size() < 2) {
            return OI_NavigationTargetDTO.unsupported('This field could not be matched to an object.');
        }
        String objectApiName = parts[0];
        String fieldApiName = parts[parts.size() - 1];

        List<FieldDefinition> definitions = [
            SELECT DurableId, EntityDefinitionId
            FROM FieldDefinition
            WHERE EntityDefinition.QualifiedApiName = :objectApiName AND QualifiedApiName = :fieldApiName
            LIMIT 1
        ];
        if (definitions.isEmpty()) {
            return OI_NavigationTargetDTO.unsupported('This field is no longer present in the org, or is not visible to you.');
        }
        String durableId = definitions[0].DurableId;
        String entityDurableId = definitions[0].EntityDefinitionId;
        /** DurableId is "{entityDurableId}.{suffix}"; the Setup route wants only the suffix. Derived by stripping the known prefix rather than by splitting on '.', because a custom object's durable id contains no dot but a qualified field name might. */
        String fieldSuffix = durableId.startsWith(entityDurableId + '.') ? durableId.substring(entityDurableId.length() + 1) : durableId;
        return OI_NavigationTargetDTO.setupPage(
            '/lightning/setup/ObjectManager/' + entityDurableId + '/FieldsAndRelationships/' + fieldSuffix + '/view',
            'Open field in Object Manager'
        );
    }

    private OI_NavigationTargetDTO resolveApexClass(String className) {
        String unqualified = unqualify(className);
        List<ApexClass> classes = [SELECT Id FROM ApexClass WHERE Name = :unqualified LIMIT 1];
        if (classes.isEmpty()) {
            return OI_NavigationTargetDTO.unsupported('This Apex class is no longer present in the org, or is not visible to you.');
        }
        return OI_NavigationTargetDTO.setupPage(
            '/lightning/setup/ApexClasses/page?address=%2F' + classes[0].Id,
            'Open Apex class'
        );
    }

    private OI_NavigationTargetDTO resolveApexTrigger(String triggerName) {
        String unqualified = unqualify(triggerName);
        List<ApexTrigger> triggers = [SELECT Id FROM ApexTrigger WHERE Name = :unqualified LIMIT 1];
        if (triggers.isEmpty()) {
            return OI_NavigationTargetDTO.unsupported('This trigger is no longer present in the org, or is not visible to you.');
        }
        return OI_NavigationTargetDTO.setupPage(
            '/lightning/setup/ApexTriggers/page?address=%2F' + triggers[0].Id,
            'Open trigger'
        );
    }

    private OI_NavigationTargetDTO resolvePermissionSet(String permissionSetName) {
        String unqualified = unqualify(permissionSetName);
        List<PermissionSet> permissionSets = [SELECT Id FROM PermissionSet WHERE Name = :unqualified LIMIT 1];
        if (permissionSets.isEmpty()) {
            return OI_NavigationTargetDTO.unsupported('This permission set is no longer present in the org, or is not visible to you.');
        }
        return OI_NavigationTargetDTO.setupPage(
            '/lightning/setup/PermSets/page?address=%2F' + permissionSets[0].Id,
            'Open permission set'
        );
    }

    /**
     * Flows land on the Flows management list, deliberately. Flow Builder is addressed by a flow
     * definition/version Id that no Apex-queryable object exposes (FlowDefinitionView's DurableId
     * is a developer name), so a direct link would be a guess. A working list page plus a stated
     * caveat is more useful than a link that may fail.
     */
    private OI_NavigationTargetDTO resolveFlow() {
        return OI_NavigationTargetDTO.setupPageWithCaveat(
            '/lightning/setup/Flows/home',
            'Open Flows list',
            'Salesforce does not expose a stable direct link to a single Flow without Tooling API access, so this opens the Flows list where you can select it.'
        );
    }

    /** Strips a namespace prefix so a name resolves against the local object, which stores Name without it. */
    private String unqualify(String name) {
        return name.contains('.') ? name.substringAfterLast('.') : name;
    }
}
