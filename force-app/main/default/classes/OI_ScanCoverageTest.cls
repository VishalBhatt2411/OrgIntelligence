/**
 * Purpose: Verifies the scan-coverage model — that each Scanner declares an honest coverage
 *          status, that the three statuses stay semantically distinct, and that coverage
 *          reporting degrades to a no-op rather than throwing where the persistence fields are
 *          not visible in the running org.
 *
 * Why the status DISTINCTION is worth testing rather than just the presence of a status:
 * Partial and Degraded both mean "incomplete", but only Degraded is actionable by an admin and
 * only Partial is a permanent product boundary. Collapsing them would send users hunting for a
 * misconfiguration that does not exist, so these tests assert the specific status each Scanner
 * reports, not merely that some status was set.
 */
@isTest
private class OI_ScanCoverageTest {
    @isTest
    static void testCompleteCoverageCarriesNoReasonBecauseThereIsNothingToExplain() {
        OI_ScanCoverage coverage = OI_ScanCoverage.complete(12);

        System.assertEquals(OI_ScanCoverage.STATUS_COMPLETE, coverage.status);
        System.assertEquals(null, coverage.reason, 'Complete coverage must not carry a reason — a reason implies something is missing.');
        System.assertEquals(12, coverage.relationshipsDiscovered);
        System.assertEquals(true, coverage.isComplete());
    }

    @isTest
    static void testPartialAndDegradedAreDistinctAndBothCarryAReason() {
        OI_ScanCoverage partial = OI_ScanCoverage.partial(5, 'Internals not reachable without Tooling API.');
        OI_ScanCoverage degraded = OI_ScanCoverage.degraded(0, 'Source unavailable to the scanning user.');

        System.assertEquals(OI_ScanCoverage.STATUS_PARTIAL, partial.status);
        System.assertEquals(OI_ScanCoverage.STATUS_DEGRADED, degraded.status);
        System.assertNotEquals(partial.status, degraded.status, 'Partial (permanent boundary) and Degraded (situational failure) must never collapse into one status.');
        System.assert(String.isNotBlank(partial.reason), 'Partial coverage must explain what it does not cover.');
        System.assert(String.isNotBlank(degraded.reason), 'Degraded coverage must explain why this run fell short.');
        System.assertEquals(false, partial.isComplete());
        System.assertEquals(false, degraded.isComplete());
    }

    @isTest
    static void testNullRelationshipCountDefaultsToZeroRatherThanNull() {
        System.assertEquals(0, OI_ScanCoverage.complete(null).relationshipsDiscovered, 'A null count must normalise to zero so consumers never have to null-check it.');
    }

    /**
     * A batch built without an explicit coverage must default to Complete — the correct reading
     * for the structural scanners (Object/Field), which have no degradable extraction step, and
     * for the chunked-ingest paths that rebuild a batch purely to carry a slice of already-
     * discovered data.
     */
    @isTest
    static void testDiscoveryBatchDefaultsToCompleteCoverageWhenNoneIsDeclared() {
        OI_DiscoveryBatch batch = new OI_DiscoveryBatch(null, 'CustomObject', new List<OI_DiscoveredComponent>(), new List<OI_DiscoveredRelationship>(), true, 1);

        System.assertNotEquals(null, batch.coverage, 'Coverage must never be null — consumers read it unconditionally.');
        System.assertEquals(OI_ScanCoverage.STATUS_COMPLETE, batch.coverage.status);
    }

    @isTest
    static void testDiscoveryBatchPreservesAnExplicitlyDeclaredCoverage() {
        OI_DiscoveryBatch batch = new OI_DiscoveryBatch(
            null,
            'ApexClass',
            new List<OI_DiscoveredComponent>(),
            new List<OI_DiscoveredRelationship>(),
            true,
            1,
            OI_ScanCoverage.degraded(0, 'Apex source unavailable.')
        );

        System.assertEquals(OI_ScanCoverage.STATUS_DEGRADED, batch.coverage.status);
        System.assertEquals('Apex source unavailable.', batch.coverage.reason);
    }

