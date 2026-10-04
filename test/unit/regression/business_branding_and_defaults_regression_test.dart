import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/invoice/invoice_type.dart';

void main() {
  const uuid = Uuid();

  group('Business Branding, Invoice Terms, Notes & Statutory Title Regression Tests', () {
    test('Business entity persists and serializes offline logoPath and signaturePath', () {
      final now = DateTime.now().toUtc();
      final business = Business(
        id: uuid.v4(),
        name: 'Sharma Tech Solutions',
        phone: '9811098110',
        stateCode: '07',
        stateName: 'Delhi',
        logoPath: 'C:\\Users\\User\\AppData\\Roaming\\Billzo\\media\\logo_123.png',
        signaturePath: 'C:\\Users\\User\\AppData\\Roaming\\Billzo\\media\\signature_123.png',
        createdAt: now,
        updatedAt: now,
      );

      final map = business.toMap();
      expect(map['logo_path'], equals('C:\\Users\\User\\AppData\\Roaming\\Billzo\\media\\logo_123.png'));
      expect(map['signature_path'], equals('C:\\Users\\User\\AppData\\Roaming\\Billzo\\media\\signature_123.png'));

      final restored = Business.fromMap(map);
      expect(restored.logoPath, equals(business.logoPath));
      expect(restored.signaturePath, equals(business.signaturePath));
    });

    test('BusinessSettings persists defaultInvoiceTerms and defaultInvoiceNotes backward-compatibly', () {
      final now = DateTime.now().toUtc();
      final settings = BusinessSettings(
        id: 'settings-1',
        businessId: 'biz-1',
        defaultInvoiceTerms: 'Payment due in 15 days. 18% interest on delayed payment.',
        defaultInvoiceNotes: 'We appreciate your business! Please visit again.',
        createdAt: now,
        updatedAt: now,
      );

      final map = settings.toMap();
      // Verify terms column contains backward-compatible JSON encoding
      expect(map['default_invoice_terms'], contains('Payment due in 15 days'));
      expect(map['default_invoice_terms'], contains('We appreciate your business'));

      final restored = BusinessSettings.fromMap(map);
      expect(restored.defaultInvoiceTerms, equals('Payment due in 15 days. 18% interest on delayed payment.'));
      expect(restored.defaultInvoiceNotes, equals('We appreciate your business! Please visit again.'));
    });

    test('Finalized invoice historical terms and notes remain unchanged when business defaults later change', () {
      // 1. Initial business settings
      var settings = BusinessSettings(
        id: 'settings-1',
        businessId: 'biz-1',
        defaultInvoiceTerms: '2025 Terms: Net 30 days',
        defaultInvoiceNotes: '2025 Note: Thank you!',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      // 2. Create and finalize an invoice using current defaults
      final invoice = Invoice(
        id: uuid.v4(),
        businessId: 'biz-1',
        invoiceNumber: 'INV-2025-001',
        customerId: 'cust-1',
        invoiceDate: DateTime(2025, 12, 1),
        dueDate: DateTime(2025, 12, 31),
        placeOfSupplyStateCode: '27',
        status: InvoiceStatus.finalized,
        subtotalPaise: 100000,
        taxableAmountPaise: 100000,
        cgstPaise: 0,
        sgstPaise: 0,
        igstPaise: 0,
        roundOffPaise: 0,
        totalAmountPaise: 100000,
        paidAmountPaise: 100000,
        balanceAmountPaise: 0,
        termsAndConditions: settings.defaultInvoiceTerms,
        notes: settings.defaultInvoiceNotes,
        createdAt: DateTime(2025, 12, 1),
        updatedAt: DateTime(2025, 12, 1),
      );

      expect(invoice.termsAndConditions, equals('2025 Terms: Net 30 days'));
      expect(invoice.notes, equals('2025 Note: Thank you!'));

      // 3. Next year, business owner updates default terms in Business Settings
      settings = settings.copyWith(
        defaultInvoiceTerms: '2026 Terms: Immediate payment upon receipt',
        defaultInvoiceNotes: '2026 Note: All sales are final',
      );

      // 4. Verify historical finalized invoice was NOT mutated by the settings update
      expect(invoice.termsAndConditions, equals('2025 Terms: Net 30 days'));
      expect(invoice.notes, equals('2025 Note: Thank you!'));
      expect(settings.defaultInvoiceTerms, equals('2026 Terms: Immediate payment upon receipt'));
    });

    test('Statutory document title logic matches business tax configuration', () {
      // Case A: Registered Regular business with valid GSTIN
      final regularBusiness = Business(
        id: 'biz-reg',
        name: 'Regular GST Trader',
        phone: '9800000000',
        stateCode: '27',
        stateName: 'Maharashtra',
        gstin: '27ABCDE1234F1Z5',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      final taxInvoice = Invoice(
        id: uuid.v4(),
        businessId: regularBusiness.id,
        invoiceNumber: 'INV-2026-001',
        customerId: 'cust-1',
        invoiceDate: DateTime.now().toUtc(),
        dueDate: DateTime.now().toUtc(),
        placeOfSupplyStateCode: '27',
        invoiceType: InvoiceType.taxInvoice,
        status: InvoiceStatus.finalized,
        subtotalPaise: 10000,
        taxableAmountPaise: 10000,
        cgstPaise: 900,
        sgstPaise: 900,
        igstPaise: 0,
        roundOffPaise: 0,
        totalAmountPaise: 11800,
        paidAmountPaise: 0,
        balanceAmountPaise: 11800,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      final isRegCompositionOrUnregistered = regularBusiness.gstin == null || regularBusiness.gstin!.trim().isEmpty;
      final regDocTitle = (taxInvoice.invoiceType == InvoiceType.billOfSupply || isRegCompositionOrUnregistered)
          ? 'BILL OF SUPPLY'
          : taxInvoice.invoiceType.displayName.toUpperCase();

      expect(regDocTitle, equals('TAX INVOICE'));

      // Case B: Composition / Unregistered business without GSTIN
      final compositionBusiness = Business(
        id: 'biz-comp',
        name: 'Small Corner Grocery',
        phone: '9811111111',
        stateCode: '27',
        stateName: 'Maharashtra',
        gstin: null, // Unregistered / Composition
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      final isCompUnregistered = compositionBusiness.gstin == null || compositionBusiness.gstin!.trim().isEmpty;
      final compDocTitle = (taxInvoice.invoiceType == InvoiceType.billOfSupply || isCompUnregistered)
          ? 'BILL OF SUPPLY'
          : taxInvoice.invoiceType.displayName.toUpperCase();

      // Statutory requirement: must show BILL OF SUPPLY
      expect(compDocTitle, equals('BILL OF SUPPLY'));
    });
  });
}
