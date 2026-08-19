import { parseRecordNodeKey } from 'c/recordNodeKey';

describe('recordNodeKey', () => {
    it('parses a well-formed record node key into its object API name and record Id', () => {
        expect(parseRecordNodeKey('Record::Account::001x1')).toEqual({ objectApiName: 'Account', recordId: '001x1' });
    });

    it('returns null for a metadata node key', () => {
        expect(parseRecordNodeKey('SalesforceMetadata.CustomObject::Account')).toBeNull();
    });

    it('returns null for blank/undefined input', () => {
        expect(parseRecordNodeKey(null)).toBeNull();
        expect(parseRecordNodeKey(undefined)).toBeNull();
        expect(parseRecordNodeKey('')).toBeNull();
    });

    it('returns null for a malformed record-prefixed key missing the second separator', () => {
        expect(parseRecordNodeKey('Record::Account')).toBeNull();
    });
});
