@isTest
private class OI_RecordHierarchyServiceTest {
  @isTest
  static void testGetRecordFragmentResolvesAParentLookupToItsRealTargetRecord() {
    Account parent = new Account(Name = 'Parent Co');
    insert parent;
    Contact child = new Contact(LastName = 'Kid', AccountId = parent.Id);
    insert child;

    OI_RecordFragmentDTO fragment = new OI_RecordHierarchyService()
      .getRecordFragment('Contact', child.Id);

    /**
     * Not asserting an exact node/edge count here: every record also has an OwnerId
     * (and Created/LastModifiedById) lookup to a User, which legitimately resolves to
     * its own parent node too — this test's job is only to prove the Account lookup
     * specifically resolves correctly, not to enumerate every populated reference field.
     */
    Boolean foundParent = false;
    for (OI_NodeSummaryDTO node : fragment.nodes) {
      if (node.label == 'Parent Co') {
        foundParent = true;
        System.assertEquals('SalesforceRecord.Account', node.typeKey);
      }
    }
    System.assert(
      foundParent,
      'The parent Account must appear as a resolved node, not just a raw Id.'
    );

    Boolean foundParentEdge = false;
    for (OI_EdgeSummaryDTO edge : fragment.edges) {
      if (
        edge.typeKey == 'SalesforceRecord.LOOKUP_TO' &&
        edge.targetNodeKey.contains('Account')
      ) {
        foundParentEdge = true;
        System.assertEquals(
          'AccountId',
          edge.viaFieldApiName,
          'Record intelligence must retain which accessible lookup field created the relationship.'
        );
      }
    }
    System.assert(
      foundParentEdge,
      'A LOOKUP_TO edge from the Contact to its Account must exist.'
    );
    System.assertNotEquals(
      null,
      fragment.recordOverview,
      'The center record must carry a dedicated live overview payload.'
    );
    System.assertNotEquals(
      null,
      fragment.recordOverview.ownerName,
      'Owner should be resolved when OwnerId and the target User are accessible.'
    );
    System.assertNotEquals(
      null,
      fragment.recordOverview.createdDate,
      'CreatedDate should be returned when FLS permits it.'
    );
    System.assertNotEquals(
      null,
      fragment.recordOverview.lastModifiedDate,
      'LastModifiedDate should be returned when FLS permits it.'
    );
  }

  /**
   * secondaryKey is what oiGraphNode renders as the card's visible caption line — it must
   * read as a clean "which Object is this" label (e.g. "Account"), never "Account
   * 001xx0000034567AAB". The raw Id is already carried in nodeKey and available on hover/
   * click; mixing it into the visible caption made every card on the canvas confusing to
   * tell apart by object type, which is the entire reason this field exists.
   */
  @isTest
  static void testGetRecordFragmentSecondaryKeyIsTheObjectNameAloneNeverTheRawRecordId() {
    Account parent = new Account(Name = 'Parent Co');
    insert parent;
    Contact child = new Contact(LastName = 'Kid', AccountId = parent.Id);
    insert child;

    OI_RecordFragmentDTO fragment = new OI_RecordHierarchyService()
      .getRecordFragment('Contact', child.Id);

    Boolean checkedCenter = false;
    Boolean checkedParent = false;
    for (OI_NodeSummaryDTO node : fragment.nodes) {
      if (node.label == child.LastName) {
        System.assertEquals('Contact', node.secondaryKey);
        checkedCenter = true;
      } else if (node.label == 'Parent Co') {
        System.assertEquals('Account', node.secondaryKey);
        checkedParent = true;
      }
    }
    System.assert(
      checkedCenter,
      'Expected the center Contact node to be present.'
    );
    System.assert(
      checkedParent,
      'Expected the resolved parent Account node to be present.'
    );
  }

