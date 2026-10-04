import 'package:flutter_test/flutter_test.dart';
import 'package:billzo/domain/recurring/recurring_frequency.dart';
import 'package:billzo/domain/recurring/recurring_invoice.dart';
import 'package:billzo/domain/recurring/recurring_invoice_item.dart';
import 'package:billzo/domain/recurring/recurring_invoice_status.dart';
import 'package:billzo/domain/recurring/recurring_invoice_validator.dart';

void main() {
  group('RecurringInvoice Domain & Validation Tests', () {
    final now = DateTime(2026, 3, 1);

    RecurringInvoice createSampleProfile({
      String profileName = 'Monthly IT Retainer',
      String customerId = 'cust-123',
      RecurringFrequency frequency = RecurringFrequency.monthly,
      DateTime? startDate,
      DateTime? endDate,
      int? customIntervalDays,
      List<RecurringInvoiceItem>? items,
    }) {
      return RecurringInvoice(
        id: 'rec-001',
        businessId: 'biz-001',
        customerId: customerId,
        customerName: 'Acme Corp',
        profileName: profileName,
        frequency: frequency,
        startDate: startDate ?? now,
        endDate: endDate,
        nextRunDate: startDate ?? now,
        status: RecurringInvoiceStatus.active,
        customIntervalDays: customIntervalDays,
        items: items ??
            [
              RecurringInvoiceItem(
                id: 'item-1',
                recurringInvoiceId: 'rec-001',
                productId: 'prod-001',
                taxRateId: 'tax-18',
                productName: 'Server Maintenance',
                quantity: 2,
                unitCode: 'NOS',
                ratePaise: 500000, // 5,000 INR
                discountPaise: 50000, // 500 INR
                createdAt: now,
                updatedAt: now,
              ),
            ],
        createdAt: now,
        updatedAt: now,
      );
    }

    test('RecurringInvoiceItem calculates gross and taxable amount accurately in integer paise', () {
      final item = RecurringInvoiceItem(
        id: 'item-1',
        recurringInvoiceId: 'rec-001',
        productId: 'prod-001',
        taxRateId: 'tax-18',
        productName: 'Server Maintenance',
        quantity: 3,
        unitCode: 'NOS',
        ratePaise: 100000, // 1,000 INR
        discountPaise: 20000, // 200 INR
        createdAt: now,
        updatedAt: now,
      );

      // Gross = 3 * 100000 = 300000 paise
      expect(item.grossAmountPaise, equals(300000));
      // Taxable = 300000 - 20000 = 280000 paise
      expect(item.taxableAmountPaise, equals(280000));
    });

    test('Valid profile passes domain validator with 0 errors', () {
      final profile = createSampleProfile();
      final errors = RecurringInvoiceValidator.validate(profile);
      expect(errors, isEmpty);
    });

    test('Validator rejects blank profile name and empty customer ID', () {
      final profile = createSampleProfile(
        profileName: '   ',
        customerId: '',
      );
      final errors = RecurringInvoiceValidator.validate(profile);
      expect(errors.any((e) => e.contains('Profile name cannot be empty')), isTrue);
      expect(errors.any((e) => e.contains('Customer must be selected')), isTrue);
    });

    test('Validator requires customIntervalDays for custom frequency', () {
      final profile = createSampleProfile(
        frequency: RecurringFrequency.custom,
        customIntervalDays: null,
      );
      final errors = RecurringInvoiceValidator.validate(profile);
      expect(errors.any((e) => e.contains('Custom frequency requires an interval of at least 1 day')), isTrue);
    });

    test('Validator rejects profile when end date is earlier than start date', () {
      final profile = createSampleProfile(
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2026, 5, 1),
      );
      final errors = RecurringInvoiceValidator.validate(profile);
      expect(errors.any((e) => e.contains('End date cannot be earlier than start date')), isTrue);
    });

    test('Validator rejects empty items list', () {
      final profile = createSampleProfile(items: []);
      final errors = RecurringInvoiceValidator.validate(profile);
      expect(errors.any((e) => e.contains('At least one item line is required')), isTrue);
    });

    test('Validator rejects item with zero or negative quantity or rate', () {
      final profile = createSampleProfile(
        items: [
          RecurringInvoiceItem(
            id: 'item-1',
            recurringInvoiceId: 'rec-001',
            productId: 'prod-001',
            taxRateId: 'tax-18',
            productName: 'Bad Item',
            quantity: 0,
            unitCode: 'NOS',
            ratePaise: -500,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      final errors = RecurringInvoiceValidator.validate(profile);
      expect(errors.any((e) => e.contains('Quantity must be greater than zero')), isTrue);
      expect(errors.any((e) => e.contains('Rate cannot be negative')), isTrue);
    });

    test('Status transitions: allows active <-> paused, active -> completed/cancelled', () {
      expect(
        () => RecurringInvoiceValidator.checkStatusTransition(
            RecurringInvoiceStatus.active, RecurringInvoiceStatus.paused),
        returnsNormally,
      );
      expect(
        () => RecurringInvoiceValidator.checkStatusTransition(
            RecurringInvoiceStatus.paused, RecurringInvoiceStatus.active),
        returnsNormally,
      );
      expect(
        () => RecurringInvoiceValidator.checkStatusTransition(
            RecurringInvoiceStatus.active, RecurringInvoiceStatus.completed),
        returnsNormally,
      );
      expect(
        () => RecurringInvoiceValidator.checkStatusTransition(
            RecurringInvoiceStatus.active, RecurringInvoiceStatus.cancelled),
        returnsNormally,
      );
    });

    test('Status transitions: rejects mutating terminal cancelled profile', () {
      expect(
        () => RecurringInvoiceValidator.checkStatusTransition(
            RecurringInvoiceStatus.cancelled, RecurringInvoiceStatus.active),
        throwsA(isA<StateError>()),
      );
      expect(
        () => RecurringInvoiceValidator.checkStatusTransition(
            RecurringInvoiceStatus.completed, RecurringInvoiceStatus.paused),
        throwsA(isA<StateError>()),
      );
    });
  });
}
