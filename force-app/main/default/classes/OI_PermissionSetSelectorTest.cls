@IsTest
private class OI_PermissionSetSelectorTest {
  @IsTest
  static void testSelectPermissionSetsBoundedRespectsCeilingAndIncludesProfileShadowRows() {
    List<PermissionSet> bounded = new OI_PermissionSetSelector()
      .selectPermissionSetsBounded(3);
    System.assert(bounded.size() <= 3, 'The ceiling must never be exceeded.');

    List<PermissionSet> unbounded = new OI_PermissionSetSelector()
      .selectPermissionSetsBounded(500);
    Boolean sawProfileShadowRow = false;
    for (PermissionSet permissionSet : unbounded) {
      if (permissionSet.IsOwnedByProfile == true) {
        sawProfileShadowRow = true;
        break;
      }
    }
    System.assert(
      sawProfileShadowRow,
      'Unlike the graph scanner, this Selector must include profile shadow rows — every org has at least one Profile.'
    );
  }

  @IsTest
  static void testSelectPermissionSetsBoundedDefaultsNonPositiveCeiling() {
    List<PermissionSet> results = new OI_PermissionSetSelector()
      .selectPermissionSetsBounded(0);
    System.assert(
      results.size() <= 500,
      'A non-positive ceiling must fall back to the default of 500.'
    );
  }

  @IsTest
  static void testCountAssigneesByPermissionSetIdsReflectsARealAssignment() {
    PermissionSet permissionSet = new PermissionSet(
      Name = 'OI_Test_Sel_Assignee',
      Label = 'OI Test Sel Assignee'
    );
    insert permissionSet;
    insert new PermissionSetAssignment(
      AssigneeId = UserInfo.getUserId(),
      PermissionSetId = permissionSet.Id
    );

    Map<Id, Integer> counts = new OI_PermissionSetSelector()
      .countAssigneesByPermissionSetIds(new Set<Id>{ permissionSet.Id });

    System.assertEquals(1, counts.get(permissionSet.Id));
  }

  @IsTest
  static void testCountAssigneesByPermissionSetIdsHandlesEmptySetWithoutQuerying() {
    Map<Id, Integer> counts = new OI_PermissionSetSelector()
      .countAssigneesByPermissionSetIds(new Set<Id>());
    System.assertEquals(0, counts.size());
  }

  @IsTest
  static void testCountBroadObjectGrantsByPermissionSetIdsOnlyCountsViewAllOrModifyAllRows() {
    PermissionSet permissionSet = new PermissionSet(
      Name = 'OI_Test_Sel_Broad',
      Label = 'OI Test Sel Broad'
    );
    insert permissionSet;
    insert new List<ObjectPermissions>{
      new ObjectPermissions(
        ParentId = permissionSet.Id,
        SobjectType = 'Account',
        PermissionsRead = true,
        PermissionsViewAllRecords = true
      ),
      new ObjectPermissions(
        ParentId = permissionSet.Id,
        SobjectType = 'Contact',
        PermissionsRead = true,
        PermissionsEdit = true
      )
    };

    Map<Id, Integer> counts = new OI_PermissionSetSelector()
      .countBroadObjectGrantsByPermissionSetIds(
        new Set<Id>{ permissionSet.Id }
      );

    System.assertEquals(
      1,
      counts.get(permissionSet.Id),
      'Only the View All Records grant on Account is broad; the Contact row (read/edit only) must be excluded.'
    );
  }

  @IsTest
  static void testCountBroadObjectGrantsByPermissionSetIdsHandlesEmptySetWithoutQuerying() {
    Map<Id, Integer> counts = new OI_PermissionSetSelector()
      .countBroadObjectGrantsByPermissionSetIds(new Set<Id>());
    System.assertEquals(0, counts.size());
  }

  @IsTest
  static void testSelectSensitiveObjectGrantPermissionSetIdsOnlyMatchesNamedSensitiveObjects() {
    PermissionSet permissionSet = new PermissionSet(
      Name = 'OI_Test_Sel_Sensitive',
      Label = 'OI Test Sel Sensitive'
    );
    insert permissionSet;
    insert new List<ObjectPermissions>{
      new ObjectPermissions(
        ParentId = permissionSet.Id,
        SobjectType = 'Account',
        PermissionsRead = true,
        PermissionsViewAllRecords = true
      ),
      new ObjectPermissions(
        ParentId = permissionSet.Id,
        SobjectType = 'Opportunity',
        PermissionsRead = true,
        PermissionsCreate = true,
        PermissionsEdit = true,
        PermissionsDelete = true,
        PermissionsViewAllRecords = true,
        PermissionsModifyAllRecords = true
      )
    };

    Set<Id> matches = new OI_PermissionSetSelector()
      .selectSensitiveObjectGrantPermissionSetIds(
        new Set<Id>{ permissionSet.Id },
        new Set<String>{ 'Account', 'Contact' }
      );

    System.assert(
      matches.contains(permissionSet.Id),
      'The broad Account grant must match — Account is in the sensitive object set.'
    );
  }

  @IsTest
  static void testSelectSensitiveObjectGrantPermissionSetIdsHandlesEmptyInputsWithoutQuerying() {
    Set<Id> matches = new OI_PermissionSetSelector()
      .selectSensitiveObjectGrantPermissionSetIds(
        new Set<Id>(),
        new Set<String>{ 'Account' }
      );
    System.assertEquals(0, matches.size());

    Set<Id> matchesNoSensitiveNames = new OI_PermissionSetSelector()
      .selectSensitiveObjectGrantPermissionSetIds(
        new Set<Id>{ UserInfo.getUserId() },
        new Set<String>()
      );
    System.assertEquals(0, matchesNoSensitiveNames.size());
  }
}