  /**
   * Asserts on the two expected Contact node keys rather than a blind CHILD_OF count: a
   * target org can carry other child relationships with real rows (e.g. managed-package
   * automation that creates related records on Account insert), which would inflate a plain
   * count and make the test depend on org configuration.
   */
  @isTest
  static void testGetRecordFragmentResolvesChildRelationships() {
    Account parent = new Account(Name = 'Parent Co');
    insert parent;
    Contact kidOne = new Contact(LastName = 'Kid One', AccountId = parent.Id);
    Contact kidTwo = new Contact(LastName = 'Kid Two', AccountId = parent.Id);
    insert new List<Contact>{ kidOne, kidTwo };

    OI_RecordFragmentDTO fragment = new OI_RecordHierarchyService()
      .getRecordFragment('Account', parent.Id);

    Set<String> expectedChildKeys = new Set<String>{
      OI_RecordSchemaUtil.recordNodeKey('Contact', kidOne.Id),
      OI_RecordSchemaUtil.recordNodeKey('Contact', kidTwo.Id)
    };
    Set<String> foundChildKeys = new Set<String>();
    for (OI_EdgeSummaryDTO edge : fragment.edges) {
      if (
        edge.typeKey == 'SalesforceRecord.CHILD_OF' &&
        expectedChildKeys.contains(edge.targetNodeKey)
      ) {
        foundChildKeys.add(edge.targetNodeKey);
        System.assertEquals(
          'AccountId',
          edge.viaFieldApiName,
          'Child edges must retain the relationship field used to reach the center record.'
        );
      }
    }
    System.assertEquals(
      expectedChildKeys,
      foundChildKeys,
      'Both child Contacts must appear as CHILD_OF edges from the Account.'
    );
  }

  @isTest
  static void testGetRecordFragmentForANonExistentRecordReturnsAnEmptyFragmentNotAnError() {
    Account throwaway = new Account(Name = 'Throwaway');
    insert throwaway;
    Id fakeId = throwaway.Id;
    delete throwaway;

    OI_RecordFragmentDTO fragment = new OI_RecordHierarchyService()
      .getRecordFragment('Account', fakeId);

    System.assertEquals(0, fragment.nodes.size());
    System.assertEquals(false, fragment.hasMore);
  }

  @isTest
  static void testGetRecordFragmentWithBlankRecordIdThrowsValidationException() {
    try {
      new OI_RecordHierarchyService().getRecordFragment('Account', null);
      System.assert(
        false,
        'Expected OI_ValidationException for a blank record Id.'
      );
    } catch (OI_ValidationException e) {
      System.assert(true);
    }
  }

  @isTest
  static void testGetRecordFragmentForAnUnknownObjectThrowsValidationException() {
    try {
      new OI_RecordHierarchyService()
        .getRecordFragment('Definitely_Not_Real__x', '001000000000000AAA');
      System.assert(
        false,
        'Expected OI_ValidationException for an unknown object.'
      );
    } catch (OI_ValidationException e) {
      System.assert(true);
    }
  }

  @isTest
  static void testGetRecordFragmentRejectsMalformedRecordIdBeforeQuerying() {
    try {
      new OI_RecordHierarchyService()
        .getRecordFragment('Account', 'not-a-salesforce-id');
      System.assert(
        false,
        'Expected OI_ValidationException for a malformed Id.'
      );
    } catch (OI_ValidationException e) {
      System.assertEquals('The record Id is not valid.', e.getMessage());
    }
  }

  @isTest
  static void testGetRecordFragmentRejectsAnIdFromAnotherObjectType() {
    Contact contact = new Contact(LastName = 'Wrong object');
    insert contact;

    try {
      new OI_RecordHierarchyService().getRecordFragment('Account', contact.Id);
      System.assert(
        false,
        'Expected OI_ValidationException for an object/Id mismatch.'
      );
    } catch (OI_ValidationException e) {
      System.assertEquals(
        'The record Id does not belong to Account.',
        e.getMessage()
      );
    }
  }
}
