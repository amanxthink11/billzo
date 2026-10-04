import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_item.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/infrastructure/services/pdf/invoice_pdf_service.dart';
import 'package:billzo/infrastructure/services/printing/printer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Business testBusiness;
  late BusinessSettings testSettings;
  late Party testCustomer;
  late Invoice testInvoice;

  setUp(() {
    testBusiness = Business(
      id: 'biz-pdf-test',
      name: 'SuperTech Enterprises',
      phone: '9876543210',
      stateCode: '27',
      stateName: 'Maharashtra',
      gstin: '27AAAAA0000A1Z5',
      addressLine1: 'Suite 404, Tech Park',
      city: 'Pune',
      pincode: '411057',
      upiId: 'supertech@upi',
      bankName: 'HDFC Bank',
      bankAccountNumber: '50100234567890',
      bankIfsc: 'HDFC0001234',
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );

    testSettings = BusinessSettings(
      id: 'settings-1',
      businessId: testBusiness.id,
      printBusinessLogo: true,
      printBankDetails: true,
      printUpiQr: true,
      enableRoundOff: true,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );

    testCustomer = Party(
      id: 'cust-pdf-test',
      businessId: testBusiness.id,
      partyType: PartyType.customer,
      name: 'Bharat Enterprises Ltd',
      phone: '9123456780',
      gstin: '27BBBBB1111B1Z2',
      billingStateCode: '27',
      billingStateName: 'Maharashtra',
      billingAddressLine1: 'Plot 12, Industrial Area',
      billingCity: 'Mumbai',
      billingPincode: '400001',
      currentBalancePaise: 0,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );

    testInvoice = Invoice(
      id: 'inv-pdf-1',
      businessId: testBusiness.id,
      invoiceNumber: 'INV-2026-0001',
      customerId: testCustomer.id,
      customerName: testCustomer.name,
      customerPhone: testCustomer.phone,
      customerGstin: testCustomer.gstin,
      customerAddress: 'Plot 12, Industrial Area, Mumbai, Maharashtra - 400001',
      placeOfSupplyStateCode: '27',
      invoiceDate: DateTime(2026, 10, 1),
      dueDate: DateTime(2026, 10, 15),
      status: InvoiceStatus.finalized,
      subtotalPaise: 1250000, // ₹12,500.00
      taxableAmountPaise: 1250000,
      cgstPaise: 112500, // 9% = ₹1,125.00
      sgstPaise: 112500, // 9% = ₹1,125.00
      igstPaise: 0,
      roundOffPaise: 0,
      totalAmountPaise: 1475000, // ₹14,750.00
      balanceAmountPaise: 1475000,
      notes: 'Thank you for your business!',
      termsAndConditions: '1. Goods once sold cannot be returned.\n2. Subject to Pune jurisdiction.',
      items: [
        InvoiceItem(
          id: 'item-pdf-1',
          invoiceId: 'inv-pdf-1',
          productId: 'prod-1',
          taxRateId: 'tax-18',
          productName: 'Commercial Router AC2600',
          hsnSac: '851762',
          quantityScaled: 2000, // 2 units
          unitCode: 'PCS',
          ratePaise: 625000, // ₹6,250.00
          discountPaise: 0,
          taxableAmountPaise: 1250000,
          cgstRateBasisPoints: 900,
          sgstRateBasisPoints: 900,
          cgstAmountPaise: 112500,
          sgstAmountPaise: 112500,
          totalAmountPaise: 1475000,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      ],
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
  });

  group('Invoice PDF & Printing Service Tests', () {
    test('Generates valid standard A4 Tax Invoice PDF bytes', () async {
      final pdfBytes = await InvoicePdfService.generateA4InvoicePdf(
        invoice: testInvoice,
        business: testBusiness,
        customer: testCustomer,
        settings: testSettings,
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(1000));

      // PDF magic header: %PDF-
      final header = utf8.decode(pdfBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });

    test('Generates 80mm POS Thermal receipt bytes via PrintingService', () async {
      const printingService = PrintingService();
      final docBytes = await printingService.generateInvoiceDocument(
        invoice: testInvoice,
        business: testBusiness,
        customer: testCustomer,
        settings: testSettings,
        format: PrintFormat.thermal80mm,
      );

      expect(docBytes, isNotEmpty);
      final header = utf8.decode(docBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });

    test('Generates 58mm POS Thermal receipt bytes via PrintingService', () async {
      const printingService = PrintingService();
      final docBytes = await printingService.generateInvoiceDocument(
        invoice: testInvoice,
        business: testBusiness,
        customer: testCustomer,
        settings: testSettings,
        format: PrintFormat.thermal58mm,
      );

      expect(docBytes, isNotEmpty);
      final header = utf8.decode(docBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });

    test('PrintFormat enum covers all required formats and displays properly', () {
      expect(PrintFormat.a4.displayName, equals('Standard A4'));
      expect(PrintFormat.thermal80mm.displayName, equals('80mm POS Thermal'));
      expect(PrintFormat.thermal58mm.displayName, equals('58mm POS Thermal'));

      expect(PrintFormat.fromString('80mm'), equals(PrintFormat.thermal80mm));
      expect(PrintFormat.fromString('58mm'), equals(PrintFormat.thermal58mm));
      expect(PrintFormat.fromString('A4'), equals(PrintFormat.a4));
      expect(PrintFormat.fromString('unknown'), equals(PrintFormat.a4));
    });
  });
}
