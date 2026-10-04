import 'package:flutter_test/flutter_test.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/party/party_validator.dart';

void main() {
  group('PartyValidator Domain Tests', () {
    final now = DateTime.now().toUtc();

    test('Valid Customer passes validation', () {
      final party = Party(
        id: 'cust-1',
        businessId: 'biz-1',
        name: 'Sharma Electronics',
        companyName: 'Sharma Traders Pvt Ltd',
        partyType: PartyType.customer,
        phone: '9876543210',
        email: 'sharma@example.com',
        gstin: '27ABCDE1234F1Z5',
        pan: 'ABCDE1234F',
        billingStateCode: '27',
        billingStateName: 'Maharashtra',
        billingPincode: '400001',
        creditLimitPaise: 5000000,
        creditPeriodDays: 30,
        openingBalancePaise: 2500000,
        openingBalanceType: OpeningBalanceType.toReceive,
        createdAt: now,
        updatedAt: now,
      );

      final result = PartyValidator.validate(party);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('Valid Supplier passes validation', () {
      final party = Party(
        id: 'supp-1',
        businessId: 'biz-1',
        name: 'Super Wholesale Hub',
        partyType: PartyType.supplier,
        phone: '9123456789',
        email: 'info@superwholesale.in',
        billingStateCode: '29',
        billingStateName: 'Karnataka',
        billingPincode: '560001',
        openingBalancePaise: 4000000,
        openingBalanceType: OpeningBalanceType.toPay,
        createdAt: now,
        updatedAt: now,
      );

      final result = PartyValidator.validate(party);
      expect(result.isValid, isTrue);
    });

    test('Party name is strictly required and must be at least 2 chars', () {
      final emptyName = Party(
        id: '1',
        businessId: 'biz-1',
        name: '   ',
        partyType: PartyType.customer,
        createdAt: now,
        updatedAt: now,
      );
      final emptyResult = PartyValidator.validate(emptyName);
      expect(emptyResult.isValid, isFalse);
      expect(emptyResult.errors['name'], contains('required'));

      final shortName = emptyName.copyWith(name: 'A');
      final shortResult = PartyValidator.validate(shortName);
      expect(shortResult.isValid, isFalse);
      expect(shortResult.errors['name'], contains('at least 2'));
    });

    test('Validates Indian phone numbers (10 digits starting with 6-9)', () {
      final invalidPhone = Party(
        id: '1',
        businessId: 'biz-1',
        name: 'Valid Name',
        partyType: PartyType.customer,
        phone: '1234567890', // Starts with 1
        createdAt: now,
        updatedAt: now,
      );
      final result = PartyValidator.validate(invalidPhone);
      expect(result.isValid, isFalse);
      expect(result.errors['phone'], contains('10-digit Indian mobile number'));

      // Phone sanitization handles +91 and 0 prefixes
      expect(PartyValidator.sanitizePhone('+91 98765 43210'), equals('9876543210'));
      expect(PartyValidator.sanitizePhone('09876543210'), equals('9876543210'));
      expect(PartyValidator.sanitizePhone('98765-43210'), equals('9876543210'));
    });

    test('Validates alternate phone numbers', () {
      final party = Party(
        id: '1',
        businessId: 'biz-1',
        name: 'Valid Name',
        partyType: PartyType.customer,
        phone: '9876543210',
        alternatePhone: '5551234567', // Starts with 5
        createdAt: now,
        updatedAt: now,
      );
      final result = PartyValidator.validate(party);
      expect(result.isValid, isFalse);
      expect(result.errors['alternate_phone'], isNotNull);
    });

    test('Validates email format', () {
      final party = Party(
        id: '1',
        businessId: 'biz-1',
        name: 'Valid Name',
        partyType: PartyType.customer,
        email: 'invalid-email-string',
        createdAt: now,
        updatedAt: now,
      );
      final result = PartyValidator.validate(party);
      expect(result.isValid, isFalse);
      expect(result.errors['email'], contains('valid email'));
    });

    test('Validates 15-character GSTIN format and state code alignment', () {
      // Invalid format
      final partyInvalid = Party(
        id: '1',
        businessId: 'biz-1',
        name: 'Valid Name',
        partyType: PartyType.customer,
        gstin: 'INVALIDGSTIN',
        createdAt: now,
        updatedAt: now,
      );
      expect(PartyValidator.validate(partyInvalid).errors['gstin'], contains('Invalid GSTIN format'));

      // GSTIN state code mismatch (27 for Maharashtra, but billing state is 29 Karnataka)
      final partyMismatch = Party(
        id: '1',
        businessId: 'biz-1',
        name: 'Valid Name',
        partyType: PartyType.customer,
        gstin: '27ABCDE1234F1Z5',
        billingStateCode: '29',
        billingStateName: 'Karnataka',
        createdAt: now,
        updatedAt: now,
      );
      final mismatchResult = PartyValidator.validate(partyMismatch);
      expect(mismatchResult.errors['gstin'], contains('does not match billing state'));
    });

    test('Validates PAN format', () {
      final party = Party(
        id: '1',
        businessId: 'biz-1',
        name: 'Valid Name',
        partyType: PartyType.customer,
        pan: '12345ABCDE', // Should be 5 letters + 4 digits + 1 letter
        createdAt: now,
        updatedAt: now,
      );
      expect(PartyValidator.validate(party).errors['pan'], contains('Invalid PAN format'));
    });

    test('Validates Indian PIN codes (6 digits, does not start with 0)', () {
      final party = Party(
        id: '1',
        businessId: 'biz-1',
        name: 'Valid Name',
        partyType: PartyType.customer,
        billingPincode: '012345',
        createdAt: now,
        updatedAt: now,
      );
      expect(PartyValidator.validate(party).errors['billing_pincode'], contains('valid 6-digit'));
    });

    test('Rejects negative monetary values for credit limit or opening balance', () {
      final party = Party(
        id: '1',
        businessId: 'biz-1',
        name: 'Valid Name',
        partyType: PartyType.customer,
        creditLimitPaise: -100,
        openingBalancePaise: -500,
        createdAt: now,
        updatedAt: now,
      );
      final result = PartyValidator.validate(party);
      expect(result.errors['credit_limit'], contains('cannot be negative'));
      expect(result.errors['opening_balance'], contains('cannot be negative'));
    });
  });
}
