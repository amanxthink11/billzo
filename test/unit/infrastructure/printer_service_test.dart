import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_item.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/invoice/invoice_type.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/infrastructure/services/printing/printer_service.dart';

void main() {
  late PrintingService printerService;
  late Business testBusiness;
  late Party testCustomer;
  late BusinessSettings testSettings;
  late Invoice testInvoice;

  setUp(() {
    printerService = const PrintingService();

    testBusiness = Business(
      id: 'biz-001',
      name: 'Apex Retail Solutions Pvt Ltd',
      tradeName: 'Apex Stores',
      gstin: '27AABCA1234A1Z5',
      stateCode: '27',
      stateName: 'Maharashtra',
      addressLine1: 'Shop 42, Phoenix Marketcity',
      city: 'Mumbai',
      pincode: '400070',
      phone: '9876543210',
      email: 'billing@apexstores.com',
      bankName: 'HDFC Bank',
      bankAccountNumber: '50200012345678',
      bankIfsc: 'HDFC0000240',
      upiId: 'apexstores@hdfcbank',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    testCustomer = Party(
      id: 'cust-001',
      businessId: 'biz-001',
      partyType: PartyType.customer,
      name: 'Rohan Sharma',
      phone: '9123456780',
      gstin: '27XYZPA1234B1Z2',
      billingAddressLine1: 'Flat 302, Palm Heights',
      billingCity: 'Mumbai',
      billingPincode: '400053',
      billingStateCode: '27',
      billingStateName: 'Maharashtra',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    testSettings = BusinessSettings(
      id: 'set-001',
      businessId: 'biz-001',
      printBusinessLogo: true,
      printBankDetails: true,
      printUpiQr: true,
      thermalPrinterType: '80mm',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    final testItem = InvoiceItem(
      id: 'item-001',
      invoiceId: 'inv-001',
      productId: 'prod-001',
      taxRateId: 'tax-001',
      productName: 'Industrial Wireless Router AX3000',
      hsnSac: '851762',
      quantityScaled: 1000,
      unitCode: 'PCS',
      ratePaise: 100000,
      discountPaise: 5000,
      taxableAmountPaise: 95000,
      cgstRateBasisPoints: 900,
      cgstAmountPaise: 8550,
      sgstRateBasisPoints: 900,
      sgstAmountPaise: 8550,
      igstRateBasisPoints: 0,
      igstAmountPaise: 0,
      cessRateBasisPoints: 0,
      cessAmountPaise: 0,
      totalAmountPaise: 112100,
      createdAt: DateTime.utc(2026, 3, 15),
      updatedAt: DateTime.utc(2026, 3, 15),
    );

    testInvoice = Invoice(
      id: 'inv-001',
      businessId: 'biz-001',
      customerId: 'cust-001',
      customerName: 'Rohan Sharma',
      customerPhone: '9123456780',
      customerGstin: '27XYZPA1234B1Z2',
      invoiceNumber: 'INV-2026-0001',
      invoiceDate: DateTime.utc(2026, 3, 15),
      dueDate: DateTime.utc(2026, 3, 30),
      placeOfSupplyStateCode: '27',
      invoiceType: InvoiceType.taxInvoice,
      status: InvoiceStatus.paid,
      subtotalPaise: 100000,
      discountPaise: 5000,
      taxableAmountPaise: 95000,
      cgstPaise: 8550,
      sgstPaise: 8550,
      igstPaise: 0,
      cessPaise: 0,
      roundOffPaise: 0,
      totalAmountPaise: 112100,
      paidAmountPaise: 112100,
      balanceAmountPaise: 0,
      notes: 'Thank you for your business!',
      items: [testItem],
      createdAt: DateTime.utc(2026, 3, 15),
      updatedAt: DateTime.utc(2026, 3, 15),
    );
  });

  group('PrintingService', () {
    test('PrintFormat enum parses strings accurately', () {
      expect(PrintFormat.fromString('80mm'), equals(PrintFormat.thermal80mm));
      expect(PrintFormat.fromString('thermal80mm'), equals(PrintFormat.thermal80mm));
      expect(PrintFormat.fromString('58mm'), equals(PrintFormat.thermal58mm));
      expect(PrintFormat.fromString('thermal58mm'), equals(PrintFormat.thermal58mm));
      expect(PrintFormat.fromString('a4'), equals(PrintFormat.a4));
      expect(PrintFormat.fromString('unknown'), equals(PrintFormat.a4));

      expect(PrintFormat.a4.displayName, equals('Standard A4'));
      expect(PrintFormat.thermal80mm.displayName, equals('80mm POS Thermal'));
      expect(PrintFormat.thermal58mm.displayName, equals('58mm POS Thermal'));
    });

    test('generateInvoiceDocument generates valid PDF bytes for all formats', () async {
      final a4Bytes = await printerService.generateInvoiceDocument(
        invoice: testInvoice,
        business: testBusiness,
        customer: testCustomer,
        settings: testSettings,
        format: PrintFormat.a4,
      );
      expect(a4Bytes.isNotEmpty, isTrue);
      // Valid PDF magic header %PDF-
      expect(String.fromCharCodes(a4Bytes.take(4)), equals('%PDF'));

      final thermal80Bytes = await printerService.generateInvoiceDocument(
        invoice: testInvoice,
        business: testBusiness,
        customer: testCustomer,
        settings: testSettings,
        format: PrintFormat.thermal80mm,
      );
      expect(thermal80Bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(thermal80Bytes.take(4)), equals('%PDF'));

      final thermal58Bytes = await printerService.generateInvoiceDocument(
        invoice: testInvoice,
        business: testBusiness,
        customer: testCustomer,
        settings: testSettings,
        format: PrintFormat.thermal58mm,
      );
      expect(thermal58Bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(thermal58Bytes.take(4)), equals('%PDF'));
    });

    test('generateEscPosBytes and generatePlainTextReceipt produce receipt content', () {
      final escPosBytes = printerService.generateEscPosBytes(
        invoice: testInvoice,
        business: testBusiness,
        customer: testCustomer,
        settings: testSettings,
        format: PrintFormat.thermal80mm,
        kickCashDrawer: true,
      );
      expect(escPosBytes.isNotEmpty, isTrue);

      final plainText = printerService.generatePlainTextReceipt(
        invoice: testInvoice,
        business: testBusiness,
        customer: testCustomer,
        settings: testSettings,
        format: PrintFormat.thermal80mm,
      );
      expect(plainText.contains('INV-2026-0001'), isTrue);
      expect(plainText.contains('Apex Stores'), isTrue);
    });

    test('saveInvoicePdfToFile saves bytes to file on disk', () async {
      final tempDir = await Directory.systemTemp.createTemp('billzo_test_');
      final targetFile = '${tempDir.path}${Platform.pathSeparator}test_invoice.pdf';

      final sampleBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]);
      final savedFile = await printerService.saveInvoicePdfToFile(
        pdfBytes: sampleBytes,
        targetPath: targetFile,
      );

      expect(await savedFile.exists(), isTrue);
      expect(await savedFile.readAsBytes(), equals(sampleBytes));

      // Cleanup
      await tempDir.delete(recursive: true);
    });
  });
}
