/**
 * Purpose: Verifies OI_JsonUtil's null-safe conversions and readInteger's "null means unknown"
 *          contract (ADR-0031).
 */
@isTest
private class OI_JsonUtilTest {
  @isTest
  static void testReadIntegerReturnsThePresentIntegerAttribute() {
    System.assertEquals(
      57,
      OI_JsonUtil.readInteger('{"fieldCount":57}', 'fieldCount')
    );
    System.assertEquals(
      0,
      OI_JsonUtil.readInteger('{"fieldCount":0}', 'fieldCount'),
      'A real zero is a value, not unknown.'
    );
  }

  @isTest
  static void testReadIntegerReturnsNullWhenUnknown() {
    System.assertEquals(null, OI_JsonUtil.readInteger(null, 'fieldCount'));
    System.assertEquals(null, OI_JsonUtil.readInteger('', 'fieldCount'));
    System.assertEquals(null, OI_JsonUtil.readInteger('{}', 'fieldCount'));
    System.assertEquals(
      null,
      OI_JsonUtil.readInteger('{"fieldCount":"57"}', 'fieldCount')
    );
    System.assertEquals(
      null,
      OI_JsonUtil.readInteger('not json', 'fieldCount')
    );
    System.assertEquals(null, OI_JsonUtil.readInteger('[1,2]', 'fieldCount'));
  }

  @isTest
  static void testMapRoundTrip() {
    System.assertEquals(0, OI_JsonUtil.toMap(null).size());
    System.assertEquals(null, OI_JsonUtil.toJson(new Map<String, Object>()));
    System.assertEquals(
      1,
      OI_JsonUtil.toMap(OI_JsonUtil.toJson(new Map<String, Object>{ 'a' => 1 }))
        .get('a')
    );
  }
}
