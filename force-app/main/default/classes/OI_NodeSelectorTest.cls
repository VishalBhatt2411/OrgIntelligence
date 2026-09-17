/**
 * Purpose: Verifies OI_NodeSelector's bulk, key-set-shaped reads and Is_Current__c
 *          centralization (CodingStandards.md §4).
 */
@isTest
private class OI_NodeSelectorTest {
  @isTest
  static void testSelectCurrentByKeysReturnsOnlyCurrentRows() {
    insert new List<OI_Graph_Node__c>{
      new OI_Graph_Node__c(
        Node_Key__c = 'n1',
        Node_Version_Key__c = 'n1::v1',
        Version_Number__c = 1,
        Node_Type__c = 'T',
        State__c = 'Active',
        Is_Current__c = false
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'n1',
        Node_Version_Key__c = 'n1::v2',
        Version_Number__c = 2,
        Node_Type__c = 'T',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'n2',
        Node_Version_Key__c = 'n2::v1',
        Version_Number__c = 1,
        Node_Type__c = 'T',
        State__c = 'Active',
        Is_Current__c = true
      )
    };
    List<OI_Graph_Node__c> results = new OI_NodeSelector()
      .selectCurrentByKeys(new Set<String>{ 'n1', 'n2' });
    System.assertEquals(2, results.size());
    for (OI_Graph_Node__c row : results) {
      System.assertEquals(true, row.Is_Current__c);
    }
  }

  @isTest
  static void testSelectCurrentByKeysEmptySetReturnsEmpty() {
    System.assertEquals(
      0,
      new OI_NodeSelector().selectCurrentByKeys(new Set<String>()).size()
    );
  }

  @isTest
  static void testSelectCurrentKeysByTypePagination() {
    List<OI_Graph_Node__c> rows = new List<OI_Graph_Node__c>();
    for (Integer i = 0; i < 5; i++) {
      rows.add(
        new OI_Graph_Node__c(
          Node_Key__c = 'p' + i,
          Node_Version_Key__c = 'p' + i + '::v1',
          Version_Number__c = 1,
          Node_Type__c = 'Paginated.Type',
          State__c = 'Active',
          Is_Current__c = true
        )
      );
    }
    insert rows;
    List<OI_Graph_Node__c> page1 = new OI_NodeSelector()
      .selectCurrentKeysByType('Paginated.Type', null, 2);
    System.assertEquals(2, page1.size());
    List<OI_Graph_Node__c> page2 = new OI_NodeSelector()
      .selectCurrentKeysByType(
        'Paginated.Type',
        page1[1].Node_Version_Key__c,
        2
      );
    System.assertEquals(2, page2.size());
    System.assertNotEquals(
      page1[0].Node_Version_Key__c,
      page2[0].Node_Version_Key__c
    );
  }

  @isTest
  static void testSelectCurrentByLabelOrSecondaryKeyPrefixMatchesEitherFieldCaseOfCurrentRowsOnly() {
    insert new List<OI_Graph_Node__c>{
      new OI_Graph_Node__c(
        Node_Key__c = 's1',
        Node_Version_Key__c = 's1::v1',
        Version_Number__c = 1,
        Node_Type__c = 'T',
        Label__c = 'Account',
        Secondary_Key__c = 'Account',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 's2',
        Node_Version_Key__c = 's2::v1',
        Version_Number__c = 1,
        Node_Type__c = 'T',
        Label__c = 'AccountContactRoles',
        Secondary_Key__c = 'AccountContactRoles',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 's3',
        Node_Version_Key__c = 's3::v1',
        Version_Number__c = 1,
        Node_Type__c = 'T',
        Label__c = 'Contact',
        Secondary_Key__c = 'Contact',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 's1',
        Node_Version_Key__c = 's1::v0',
        Version_Number__c = 0,
        Node_Type__c = 'T',
        Label__c = 'Account',
        Secondary_Key__c = 'Account',
        State__c = 'Stale',
        Is_Current__c = false
      )
    };
    List<OI_Graph_Node__c> results = new OI_NodeSelector()
      .selectCurrentByLabelOrSecondaryKeyPrefix('Account', 20);
    System.assertEquals(
      2,
      results.size(),
      'Only current rows matching the prefix (Account, AccountContactRoles) must be returned — Contact must not match, the Stale duplicate must not be returned.'
    );
  }

  @isTest
  static void testCountCurrentByTypeGroupsOnlyCurrentRowsWithinRequestedTypes() {
    insert new List<OI_Graph_Node__c>{
      new OI_Graph_Node__c(
        Node_Key__c = 'c1',
        Node_Version_Key__c = 'c1::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Health.TypeA',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'c2',
        Node_Version_Key__c = 'c2::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Health.TypeA',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'c3',
        Node_Version_Key__c = 'c3::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Health.TypeB',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'c4',
        Node_Version_Key__c = 'c4::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Health.TypeA',
        State__c = 'Stale',
        Is_Current__c = false
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'c5',
        Node_Version_Key__c = 'c5::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Health.Excluded',
        State__c = 'Active',
        Is_Current__c = true
      )
    };
    Map<String, Integer> counts = new OI_NodeSelector()
      .countCurrentByType(new Set<String>{ 'Health.TypeA', 'Health.TypeB' });
    System.assertEquals(
      2,
      counts.get('Health.TypeA'),
      'Only current rows of the requested type must be counted.'
    );
    System.assertEquals(1, counts.get('Health.TypeB'));
    System.assertEquals(
      false,
      counts.containsKey('Health.Excluded'),
      'A type not in the requested set must not appear, even if current rows of it exist.'
    );
  }