    /**
     * The Apex scanner must report PARTIAL rather than COMPLETE even on a fully successful run:
     * a bare-identifier heuristic genuinely cannot see dynamic Apex or interface indirection, so
     * claiming Complete would overstate what the data supports. This is the difference between a
     * product that is trusted and one that is merely confident.
     */
    @isTest
    static void testApexClassScannerNeverClaimsCompleteCoverage() {
        OI_DiscoveryBatch batch = new OI_ApexClassScanner().scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        System.assertNotEquals(
            OI_ScanCoverage.STATUS_COMPLETE,
            batch.coverage.status,
            'A name-matching heuristic must never report Complete coverage — it cannot see dynamic Apex or interface indirection.'
        );
        System.assert(String.isNotBlank(batch.coverage.reason), 'The scanner must state what its heuristic cannot detect.');
    }

    /** Flow coverage is a permanent boundary of FlowDefinitionView, not a failure — so it must be Partial, and its reason must name what is missing rather than being a vague shrug. */
    @isTest
    static void testFlowScannerReportsPartialAndNamesWhatItCannotSee() {
        OI_DiscoveryBatch batch = new OI_FlowScanner().scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        System.assertEquals(OI_ScanCoverage.STATUS_PARTIAL, batch.coverage.status, 'Flow internals are an unreachable boundary, not a degraded run.');
        System.assert(batch.coverage.reason.containsIgnoreCase('Tooling API'), 'The reason must name the concrete blocker. Got: ' + batch.coverage.reason);
    }

    /** Permission-set field-level grants are a named gap; the reason must say so explicitly so "which permission sets expose this field" reads as unsupported rather than as an empty answer. */
    @isTest
    static void testPermissionSetScannerReportsFieldLevelGrantsAsANamedGap() {
        OI_DiscoveryBatch batch = new OI_PermissionSetScanner().scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        System.assertEquals(OI_ScanCoverage.STATUS_PARTIAL, batch.coverage.status);
        System.assert(batch.coverage.reason.containsIgnoreCase('field-level'), 'The reason must name the field-level grant gap. Got: ' + batch.coverage.reason);
    }

    @isTest
    static void testApexTriggerScannerDeclaresCoverage() {
        OI_DiscoveryBatch batch = new OI_ApexTriggerScanner().scan(new OI_ScanContext(null, 200, null, 'SOQL'));

        System.assertNotEquals(null, batch.coverage);
        System.assertNotEquals(OI_ScanCoverage.STATUS_COMPLETE, batch.coverage.status, 'Trigger reference extraction shares the same heuristic limits as Apex classes.');
    }

    /**
     * Coverage persistence must be best-effort: in an org where the coverage fields are not
     * visible (a reproduced condition — see OI_ScanCoverageFields), writing must be a silent
     * no-op rather than an exception, because a scan's real payload must never be lost over a
     * diagnostic field.
     */
    @isTest
    static void testCoverageWritesNeverThrowRegardlessOfFieldAvailability() {
        OI_Scan_Run__c run = new OI_Scan_Run__c(Status__c = 'Running', Scan_Type__c = 'Full');
        insert run;
        OI_Scan_Task__c task = new OI_Scan_Task__c(Scan_Run__c = run.Id, Metadata_Type__c = 'ApexClass', Status__c = 'Running');
        insert task;

        Test.startTest();
        OI_ScanCoverageFields.writeCoverage(task.Id, OI_ScanCoverage.degraded(0, 'Apex source unavailable.'));
        OI_ScanCoverageFields.addSkipped(task.Id, 3);
        Boolean limitations = OI_ScanCoverageFields.hasLimitations(run.Id);
        Test.stopTest();

        System.assertNotEquals(null, limitations, 'hasLimitations must return a real boolean in either availability mode, never null.');
    }

    @isTest
    static void testCoverageHelpersIgnoreNullAndNonPositiveInput() {
        Test.startTest();
        OI_ScanCoverageFields.writeCoverage(null, OI_ScanCoverage.complete(0));
        OI_ScanCoverageFields.addSkipped(null, 5);
        Test.stopTest();

        System.assertEquals(false, OI_ScanCoverageFields.hasLimitations(null), 'A null run id cannot have limitations and must not query.');
    }
}
