import 'package:flutter_test/flutter_test.dart';
import 'package:billzo/domain/business/business_validator.dart';

void main() {
  group('BusinessValidator Domain Tests', () {
    test('Valid business profile passes validation', () {
      final result = BusinessValidator.validate(
        name: 'ABC Electronics',
        phone: '9876543210',
        stateCode: '27', // Maharashtra
        email: 'info@abcelectronics.com',
        gstin: '27AAAAA0000A1Z5',
        pincode: '400001',
      );

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('Rejects empty or blank business name', () {
      final result = BusinessValidator.validate(
        name: '   ',
        phone: '9876543210',
        stateCode: '27',
      );

      expect(result.isValid, isFalse);
      expect(result.errors['name'], contains('required'));
    });

    test('Rejects short business name', () {
      final result = BusinessValidator.validate(
        name: 'A',
        phone: '9876543210',
        stateCode: '27',
      );

      expect(result.isValid, isFalse);
      expect(result.errors['name'], contains('at least 2 characters'));
    });

    test('Rejects invalid phone numbers', () {
      final r1 = BusinessValidator.validate(
        name: 'Valid Shop',
        phone: '12345',
        stateCode: '27',
      );
      expect(r1.isValid, isFalse);
      expect(r1.errors['phone'], isNotNull);

      // Starting with invalid digit for Indian mobile
      final r2 = BusinessValidator.validate(
        name: 'Valid Shop',
        phone: '2345678901',
        stateCode: '27',
      );
      expect(r2.isValid, isFalse);
      expect(r2.errors['phone'], isNotNull);
    });

    test('Sanitizes phone numbers with prefixes (+91, 0)', () {
      expect(BusinessValidator.sanitizePhone('+91 98765 43210'), equals('9876543210'));
      expect(BusinessValidator.sanitizePhone('09876543210'), equals('9876543210'));
      expect(BusinessValidator.sanitizePhone('98765-43210'), equals('9876543210'));
    });

    test('Rejects invalid GSTIN formats', () {
      final r1 = BusinessValidator.validate(
        name: 'Valid Shop',
        phone: '9876543210',
        stateCode: '27',
        gstin: 'INVALIDGSTIN123',
      );
      expect(r1.isValid, isFalse);
      expect(r1.errors['gstin'], isNotNull);
    });

    test('Rejects GSTIN where state code does not match selected state', () {
      // GSTIN starts with '29' (Karnataka), but selected state is '27' (Maharashtra)
      final result = BusinessValidator.validate(
        name: 'Valid Shop',
        phone: '9876543210',
        stateCode: '27',
        gstin: '29AAAAA0000A1Z5',
      );
      expect(result.isValid, isFalse);
      expect(result.errors['gstin'], contains('does not match selected state'));
    });

    test('Rejects invalid email format', () {
      final result = BusinessValidator.validate(
        name: 'Valid Shop',
        phone: '9876543210',
        stateCode: '27',
        email: 'invalid-email-address',
      );
      expect(result.isValid, isFalse);
      expect(result.errors['email'], isNotNull);
    });

    test('Rejects invalid PIN code', () {
      final result = BusinessValidator.validate(
        name: 'Valid Shop',
        phone: '9876543210',
        stateCode: '27',
        pincode: '012345', // Starts with 0
      );
      expect(result.isValid, isFalse);
      expect(result.errors['pincode'], isNotNull);
    });

    test('Rejects invalid bank IFSC', () {
      final result = BusinessValidator.validate(
        name: 'Valid Shop',
        phone: '9876543210',
        stateCode: '27',
        bankIfsc: 'HDFC1234', // Too short, missing 5th zero
      );
      expect(result.isValid, isFalse);
      expect(result.errors['bankIfsc'], isNotNull);
    });
  });
}