  @isTest
  static void testCountCurrentByTypeWithEmptySetReturnsEmptyMap() {
    System.assertEquals(
      0,
      new OI_NodeSelector().countCurrentByType(new Set<String>()).size()
    );
  }

  @isTest
  static void testBulkInsertAndSelect() {
    List<OI_Graph_Node__c> rows = new List<OI_Graph_Node__c>();
    Set<String> keys = new Set<String>();
    for (Integer i = 0; i < 200; i++) {
      String key = 'bulk' + i;
      keys.add(key);
      rows.add(
        new OI_Graph_Node__c(
          Node_Key__c = key,
          Node_Version_Key__c = key + '::v1',
          Version_Number__c = 1,
          Node_Type__c = 'Bulk.Type',
          State__c = 'Active',
          Is_Current__c = true
        )
      );
    }
    insert rows;
    System.assertEquals(
      200,
      new OI_NodeSelector().selectCurrentByKeys(keys).size()
    );
  }

  @isTest
  static void testSelectCurrentByTypeBoundedRespectsCeilingAndExcludesOtherTypesAndNonCurrent() {
    insert new List<OI_Graph_Node__c>{
      new OI_Graph_Node__c(
        Node_Key__c = 'bnd1',
        Node_Version_Key__c = 'bnd1::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Bounded.Type',
        Label__c = 'One',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'bnd2',
        Node_Version_Key__c = 'bnd2::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Bounded.Type',
        Label__c = 'Two',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'bnd3',
        Node_Version_Key__c = 'bnd3::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Bounded.Type',
        Label__c = 'Three',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'bnd4',
        Node_Version_Key__c = 'bnd4::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Bounded.OtherType',
        Label__c = 'Other',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'bnd5',
        Node_Version_Key__c = 'bnd5::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Bounded.Type',
        Label__c = 'Stale',
        State__c = 'Active',
        Is_Current__c = false
      )
    };

    List<OI_Graph_Node__c> unbounded = new OI_NodeSelector()
      .selectCurrentByTypeBounded('Bounded.Type', 500);
    System.assertEquals(
      3,
      unbounded.size(),
      'Only current rows of the requested type must be returned.'
    );

    List<OI_Graph_Node__c> capped = new OI_NodeSelector()
      .selectCurrentByTypeBounded('Bounded.Type', 2);
    System.assertEquals(
      2,
      capped.size(),
      'The ceiling must bound the result even when more current rows exist.'
    );
  }

  @isTest
  static void testSelectCurrentBrowseOrdersAlphabeticallyAndScopesByTypeAndCurrency() {
    insert new List<OI_Graph_Node__c>{
      new OI_Graph_Node__c(
        Node_Key__c = 'brw1',
        Node_Version_Key__c = 'brw1::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Browse.Type',
        Label__c = 'Zebra',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'brw2',
        Node_Version_Key__c = 'brw2::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Browse.Type',
        Label__c = 'Account',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'brw3',
        Node_Version_Key__c = 'brw3::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Browse.OtherType',
        Label__c = 'Aardvark',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'brw4',
        Node_Version_Key__c = 'brw4::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Browse.Type',
        Label__c = 'Stale',
        State__c = 'Active',
        Is_Current__c = false
      )
    };

    List<OI_Graph_Node__c> scoped = new OI_NodeSelector()
      .selectCurrentBrowse('Browse.Type', 20);
    System.assertEquals(
      2,
      scoped.size(),
      'Only current rows of the requested type must be returned.'
    );
    System.assertEquals(
      'Account',
      scoped[0].Label__c,
      'Results must be ordered alphabetically by label.'
    );
    System.assertEquals('Zebra', scoped[1].Label__c);

    List<OI_Graph_Node__c> capped = new OI_NodeSelector()
      .selectCurrentBrowse('Browse.Type', 1);
    System.assertEquals(
      1,
      capped.size(),
      'The ceiling must bound the result even when more current rows exist.'
    );

    List<OI_Graph_Node__c> unscoped = new OI_NodeSelector()
      .selectCurrentBrowse(null, 20);
    System.assertEquals(
      3,
      unscoped.size(),
      'A blank typeKey must browse across every type, current rows only.'
    );
  }

