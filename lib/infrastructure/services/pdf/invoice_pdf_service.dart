import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_item.dart';
import 'package:billzo/domain/invoice/invoice_type.dart';
import 'package:billzo/domain/party/party.dart';

/// Service responsible for rendering vector-quality PDF documents for Sales Invoices.
///
/// Fully offline, deterministic, and styled according to the Billzo Brand Design System.
/// Supports standard A4 Tax Invoices as well as 80mm and 58mm POS thermal receipts.
class InvoicePdfService {
  InvoicePdfService._();

  static final PdfColor _primaryBlue = PdfColor.fromInt(0xFF2563EB);
  static final PdfColor _darkSlate = PdfColor.fromInt(0xFF0F172A);
  static final PdfColor _neutralText = PdfColor.fromInt(0xFF64748B);
  static final PdfColor _borderColor = PdfColor.fromInt(0xFFE2E8F0);
  static final PdfColor _tableHeaderBg = PdfColor.fromInt(0xFFF8FAFC);
  static final PdfColor _accentGreen = PdfColor.fromInt(0xFF10B981);

  static const String _rupeeSvgData = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path d="M6 3h12v2h-4.5c.8 1.1 1.3 2.5 1.4 4H18v2h-3.1c-.5 3.3-3.2 5.8-6.9 6h-.5l6.5 7h-2.9L5 17v-2h3c2.4 0 4.4-1.6 4.9-3.8H6V9.2h6.8c-.3-1.3-1.4-2.2-2.8-2.2H6V3z"/>
</svg>
''';

  /// Renders a vector Indian Rupee symbol glyph that works offline on any font.
  static pw.Widget _rupeeGlyph({double size = 8.0, PdfColor? color}) {
    final c = color ?? _darkSlate;
    final r = (c.red * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (c.green * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (c.blue * 255).round().toRadixString(16).padLeft(2, '0');
    final hex = '#$r$g$b';
    final svg = _rupeeSvgData.replaceAll('<path ', '<path fill="$hex" ');
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 0.5),
      child: pw.SvgImage(
        svg: svg,
        width: size,
        height: size,
      ),
    );
  }

  /// Formats integer paise into a clean row with the vector Rupee symbol.
  static pw.Widget _rupeeAmount(
    int paise, {
    required pw.Font font,
    double fontSize = 8.5,
    PdfColor? color,
    bool showSign = false,
  }) {
    final absPaise = paise.abs();
    final sign = paise < 0 ? '- ' : (showSign && paise > 0 ? '+ ' : '');
    final formatted = _formatPaise(absPaise);
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (sign.isNotEmpty)
          pw.Text(
            sign,
            style: pw.TextStyle(font: font, fontSize: fontSize, color: color ?? _darkSlate),
          ),
        _rupeeGlyph(size: fontSize * 0.82, color: color),
        pw.SizedBox(width: 1.5),
        pw.Text(
          formatted,
          style: pw.TextStyle(font: font, fontSize: fontSize, color: color ?? _darkSlate),
        ),
      ],
    );
  }

  /// Formats integer paise to standard decimal representation with 0 float conversion.
  static String _formatPaise(int paise) {
    final absPaise = paise.abs();
    final sign = paise < 0 ? '-' : '';
    final r = absPaise ~/ 100;
    final p = (absPaise % 100).toString().padLeft(2, '0');
    return '$sign$r.$p';
  }

  /// Helper to safely load business logo bytes.
  static Uint8List? _resolveLogoBytes(Business business, Uint8List? explicitLogoBytes) {
    if (explicitLogoBytes != null && explicitLogoBytes.isNotEmpty) {
      return explicitLogoBytes;
    }
    if (business.logoPath != null && business.logoPath!.isNotEmpty) {
      try {
        final file = File(business.logoPath!);
        if (file.existsSync()) {
          return file.readAsBytesSync();
        }
      } catch (e) {
        debugPrint('Could not load logo from path ${business.logoPath}: $e');
      }
    }
    return null;
  }

  /// Helper to safely load business authorized signature bytes.
  static Uint8List? _resolveSignatureBytes(Business business, Uint8List? explicitSignatureBytes) {
    if (explicitSignatureBytes != null && explicitSignatureBytes.isNotEmpty) {
      return explicitSignatureBytes;
    }
    if (business.signaturePath != null && business.signaturePath!.isNotEmpty) {
      try {
        final file = File(business.signaturePath!);
        if (file.existsSync()) {
          return file.readAsBytesSync();
        }
      } catch (e) {
        debugPrint('Could not load signature from path ${business.signaturePath}: $e');
      }
    }
    return null;
  }

  /// Builds the standard NPCI UPI payment URL string.
  static String _buildUpiPaymentUrl({
    required Business business,
    required Invoice invoice,
  }) {
    final vpa = business.upiId ?? '';
    final name = Uri.encodeComponent(business.name);
    final amount = _formatPaise(invoice.totalAmountPaise);
    final note = Uri.encodeComponent('Inv ${invoice.invoiceNumber}');
    return 'upi://pay?pa=$vpa&pn=$name&am=$amount&cu=INR&tn=$note';
  }

  /// Generates a standard A4 Tax Invoice PDF as a byte array.
  static Future<Uint8List> generateA4InvoicePdf({
    required Invoice invoice,
    required Business business,
    Party? customer,
    BusinessSettings? settings,
    Uint8List? logoBytes,
    Uint8List? signatureBytes,
  }) async {
    final pdf = pw.Document(
      title: 'Invoice ${invoice.invoiceNumber}',
      author: business.name,
    );

    final fontRegular = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();
    final fontOblique = pw.Font.helveticaOblique();

    final isInterState = invoice.igstPaise > 0;
    final printLogo = (settings?.printBusinessLogo ?? true);
    final effectiveLogoBytes = printLogo ? _resolveLogoBytes(business, logoBytes) : null;
    final effectiveSignatureBytes = _resolveSignatureBytes(business, signatureBytes);
    final isCompositionOrUnregistered = business.gstin == null || business.gstin!.trim().isEmpty;
    final documentTitle = (invoice.invoiceType == InvoiceType.billOfSupply || isCompositionOrUnregistered)
        ? 'BILL OF SUPPLY'
        : invoice.invoiceType.displayName.toUpperCase();
    final printUpi = (settings?.printUpiQr ?? true) && (business.upiId != null && business.upiId!.isNotEmpty);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // 1. Header Banner: Merchant Brand & Invoice Header
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              // Merchant Info (with optional Logo)
              pw.Expanded(
                flex: 6,
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (effectiveLogoBytes != null) ...[
                      pw.Container(
                        width: 60,
                        height: 60,
                        margin: const pw.EdgeInsets.only(right: 12),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: _borderColor),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                        ),
                        child: pw.ClipRRect(
                          horizontalRadius: 6,
                          verticalRadius: 6,
                          child: pw.Image(
                            pw.MemoryImage(effectiveLogoBytes),
                            fit: pw.BoxFit.contain,
                          ),
                        ),
                      ),
                    ],
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            business.name,
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 18,
                              color: _darkSlate,
                            ),
                          ),
                          if (business.tradeName != null && business.tradeName != business.name)
                            pw.Text(
                              business.tradeName!,
                              style: pw.TextStyle(font: fontRegular, fontSize: 10, color: _neutralText),
                            ),
                          pw.SizedBox(height: 3),
                          if (business.addressLine1 != null && business.addressLine1!.isNotEmpty)
                            pw.Text(
                              business.addressLine1! + (business.city != null ? ', ${business.city}' : ''),
                              style: pw.TextStyle(font: fontRegular, fontSize: 9, color: _neutralText),
                            ),
                          pw.Text(
                            'State: ${business.stateName} (${business.stateCode})',
                            style: pw.TextStyle(font: fontRegular, fontSize: 9, color: _neutralText),
                          ),
                          if (business.gstin != null && business.gstin!.isNotEmpty)
                            pw.Text(
                              'GSTIN: ${business.gstin}',
                              style: pw.TextStyle(font: fontBold, fontSize: 9, color: _darkSlate),
                            ),
                          if (business.pan != null && business.pan!.isNotEmpty)
                            pw.Text(
                              'PAN: ${business.pan}',
                              style: pw.TextStyle(font: fontRegular, fontSize: 9, color: _neutralText),
                            ),
                          pw.Text(
                            'Phone: ${business.phone}${business.email != null ? ' | Email: ${business.email}' : ''}',
                            style: pw.TextStyle(font: fontRegular, fontSize: 9, color: _neutralText),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(width: 12),

              // Statutory Invoice Metadata Box
              pw.Expanded(
                flex: 4,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _borderColor),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    color: _tableHeaderBg,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            documentTitle,
                            style: pw.TextStyle(font: fontBold, fontSize: 11, color: _primaryBlue),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: pw.BoxDecoration(
                              color: invoice.isFinalized
                                  ? _accentGreen
                                  : (invoice.isCancelled ? PdfColors.red : _neutralText),
                              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                            ),
                            child: pw.Text(
                              invoice.status.displayName.toUpperCase(),
                              style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white),
                            ),
                          ),
                        ],
                      ),
                      pw.Divider(color: _borderColor, height: 10),
                      _metaRow('Invoice No:', invoice.invoiceNumber, fontRegular, fontBold),
                      _metaRow('Date:', invoice.invoiceDate.toIso8601String().substring(0, 10), fontRegular, fontRegular),
                      _metaRow('Due Date:', invoice.dueDate.toIso8601String().substring(0, 10), fontRegular, fontRegular),
                      _metaRow('Place of Supply:', 'State ${invoice.placeOfSupplyStateCode}', fontRegular, fontRegular),
                    ],
                  ),
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 14),

          // 2. Customer (Bill To) Section
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _borderColor),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'BILL TO (CUSTOMER):',
                        style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: _primaryBlue),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        customer?.name ?? invoice.customerName ?? 'Walk-in Customer',
                        style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: _darkSlate),
                      ),
                      if (customer?.companyName != null && customer!.companyName!.isNotEmpty)
                        pw.Text(
                          customer.companyName!,
                          style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: _neutralText),
                        ),
                      if (invoice.customerAddress != null && invoice.customerAddress!.isNotEmpty)
                        pw.Text(
                          invoice.customerAddress!,
                          style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: _neutralText),
                        )
                      else if (customer?.billingAddressLine1 != null)
                        pw.Text(
                          '${customer!.billingAddressLine1!}${customer.billingCity != null ? ', ${customer.billingCity}' : ''} - ${customer.billingPincode ?? ''}',
                          style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: _neutralText),
                        ),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (customer?.gstin != null && customer!.gstin!.isNotEmpty) ...[
                        pw.Text(
                          'Customer GSTIN: ${customer.gstin}',
                          style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: _darkSlate),
                        ),
                      ] else if (invoice.customerGstin != null && invoice.customerGstin!.isNotEmpty) ...[
                        pw.Text(
                          'Customer GSTIN: ${invoice.customerGstin}',
                          style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: _darkSlate),
                        ),
                      ],
                      pw.Text(
                        'Phone: ${customer?.phone ?? invoice.customerPhone ?? 'N/A'}',
                        style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: _neutralText),
                      ),
                      pw.Text(
                        'State: ${customer?.billingStateName ?? ''} (${customer?.billingStateCode ?? invoice.placeOfSupplyStateCode})',
                        style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: _neutralText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 14),

          // 3. Line Items Table
          pw.Table(
            border: pw.TableBorder.all(color: _borderColor, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(24),  // S.No
              1: const pw.FlexColumnWidth(3.5), // Item Name & HSN
              2: const pw.FixedColumnWidth(40),  // HSN/SAC
              3: const pw.FixedColumnWidth(42),  // Qty
              4: const pw.FixedColumnWidth(48),  // Rate
              5: const pw.FixedColumnWidth(42),  // Disc
              6: const pw.FixedColumnWidth(54),  // Taxable
              7: const pw.FixedColumnWidth(44),  // GST Rate
              8: const pw.FixedColumnWidth(58),  // Total
            },
            children: [
              // Table Header
              pw.TableRow(
                decoration: pw.BoxDecoration(color: _tableHeaderBg),
                children: [
                  _tableHeaderCell('#', fontBold),
                  _tableHeaderCell('Item Description', fontBold, align: pw.TextAlign.left),
                  _tableHeaderCell('HSN/SAC', fontBold),
                  _tableHeaderCell('Qty', fontBold),
                  _tableHeaderCellWithRupee('Rate', fontBold),
                  _tableHeaderCellWithRupee('Disc', fontBold),
                  _tableHeaderCellWithRupee('Taxable', fontBold),
                  _tableHeaderCell('GST', fontBold, align: pw.TextAlign.center),
                  _tableHeaderCellWithRupee('Amount', fontBold),
                ],
              ),

              // Item Rows
              for (int i = 0; i < invoice.items.length; i++) ...[
                _buildItemRow(i + 1, invoice.items[i], fontRegular, fontBold),
              ],
            ],
          ),

          pw.SizedBox(height: 14),

          // 4. Financial Summary, Bank, UPI QR Code & Notes Grid
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              // Left: Amount in Words, Bank Details, UPI QR Code, Terms
              pw.Expanded(
                flex: 6,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Amount in Words Box
                    pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: _tableHeaderBg,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                        border: pw.Border.all(color: _borderColor),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'AMOUNT IN WORDS:',
                            style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: _neutralText),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            invoice.amountInWords,
                            style: pw.TextStyle(font: fontBold, fontSize: 9, color: _darkSlate),
                          ),
                        ],
                      ),
                    ),

                    pw.SizedBox(height: 10),

                    // Bank Account & UPI QR Code Row
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Bank Details Box
                        if (settings?.printBankDetails != false &&
                            business.bankAccountNumber != null &&
                            business.bankAccountNumber!.isNotEmpty) ...[
                          pw.Expanded(
                            child: pw.Container(
                              padding: const pw.EdgeInsets.all(8),
                              decoration: pw.BoxDecoration(
                                border: pw.Border.all(color: _borderColor),
                                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                              ),
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text('BANK PAYMENT DETAILS', style: pw.TextStyle(font: fontBold, fontSize: 8, color: _primaryBlue)),
                                  pw.SizedBox(height: 2),
                                  pw.Text('Bank: ${business.bankName ?? ''} | Branch: ${business.bankBranch ?? ''}', style: pw.TextStyle(font: fontRegular, fontSize: 7.5)),
                                  pw.Text('A/C Name: ${business.bankAccountName ?? business.name}', style: pw.TextStyle(font: fontRegular, fontSize: 7.5)),
                                  pw.Text('A/C Number: ${business.bankAccountNumber}', style: pw.TextStyle(font: fontBold, fontSize: 8)),
                                  pw.Text('IFSC Code: ${business.bankIfsc ?? ''}', style: pw.TextStyle(font: fontBold, fontSize: 8)),
                                  if (business.upiId != null && business.upiId!.isNotEmpty)
                                    pw.Text('UPI ID: ${business.upiId}', style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: _primaryBlue)),
                                ],
                              ),
                            ),
                          ),
                          pw.SizedBox(width: 8),
                        ],

                        // UPI QR Code Widget
                        if (printUpi) ...[
                          pw.Container(
                            padding: const pw.EdgeInsets.all(6),
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(color: _borderColor),
                              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                              color: _tableHeaderBg,
                            ),
                            child: pw.Column(
                              children: [
                                pw.BarcodeWidget(
                                  barcode: pw.Barcode.qrCode(),
                                  data: _buildUpiPaymentUrl(business: business, invoice: invoice),
                                  width: 58,
                                  height: 58,
                                ),
                                pw.SizedBox(height: 2),
                                pw.Text(
                                  'Scan & Pay (UPI)',
                                  style: pw.TextStyle(font: fontBold, fontSize: 6.5, color: _primaryBlue),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),

                    pw.SizedBox(height: 8),

                    // Terms and Conditions
                    if (invoice.termsAndConditions != null && invoice.termsAndConditions!.isNotEmpty) ...[
                      pw.Text('TERMS & CONDITIONS:', style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: _neutralText)),
                      pw.Text(invoice.termsAndConditions!, style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: _darkSlate)),
                      pw.SizedBox(height: 4),
                    ],
                    if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
                      pw.Text('NOTES:', style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: _neutralText)),
                      pw.Text(invoice.notes!, style: pw.TextStyle(font: fontOblique, fontSize: 7.5, color: _neutralText)),
                    ],
                  ],
                ),
              ),

              pw.SizedBox(width: 14),

              // Right: Calculations Summary Box
              pw.Expanded(
                flex: 4,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _borderColor),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.Column(
                    children: [
                      _summaryRow(
                        'Taxable Amount:',
                        _rupeeAmount(invoice.taxableAmountPaise, font: fontRegular),
                        fontRegular,
                      ),
                      if (invoice.discountPaise > 0)
                        _summaryRow(
                          'Total Discount:',
                          _rupeeAmount(-invoice.discountPaise, font: fontRegular),
                          fontRegular,
                        ),
                      if (isInterState && invoice.igstPaise > 0) ...[
                        _summaryRow(
                          'IGST:',
                          _rupeeAmount(invoice.igstPaise, font: fontRegular),
                          fontRegular,
                        ),
                      ] else ...[
                        if (invoice.cgstPaise > 0)
                          _summaryRow(
                            'CGST:',
                            _rupeeAmount(invoice.cgstPaise, font: fontRegular),
                            fontRegular,
                          ),
                        if (invoice.sgstPaise > 0)
                          _summaryRow(
                            'SGST:',
                            _rupeeAmount(invoice.sgstPaise, font: fontRegular),
                            fontRegular,
                          ),
                      ],
                      if (invoice.cessPaise > 0)
                        _summaryRow(
                          'Cess:',
                          _rupeeAmount(invoice.cessPaise, font: fontRegular),
                          fontRegular,
                        ),
                      if (invoice.roundOffPaise != 0)
                        _summaryRow(
                          'Round Off:',
                          _rupeeAmount(invoice.roundOffPaise, font: fontRegular, showSign: true),
                          fontRegular,
                        ),
                      pw.Divider(color: _borderColor, height: 8),
                      _summaryRow(
                        'Total Amount:',
                        _rupeeAmount(
                          invoice.totalAmountPaise,
                          font: fontBold,
                          fontSize: 11.5,
                          color: _primaryBlue,
                        ),
                        fontBold,
                      ),
                      pw.SizedBox(height: 3),
                      _summaryRow(
                        'Amount Paid:',
                        _rupeeAmount(
                          invoice.paidAmountPaise,
                          font: fontBold,
                          fontSize: 9,
                          color: _accentGreen,
                        ),
                        fontRegular,
                      ),
                      pw.SizedBox(height: 3),
                      _summaryRow(
                        'Balance Due:',
                        _rupeeAmount(
                          invoice.balanceAmountPaise,
                          font: fontBold,
                          fontSize: 9.5,
                          color: invoice.balanceAmountPaise > 0 ? PdfColors.red : _darkSlate,
                        ),
                        fontBold,
                      ),
                      pw.SizedBox(height: 5),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Payment Status:', style: pw.TextStyle(font: fontBold, fontSize: 8, color: _neutralText)),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: pw.BoxDecoration(
                              color: invoice.isPaid
                                  ? _accentGreen
                                  : (invoice.isPartiallyPaid ? PdfColors.orange : PdfColors.red),
                              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                            ),
                            child: pw.Text(
                              invoice.paymentStatus.code,
                              style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: PdfColors.white),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 32),

          // 5. Authorized Signatory Footer
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Generated offline with Billzo', style: pw.TextStyle(font: fontOblique, fontSize: 7, color: _neutralText)),
                  pw.Text('Billing. Business. Simple.', style: pw.TextStyle(font: fontRegular, fontSize: 7, color: _neutralText)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('For ${business.name}', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                  if (effectiveSignatureBytes != null) ...[
                    pw.Container(
                      height: 36,
                      width: 120,
                      alignment: pw.Alignment.bottomRight,
                      child: pw.Image(
                        pw.MemoryImage(effectiveSignatureBytes),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                  ] else ...[
                    pw.SizedBox(height: 28),
                  ],
                  pw.Container(width: 130, height: 1, color: _borderColor),
                  pw.SizedBox(height: 3),
                  pw.Text('Authorized Signatory', style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: _neutralText)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  /// Generates a POS thermal receipt PDF (80mm or 58mm) as a byte array.
  static Future<Uint8List> generateThermalReceiptPdf({
    required Invoice invoice,
    required Business business,
    Party? customer,
    BusinessSettings? settings,
    required double widthMm,
    Uint8List? logoBytes,
  }) async {
    final pdf = pw.Document();
    final fontRegular = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();

    final is58mm = widthMm <= 60;
    final pageFormat = PdfPageFormat(
      widthMm * PdfPageFormat.mm,
      double.infinity,
      marginAll: is58mm ? 2 * PdfPageFormat.mm : 3 * PdfPageFormat.mm,
    );

    final printUpi = (settings?.printUpiQr ?? true) && (business.upiId != null && business.upiId!.isNotEmpty);

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Store Header
              pw.Text(
                business.name,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 10 : 12),
              ),
              if (business.addressLine1 != null)
                pw.Text(
                  business.addressLine1!,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: fontRegular, fontSize: is58mm ? 7 : 8),
                ),
              if (business.gstin != null)
                pw.Text(
                  'GSTIN: ${business.gstin}',
                  style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 7 : 8),
                ),
              pw.Text(
                'Ph: ${business.phone}',
                style: pw.TextStyle(font: fontRegular, fontSize: is58mm ? 7 : 8),
              ),

              pw.Divider(height: 8, thickness: 0.5),

              // Invoice Details
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Inv: ${invoice.invoiceNumber}', style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 7 : 8)),
                  pw.Text(invoice.invoiceDate.toIso8601String().substring(0, 10), style: pw.TextStyle(font: fontRegular, fontSize: is58mm ? 7 : 8)),
                ],
              ),
              if (customer != null || invoice.customerName != null) ...[
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    'Cust: ${customer?.name ?? invoice.customerName}',
                    style: pw.TextStyle(font: fontRegular, fontSize: is58mm ? 7 : 8),
                  ),
                ),
              ],

              pw.Divider(height: 8, thickness: 0.5),

              // Items List
              for (final item in invoice.items) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        item.productName,
                        style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 7 : 8),
                      ),
                    ),
                    pw.Text(
                      '${item.quantity.toStringAsFixed(item.unitCode == 'PCS' ? 0 : 2)}x${_formatPaise(item.ratePaise)}',
                      style: pw.TextStyle(font: fontRegular, fontSize: is58mm ? 6.5 : 7.5),
                    ),
                    pw.SizedBox(width: 4),
                    pw.Text(
                      _formatPaise(item.totalAmountPaise),
                      style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 7 : 8),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
              ],

              pw.Divider(height: 8, thickness: 0.5),

              // Totals
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Taxable:', style: pw.TextStyle(font: fontRegular, fontSize: is58mm ? 7 : 8)),
                  _rupeeAmount(invoice.taxableAmountPaise, font: fontRegular, fontSize: is58mm ? 7 : 8),
                ],
              ),
              if (invoice.cgstPaise > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('CGST:', style: pw.TextStyle(font: fontRegular, fontSize: is58mm ? 7 : 8)),
                    _rupeeAmount(invoice.cgstPaise, font: fontRegular, fontSize: is58mm ? 7 : 8),
                  ],
                ),
              if (invoice.sgstPaise > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('SGST:', style: pw.TextStyle(font: fontRegular, fontSize: is58mm ? 7 : 8)),
                    _rupeeAmount(invoice.sgstPaise, font: fontRegular, fontSize: is58mm ? 7 : 8),
                  ],
                ),
              if (invoice.igstPaise > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('IGST:', style: pw.TextStyle(font: fontRegular, fontSize: is58mm ? 7 : 8)),
                    _rupeeAmount(invoice.igstPaise, font: fontRegular, fontSize: is58mm ? 7 : 8),
                  ],
                ),
              if (invoice.roundOffPaise != 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Round Off:', style: pw.TextStyle(font: fontRegular, fontSize: is58mm ? 7 : 8)),
                    _rupeeAmount(invoice.roundOffPaise, font: fontRegular, fontSize: is58mm ? 7 : 8, showSign: true),
                  ],
                ),

              pw.Divider(height: 6, thickness: 1),

              // Grand Total
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL:', style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 9.5 : 11)),
                  _rupeeAmount(invoice.totalAmountPaise, font: fontBold, fontSize: is58mm ? 9.5 : 11),
                ],
              ),

              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Paid:', style: pw.TextStyle(font: fontRegular, fontSize: is58mm ? 7 : 8)),
                  _rupeeAmount(invoice.paidAmountPaise, font: fontRegular, fontSize: is58mm ? 7 : 8),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Balance Due:', style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 7 : 8)),
                  _rupeeAmount(invoice.balanceAmountPaise, font: fontBold, fontSize: is58mm ? 7 : 8),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Status:', style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 7 : 8)),
                  pw.Text(invoice.paymentStatus.code, style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 7 : 8)),
                ],
              ),

              // Thermal UPI QR Code
              if (printUpi) ...[
                pw.SizedBox(height: 6),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: _buildUpiPaymentUrl(business: business, invoice: invoice),
                  width: is58mm ? 48 : 58,
                  height: is58mm ? 48 : 58,
                ),
                pw.SizedBox(height: 2),
                pw.Text('Scan to Pay via UPI', style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 6.5 : 7.5)),
                pw.Text('UPI: ${business.upiId}', style: pw.TextStyle(font: fontRegular, fontSize: is58mm ? 6 : 7)),
              ],

              pw.SizedBox(height: 8),
              pw.Text('Thank You! Visit Again.', style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 7 : 8)),
              pw.Text('Powered by Billzo', style: pw.TextStyle(font: fontRegular, fontSize: is58mm ? 6 : 7, color: PdfColors.grey700)),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // --- Helpers ---

  static pw.Widget _tableHeaderCell(String text, pw.Font font, {pw.TextAlign align = pw.TextAlign.right}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(font: font, fontSize: 8, color: _darkSlate),
      ),
    );
  }

  static pw.TableRow _buildItemRow(int sNo, InvoiceItem item, pw.Font fontRegular, pw.Font fontBold) {
    final taxRateBps = item.igstRateBasisPoints > 0
        ? item.igstRateBasisPoints
        : (item.cgstRateBasisPoints + item.sgstRateBasisPoints);
    final taxDisplay = '${(taxRateBps / 100).toStringAsFixed(0)}%';

    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text('$sNo', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: fontRegular, fontSize: 7.5)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(item.productName, style: pw.TextStyle(font: fontBold, fontSize: 8, color: _darkSlate)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(item.hsnSac ?? '-', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: fontRegular, fontSize: 7.5)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text('${item.quantity.toStringAsFixed(item.unitCode == 'PCS' ? 0 : 2)} ${item.unitCode}', textAlign: pw.TextAlign.right, style: pw.TextStyle(font: fontRegular, fontSize: 7.5)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(_formatPaise(item.ratePaise), textAlign: pw.TextAlign.right, style: pw.TextStyle(font: fontRegular, fontSize: 7.5)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(_formatPaise(item.discountPaise), textAlign: pw.TextAlign.right, style: pw.TextStyle(font: fontRegular, fontSize: 7.5)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(_formatPaise(item.taxableAmountPaise), textAlign: pw.TextAlign.right, style: pw.TextStyle(font: fontRegular, fontSize: 7.5)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(taxDisplay, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: fontRegular, fontSize: 7.5)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(_formatPaise(item.totalAmountPaise), textAlign: pw.TextAlign.right, style: pw.TextStyle(font: fontBold, fontSize: 8)),
        ),
      ],
    );
  }

  static pw.Widget _metaRow(String label, String value, pw.Font labelFont, pw.Font valueFont) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: labelFont, fontSize: 8, color: _neutralText)),
          pw.Text(value, style: pw.TextStyle(font: valueFont, fontSize: 8, color: _darkSlate)),
        ],
      ),
    );
  }

  static pw.Widget _tableHeaderCellWithRupee(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            '$text (',
            style: pw.TextStyle(font: font, fontSize: 8, color: _darkSlate),
          ),
          _rupeeGlyph(size: 6.8, color: _darkSlate),
          pw.Text(
            ')',
            style: pw.TextStyle(font: font, fontSize: 8, color: _darkSlate),
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryRow(
    String label,
    pw.Widget valueWidget,
    pw.Font labelFont,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: labelFont, fontSize: 8.5, color: _neutralText)),
          valueWidget,
        ],
      ),
    );
  }
}
