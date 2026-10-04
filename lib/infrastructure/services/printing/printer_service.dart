import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/infrastructure/services/pdf/invoice_pdf_service.dart';
import 'package:billzo/infrastructure/services/printing/esc_pos_receipt_formatter.dart';

/// Supported print and receipt formats.
enum PrintFormat {
  a4,
  thermal80mm,
  thermal58mm;

  String get displayName {
    switch (this) {
      case PrintFormat.a4:
        return 'Standard A4';
      case PrintFormat.thermal80mm:
        return '80mm POS Thermal';
      case PrintFormat.thermal58mm:
        return '58mm POS Thermal';
    }
  }

  static PrintFormat fromString(String val) {
    switch (val.toLowerCase()) {
      case '80mm':
      case 'thermal80mm':
        return PrintFormat.thermal80mm;
      case '58mm':
      case 'thermal58mm':
        return PrintFormat.thermal58mm;
      default:
        return PrintFormat.a4;
    }
  }
}

/// Abstract contract for printing operations across Windows and future mobile platforms.
abstract class IPrinterService {
  /// Generates printable PDF document bytes for an invoice according to the specified format.
  Future<Uint8List> generateInvoiceDocument({
    required Invoice invoice,
    required Business business,
    Party? customer,
    BusinessSettings? settings,
    PrintFormat format = PrintFormat.a4,
    Uint8List? logoBytes,
    Uint8List? signatureBytes,
  });

  /// Generates raw ESC/POS binary command bytes for POS receipt printers.
  Uint8List generateEscPosBytes({
    required Invoice invoice,
    required Business business,
    Party? customer,
    BusinessSettings? settings,
    required PrintFormat format,
    bool kickCashDrawer = false,
  });

  /// Formats the invoice as a formatted plain text receipt for thermal preview or clipboard.
  String generatePlainTextReceipt({
    required Invoice invoice,
    required Business business,
    Party? customer,
    BusinessSettings? settings,
    required PrintFormat format,
  });

  /// Dispatches the invoice to the system print spooler without blocking the application UI.
  Future<bool> printInvoice({
    required Invoice invoice,
    required Business business,
    Party? customer,
    BusinessSettings? settings,
    PrintFormat format = PrintFormat.a4,
    Uint8List? logoBytes,
    Uint8List? signatureBytes,
  });

  /// Shares the invoice PDF via standard system intents or file dialogs.
  Future<void> shareInvoicePdf({
    required Invoice invoice,
    required Business business,
    Party? customer,
    BusinessSettings? settings,
    PrintFormat format = PrintFormat.a4,
    Uint8List? logoBytes,
    Uint8List? signatureBytes,
  });

  /// Saves the generated PDF directly to a local destination file path.
  Future<File> saveInvoicePdfToFile({
    required Uint8List pdfBytes,
    required String targetPath,
  });
}

/// Production implementation of [IPrinterService] using the `printing` and `pdf` packages.
class PrintingService implements IPrinterService {
  const PrintingService();

  @override
  Future<Uint8List> generateInvoiceDocument({
    required Invoice invoice,
    required Business business,
    Party? customer,
    BusinessSettings? settings,
    PrintFormat format = PrintFormat.a4,
    Uint8List? logoBytes,
    Uint8List? signatureBytes,
  }) async {
    switch (format) {
      case PrintFormat.a4:
        return InvoicePdfService.generateA4InvoicePdf(
          invoice: invoice,
          business: business,
          customer: customer,
          settings: settings,
          logoBytes: logoBytes,
          signatureBytes: signatureBytes,
        );
      case PrintFormat.thermal80mm:
        return InvoicePdfService.generateThermalReceiptPdf(
          invoice: invoice,
          business: business,
          customer: customer,
          settings: settings,
          widthMm: 80,
          logoBytes: logoBytes,
        );
      case PrintFormat.thermal58mm:
        return InvoicePdfService.generateThermalReceiptPdf(
          invoice: invoice,
          business: business,
          customer: customer,
          settings: settings,
          widthMm: 58,
          logoBytes: logoBytes,
        );
    }
  }

  @override
  Uint8List generateEscPosBytes({
    required Invoice invoice,
    required Business business,
    Party? customer,
    BusinessSettings? settings,
    required PrintFormat format,
    bool kickCashDrawer = false,
  }) {
    return EscPosReceiptFormatter.generateReceiptBytes(
      invoice: invoice,
      business: business,
      customer: customer,
      settings: settings,
      format: format,
      kickCashDrawer: kickCashDrawer,
    );
  }

  @override
  String generatePlainTextReceipt({
    required Invoice invoice,
    required Business business,
    Party? customer,
    BusinessSettings? settings,
    required PrintFormat format,
  }) {
    return EscPosReceiptFormatter.formatAsPlainText(
      invoice: invoice,
      business: business,
      customer: customer,
      settings: settings,
      format: format,
    );
  }

  @override
  Future<bool> printInvoice({
    required Invoice invoice,
    required Business business,
    Party? customer,
    BusinessSettings? settings,
    PrintFormat format = PrintFormat.a4,
    Uint8List? logoBytes,
    Uint8List? signatureBytes,
  }) async {
    try {
      final docBytes = await generateInvoiceDocument(
        invoice: invoice,
        business: business,
        customer: customer,
        settings: settings,
        format: format,
        logoBytes: logoBytes,
        signatureBytes: signatureBytes,
      );

      final pageFormat = format == PrintFormat.a4
          ? PdfPageFormat.a4
          : (format == PrintFormat.thermal80mm
              ? const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 2 * PdfPageFormat.mm)
              : const PdfPageFormat(58 * PdfPageFormat.mm, double.infinity, marginAll: 2 * PdfPageFormat.mm));

      return await Printing.layoutPdf(
        onLayout: (PdfPageFormat _) async => docBytes,
        name: 'Invoice_${invoice.invoiceNumber}',
        format: pageFormat,
      );
    } catch (e) {
      debugPrint('Printing error: $e');
      return false;
    }
  }

  @override
  Future<void> shareInvoicePdf({
    required Invoice invoice,
    required Business business,
    Party? customer,
    BusinessSettings? settings,
    PrintFormat format = PrintFormat.a4,
    Uint8List? logoBytes,
    Uint8List? signatureBytes,
  }) async {
    final pdfBytes = await generateInvoiceDocument(
      invoice: invoice,
      business: business,
      customer: customer,
      settings: settings,
      format: format,
      logoBytes: logoBytes,
      signatureBytes: signatureBytes,
    );

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'Invoice_${invoice.invoiceNumber}.pdf',
    );
  }

  @override
  Future<File> saveInvoicePdfToFile({
    required Uint8List pdfBytes,
    required String targetPath,
  }) async {
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    return await file.writeAsBytes(pdfBytes, flush: true);
  }
}