  @isTest
  static void testSelectSecondaryKeysByKeysReturnsCurrentRowsOnlyKeyedByNodeKey() {
    insert new List<OI_Graph_Node__c>{
      new OI_Graph_Node__c(
        Node_Key__c = 'sk1',
        Node_Version_Key__c = 'sk1::v1',
        Version_Number__c = 1,
        Node_Type__c = 'T',
        Secondary_Key__c = 'Stale.Secondary',
        State__c = 'Active',
        Is_Current__c = false
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'sk1',
        Node_Version_Key__c = 'sk1::v2',
        Version_Number__c = 2,
        Node_Type__c = 'T',
        Secondary_Key__c = 'Account',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'sk2',
        Node_Version_Key__c = 'sk2::v1',
        Version_Number__c = 1,
        Node_Type__c = 'T',
        Secondary_Key__c = 'Contact',
        State__c = 'Active',
        Is_Current__c = true
      )
    };

    Map<String, String> secondaryKeysByNodeKey = new OI_NodeSelector()
      .selectSecondaryKeysByKeys(new Set<String>{ 'sk1', 'sk2' });

    System.assertEquals(2, secondaryKeysByNodeKey.size());
    System.assertEquals(
      'Account',
      secondaryKeysByNodeKey.get('sk1'),
      'Only the current version row must be resolved, never a stale one.'
    );
    System.assertEquals('Contact', secondaryKeysByNodeKey.get('sk2'));
  }

  @isTest
  static void testSelectSecondaryKeysByKeysWithNullOrEmptySetReturnsEmptyMap() {
    System.assertEquals(
      0,
      new OI_NodeSelector().selectSecondaryKeysByKeys(null).size()
    );
    System.assertEquals(
      0,
      new OI_NodeSelector().selectSecondaryKeysByKeys(new Set<String>()).size()
    );
  }

  @isTest
  static void testSelectCurrentFieldNodesByParentKeysFiltersByParentKeyTypeAndCurrency() {
    insert new List<OI_Graph_Node__c>{
      new OI_Graph_Node__c(
        Node_Key__c = 'fld1',
        Node_Version_Key__c = 'fld1::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Field',
        Parent_Key__c = 'Account',
        Secondary_Key__c = 'Account.Custom_One__c',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'fld2',
        Node_Version_Key__c = 'fld2::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Field',
        Parent_Key__c = 'Account',
        Secondary_Key__c = 'Account.Custom_Two__c',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'fld3',
        Node_Version_Key__c = 'fld3::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Field',
        Parent_Key__c = 'Account',
        Secondary_Key__c = 'Account.Stale__c',
        State__c = 'Active',
        Is_Current__c = false
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'fld4',
        Node_Version_Key__c = 'fld4::v1',
        Version_Number__c = 1,
        Node_Type__c = 'Field',
        Parent_Key__c = 'Contact',
        Secondary_Key__c = 'Contact.Custom_One__c',
        State__c = 'Active',
        Is_Current__c = true
      ),
      new OI_Graph_Node__c(
        Node_Key__c = 'fld5',
        Node_Version_Key__c = 'fld5::v1',
        Version_Number__c = 1,
        Node_Type__c = 'OtherType',
        Parent_Key__c = 'Account',
        Secondary_Key__c = 'Account.WrongType__c',
        State__c = 'Active',
        Is_Current__c = true
      )
    };

    List<OI_Graph_Node__c> results = new OI_NodeSelector()
      .selectCurrentFieldNodesByParentKeys(
        new Set<String>{ 'Account' },
        'Field',
        null
      );

    System.assertEquals(
      2,
      results.size(),
      'Only current Field-type rows for the requested parent key must be returned.'
    );
    for (OI_Graph_Node__c row : results) {
      System.assertEquals('Account', row.Parent_Key__c);
    }
  }

  @isTest
  static void testSelectCurrentFieldNodesByParentKeysRespectsRowCeiling() {
    List<OI_Graph_Node__c> rows = new List<OI_Graph_Node__c>();
    for (Integer i = 0; i < 5; i++) {
      rows.add(
        new OI_Graph_Node__c(
          Node_Key__c = 'cfld' + i,
          Node_Version_Key__c = 'cfld' + i + '::v1',
          Version_Number__c = 1,
          Node_Type__c = 'Field',
          Parent_Key__c = 'Opportunity',
          Secondary_Key__c = 'Opportunity.F' + i + '__c',
          State__c = 'Active',
          Is_Current__c = true
        )
      );
    }
    insert rows;

    List<OI_Graph_Node__c> capped = new OI_NodeSelector()
      .selectCurrentFieldNodesByParentKeys(
        new Set<String>{ 'Opportunity' },
        'Field',
        2
      );
    System.assertEquals(
      2,
      capped.size(),
      'The row ceiling must bound the result even when more current rows exist.'
    );
  }

  @isTest
  static void testSelectCurrentFieldNodesByParentKeysWithMissingInputsReturnsEmptyList() {
    System.assertEquals(
      0,
      new OI_NodeSelector()
        .selectCurrentFieldNodesByParentKeys(null, 'Field', null)
        .size()
    );
    System.assertEquals(
      0,
      new OI_NodeSelector()
        .selectCurrentFieldNodesByParentKeys(new Set<String>(), 'Field', null)
        .size()
    );
    System.assertEquals(
      0,
      new OI_NodeSelector()
        .selectCurrentFieldNodesByParentKeys(
          new Set<String>{ 'Account' },
          null,
          null
        )
        .size()
    );
  }
}
