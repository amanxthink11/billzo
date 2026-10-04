import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_item.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/invoice/invoice_type.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/infrastructure/services/printing/esc_pos_receipt_formatter.dart';
import 'package:billzo/infrastructure/services/printing/printer_service.dart';

void main() {
  group('EscPosReceiptFormatter', () {
    late Business business;
    late Party customer;
    late Invoice invoiceIntra;
    late Invoice invoiceInter;
    late BusinessSettings settings;

    setUp(() {
      business = Business(
        id: 'biz-1',
        name: 'Billzo Supermarket',
        tradeName: 'Billzo Mart',
        gstin: '27AABCU9603R1ZM',
        pan: 'AABCU9603R',
        phone: '9876543210',
        email: 'billing@billzo.com',
        addressLine1: 'Shop 4, Market Yard',
        city: 'Pune',
        stateCode: '27',
        stateName: 'Maharashtra',
        upiId: 'billzomart@okaxis',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      customer = Party(
        id: 'cust-1',
        businessId: 'biz-1',
        name: 'Rohan Sharma',
        phone: '9822099999',
        gstin: '27AABCR1234M1Z1',
        partyType: PartyType.customer,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final item1 = InvoiceItem(
        id: 'item-1',
        invoiceId: 'inv-1',
        productId: 'prod-1',
        taxRateId: 'tax-1',
        productName: 'Organic Basmati Rice 5kg',
        hsnSac: '1006',
        quantityScaled: 2000, // 2 PCS
        unitCode: 'PCS',
        ratePaise: 45000, // ₹450.00
        taxableAmountPaise: 90000, // ₹900.00
        cgstRateBasisPoints: 250, // 2.5%
        cgstAmountPaise: 2250, // ₹22.50
        sgstRateBasisPoints: 250, // 2.5%
        sgstAmountPaise: 2250, // ₹22.50
        igstRateBasisPoints: 0,
        igstAmountPaise: 0,
        cessRateBasisPoints: 0,
        cessAmountPaise: 0,
        totalAmountPaise: 94500, // ₹945.00
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final item2 = InvoiceItem(
        id: 'item-2',
        invoiceId: 'inv-1',
        productId: 'prod-2',
        taxRateId: 'tax-2',
        productName: 'Cold Pressed Sunflower Oil 1L',
        hsnSac: '1512',
        quantityScaled: 1000, // 1 PCS
        unitCode: 'PCS',
        ratePaise: 21000, // ₹210.00
        taxableAmountPaise: 20000, // ₹200.00 after ₹10 discount
        discountPaise: 1000, // ₹10.00
        cgstRateBasisPoints: 250,
        cgstAmountPaise: 500, // ₹5.00
        sgstRateBasisPoints: 250,
        sgstAmountPaise: 500, // ₹5.00
        igstRateBasisPoints: 0,
        igstAmountPaise: 0,
        cessRateBasisPoints: 0,
        cessAmountPaise: 0,
        totalAmountPaise: 21000, // ₹210.00
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      invoiceIntra = Invoice(
        id: 'inv-1',
        businessId: 'biz-1',
        customerId: 'cust-1',
        customerName: 'Rohan Sharma',
        customerPhone: '9822099999',
        customerGstin: '27AABCR1234M1Z1',
        invoiceNumber: 'INV-2026-0042',
        invoiceDate: DateTime(2026, 10, 3),
        dueDate: DateTime(2026, 10, 3),
        placeOfSupplyStateCode: '27',
        invoiceType: InvoiceType.taxInvoice,
        status: InvoiceStatus.paid,
        subtotalPaise: 111000,
        discountPaise: 1000,
        taxableAmountPaise: 110000,
        cgstPaise: 2750,
        sgstPaise: 2750,
        igstPaise: 0,
        cessPaise: 0,
        roundOffPaise: 0,
        totalAmountPaise: 115500,
        paidAmountPaise: 115500,
        balanceAmountPaise: 0,
        items: [item1, item2],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      invoiceInter = Invoice(
        id: 'inv-2',
        businessId: 'biz-1',
        customerId: 'cust-1',
        customerName: 'Rohan Sharma',
        invoiceNumber: 'INV-2026-0043',
        invoiceDate: DateTime(2026, 10, 3),
        dueDate: DateTime(2026, 10, 3),
        placeOfSupplyStateCode: '24', // Gujarat (Inter-State)
        invoiceType: InvoiceType.taxInvoice,
        status: InvoiceStatus.finalized,
        subtotalPaise: 100000,
        discountPaise: 0,
        taxableAmountPaise: 100000,
        cgstPaise: 0,
        sgstPaise: 0,
        igstPaise: 18000,
        cessPaise: 0,
        roundOffPaise: 0,
        totalAmountPaise: 118000,
        paidAmountPaise: 0,
        balanceAmountPaise: 118000,
        items: [item1],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      settings = BusinessSettings(
        id: 'set-1',
        businessId: 'biz-1',
        printBusinessLogo: true,
        printBankDetails: true,
        printUpiQr: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    });

    test('generateReceiptBytes produces valid 80mm ESC/POS byte sequence', () {
      final bytes = EscPosReceiptFormatter.generateReceiptBytes(
        invoice: invoiceIntra,
        business: business,
        customer: customer,
        settings: settings,
        format: PrintFormat.thermal80mm,
        kickCashDrawer: true,
      );

      expect(bytes, isA<Uint8List>());
      expect(bytes, isNotEmpty);

      // Verify ESC/POS init command [0x1B, 0x40]
      expect(bytes[0], equals(0x1B));
      expect(bytes[1], equals(0x40));

      // Verify cash drawer kick command is included
      expect(bytes.contains(0x1B) && bytes.contains(0x70), isTrue);

      // Verify partial paper cut command [0x1D, 0x56, 0x42, 0x00]
      final cutIdx = bytes.lastIndexOf(0x1D);
      expect(cutIdx, isNonNegative);
      expect(bytes[cutIdx + 1], equals(0x56));

      // Verify text contents are encoded in Latin1
      final decoded = latin1.decode(bytes, allowInvalid: true);
      expect(decoded.contains('Billzo Supermarket'), isTrue);
      expect(decoded.contains('INV-2026-0042'), isTrue);
      expect(decoded.contains('Rohan Sharma'), isTrue);
      expect(decoded.contains('1155.00'), isTrue); // Total ₹1,155.00
      expect(decoded.contains('Taxable Amount:'), isTrue);
      expect(decoded.contains('CGST:'), isTrue);
      expect(decoded.contains('SGST:'), isTrue);
      expect(decoded.contains('Thank You! Visit Again.'), isTrue);
    });

    test('generateReceiptBytes produces valid 58mm ESC/POS byte sequence', () {
      final bytes = EscPosReceiptFormatter.generateReceiptBytes(
        invoice: invoiceIntra,
        business: business,
        customer: customer,
        settings: settings,
        format: PrintFormat.thermal58mm,
        kickCashDrawer: false,
      );

      expect(bytes, isNotEmpty);
      final decoded = latin1.decode(bytes, allowInvalid: true);
      expect(decoded.contains('Billzo Supermarket'), isTrue);
      expect(decoded.contains('INV-2026-0042'), isTrue);
      expect(decoded.contains('1155.00'), isTrue);
    });

    test('generateReceiptBytes includes IGST for inter-state invoices', () {
      final bytes = EscPosReceiptFormatter.generateReceiptBytes(
        invoice: invoiceInter,
        business: business,
        customer: customer,
        settings: settings,
        format: PrintFormat.thermal80mm,
      );

      final decoded = latin1.decode(bytes, allowInvalid: true);
      expect(decoded.contains('IGST:'), isTrue);
      expect(decoded.contains('180.00'), isTrue);
      expect(decoded.contains('CGST:'), isFalse);
    });

    test('formatAsPlainText generates clean 80mm and 58mm text receipts with deterministic columns', () {
      final text80 = EscPosReceiptFormatter.formatAsPlainText(
        invoice: invoiceIntra,
        business: business,
        customer: customer,
        settings: settings,
        format: PrintFormat.thermal80mm,
      );

      expect(text80, contains('Billzo Supermarket'));
      expect(text80, contains('INV-2026-0042'));
      expect(text80, contains('TOTAL (INR):'));
      expect(text80, contains('1155.00'));
      expect(text80, contains('Scan to Pay via UPI'));

      // Check column widths: each line in text80 should be at most 48 characters (excluding newline)
      final lines80 = text80.split('\n');
      for (final line in lines80) {
        expect(line.length, lessThanOrEqualTo(48));
      }

      final text58 = EscPosReceiptFormatter.formatAsPlainText(
        invoice: invoiceIntra,
        business: business,
        customer: customer,
        settings: settings,
        format: PrintFormat.thermal58mm,
      );

      final lines58 = text58.split('\n');
      for (final line in lines58) {
        expect(line.length, lessThanOrEqualTo(32));
      }
    });

    test('UPI QR code generation embeds exact decimal amount without float conversion', () {
      final bytes = EscPosReceiptFormatter.generateReceiptBytes(
        invoice: invoiceIntra,
        business: business,
        customer: customer,
        settings: settings,
        format: PrintFormat.thermal80mm,
      );

      final decoded = latin1.decode(bytes, allowInvalid: true);
      expect(decoded.contains('am=1155.00'), isTrue);
      expect(decoded.contains('pa=billzomart@okaxis'), isTrue);
      expect(decoded.contains('cu=INR'), isTrue);
    });
  });
}
