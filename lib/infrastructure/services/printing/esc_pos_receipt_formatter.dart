import 'dart:convert';
import 'dart:typed_data';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/infrastructure/services/printing/printer_service.dart';

/// Industrial-grade ESC/POS byte sequence formatter for POS thermal receipt printers.
///
/// Supports standard 80mm (48-column) and 58mm (32-column) paper rolls.
/// 100% offline, deterministic, zero floating-point arithmetic.
class EscPosReceiptFormatter {
  EscPosReceiptFormatter._();

  // --- ESC/POS Command Byte Constants ---
  static const int esc = 0x1B;
  static const int gs = 0x1D;
  static const int lf = 0x0A;

  // Initialize printer
  static const List<int> cmdInit = [esc, 0x40];

  // Alignment
  static const List<int> cmdAlignLeft = [esc, 0x61, 0x00];
  static const List<int> cmdAlignCenter = [esc, 0x61, 0x01];
  static const List<int> cmdAlignRight = [esc, 0x61, 0x02];

  // Font Emphasis (Bold)
  static const List<int> cmdBoldOn = [esc, 0x45, 0x01];
  static const List<int> cmdBoldOff = [esc, 0x45, 0x00];

  // Character Sizing
  static const List<int> cmdSizeNormal = [gs, 0x21, 0x00];
  static const List<int> cmdSizeDoubleHeight = [gs, 0x21, 0x01];
  static const List<int> cmdSizeDoubleWidth = [gs, 0x21, 0x10];
  static const List<int> cmdSizeLarge = [gs, 0x21, 0x11]; // Double height & width

  // Paper Feeding and Cutting
  static const List<int> cmdFeed3Lines = [esc, 0x64, 0x03];
  static const List<int> cmdFeed5Lines = [esc, 0x64, 0x05];
  static const List<int> cmdCutPartial = [gs, 0x56, 0x42, 0x00]; // Feed & partial cut
  static const List<int> cmdCutFull = [gs, 0x56, 0x41, 0x00];    // Feed & full cut

  // Cash Drawer Kick-out
  static const List<int> cmdCashDrawerKick = [esc, 0x70, 0x00, 0x19, 0xFA];

  /// Generates the raw binary ESC/POS byte sequence for an invoice.
  static Uint8List generateReceiptBytes({
    required Invoice invoice,
    required Business business,
    Party? customer,
    BusinessSettings? settings,
    required PrintFormat format,
    bool kickCashDrawer = false,
  }) {
    final buffer = <int>[];
    final columns = format == PrintFormat.thermal58mm ? 32 : 48;

    // 1. Initialize
    buffer.addAll(cmdInit);

    // 2. Optional: Kick Cash Drawer
    if (kickCashDrawer) {
      buffer.addAll(cmdCashDrawerKick);
    }

    // 3. Store Header (Centered)
    buffer.addAll(cmdAlignCenter);
    buffer.addAll(cmdBoldOn);
    buffer.addAll(cmdSizeDoubleHeight);
    buffer.addAll(_encodeText('${business.name}\n'));
    buffer.addAll(cmdSizeNormal);
    buffer.addAll(cmdBoldOff);

    if (business.addressLine1 != null && business.addressLine1!.isNotEmpty) {
      buffer.addAll(_encodeText('${business.addressLine1!}\n'));
    }
    if (business.city != null && business.city!.isNotEmpty) {
      buffer.addAll(_encodeText('${business.city!}, ${business.stateName}\n'));
    }
    if (business.gstin != null && business.gstin!.isNotEmpty) {
      buffer.addAll(cmdBoldOn);
      buffer.addAll(_encodeText('GSTIN: ${business.gstin!}\n'));
      buffer.addAll(cmdBoldOff);
    }
    buffer.addAll(_encodeText('Phone: ${business.phone}\n'));

    // Divider
    buffer.addAll(_encodeText('${'-' * columns}\n'));

    // 4. Invoice Metadata (Left Aligned)
    buffer.addAll(cmdAlignLeft);
    final dateStr = invoice.invoiceDate.toIso8601String().substring(0, 10);
    buffer.addAll(_encodeText(_formatRow('Inv: ${invoice.invoiceNumber}', dateStr, columns)));

    final custName = customer?.name ?? invoice.customerName;
    if (custName != null && custName.isNotEmpty) {
      buffer.addAll(_encodeText(_truncateOrWrap('Cust: $custName', columns)));
    }
    final custGstin = customer?.gstin ?? invoice.customerGstin;
    if (custGstin != null && custGstin.isNotEmpty) {
      buffer.addAll(_encodeText('GSTIN: $custGstin\n'));
    }

    // Divider
    buffer.addAll(_encodeText('${'-' * columns}\n'));

    // 5. Line Items Table Header
    buffer.addAll(cmdBoldOn);
    if (columns == 48) {
      // 80mm Column Layout: Name(24), Qty(6), Rate(8), Total(10)
      buffer.addAll(_encodeText(
          '${_padRight('Item', 24)}${_padLeft('Qty', 6)}${_padLeft('Rate', 8)}${_padLeft('Total', 10)}\n'));
    } else {
      // 58mm Column Layout: Name(14), Qty(4), Rate(6), Total(8)
      buffer.addAll(_encodeText(
          '${_padRight('Item', 14)}${_padLeft('Qty', 4)}${_padLeft('Rate', 6)}${_padLeft('Total', 8)}\n'));
    }
    buffer.addAll(cmdBoldOff);
    buffer.addAll(_encodeText('${'-' * columns}\n'));

    // Line Items Content
    for (final item in invoice.items) {
      final qtyFormatted = item.quantity.toStringAsFixed(item.unitCode == 'PCS' ? 0 : 2);
      final rateFormatted = _formatPaise(item.ratePaise);
      final totalFormatted = _formatPaise(item.totalAmountPaise);

      if (columns == 48) {
        // 80mm
        final name = item.productName.length > 23
            ? '${item.productName.substring(0, 20)}...'
            : item.productName;
        final line =
            '${_padRight(name, 24)}${_padLeft(qtyFormatted, 6)}${_padLeft(rateFormatted, 8)}${_padLeft(totalFormatted, 10)}\n';
        buffer.addAll(_encodeText(line));
      } else {
        // 58mm
        final name = item.productName.length > 13
            ? '${item.productName.substring(0, 11)}..'
            : item.productName;
        final line =
            '${_padRight(name, 14)}${_padLeft(qtyFormatted, 4)}${_padLeft(rateFormatted, 6)}${_padLeft(totalFormatted, 8)}\n';
        buffer.addAll(_encodeText(line));
      }
    }

    buffer.addAll(_encodeText('${'-' * columns}\n'));

    // 6. Financial Summary (Right Aligned or Two-Column Justified)
    buffer.addAll(_encodeText(_formatRow('Taxable Amount:', _formatPaise(invoice.taxableAmountPaise), columns)));

    if (invoice.discountPaise > 0) {
      buffer.addAll(_encodeText(_formatRow('Discount:', '-${_formatPaise(invoice.discountPaise)}', columns)));
    }

    if (invoice.igstPaise > 0) {
      buffer.addAll(_encodeText(_formatRow('IGST:', _formatPaise(invoice.igstPaise), columns)));
    } else {
      if (invoice.cgstPaise > 0) {
        buffer.addAll(_encodeText(_formatRow('CGST:', _formatPaise(invoice.cgstPaise), columns)));
      }
      if (invoice.sgstPaise > 0) {
        buffer.addAll(_encodeText(_formatRow('SGST:', _formatPaise(invoice.sgstPaise), columns)));
      }
    }

    if (invoice.cessPaise > 0) {
      buffer.addAll(_encodeText(_formatRow('Cess:', _formatPaise(invoice.cessPaise), columns)));
    }

    if (invoice.roundOffPaise != 0) {
      final sign = invoice.roundOffPaise > 0 ? '+' : '';
      buffer.addAll(_encodeText(_formatRow('Round Off:', '$sign${_formatPaise(invoice.roundOffPaise)}', columns)));
    }

    // Heavy Divider
    buffer.addAll(_encodeText('${'=' * columns}\n'));

    // 7. Grand Total
    buffer.addAll(cmdBoldOn);
    buffer.addAll(cmdSizeDoubleHeight);
    buffer.addAll(_encodeText(_formatRow('TOTAL (INR):', _formatPaise(invoice.totalAmountPaise), columns)));
    buffer.addAll(cmdSizeNormal);
    buffer.addAll(cmdBoldOff);

    buffer.addAll(_encodeText(_formatRow('Paid:', _formatPaise(invoice.paidAmountPaise), columns)));
    buffer.addAll(_encodeText(_formatRow('Balance Due:', _formatPaise(invoice.balanceAmountPaise), columns)));
    buffer.addAll(_encodeText(_formatRow('Payment Status:', invoice.paymentStatus.code, columns)));
    buffer.addAll(_encodeText('${'-' * columns}\n'));

    // 8. UPI QR Code (if configured)
    final printUpi = settings?.printUpiQr ?? true;
    if (printUpi && business.upiId != null && business.upiId!.isNotEmpty) {
      buffer.addAll(cmdAlignCenter);
      final upiUrl = 'upi://pay?pa=${business.upiId}&pn=${Uri.encodeComponent(business.name)}&am=${_formatPaise(invoice.totalAmountPaise)}&cu=INR&tn=${Uri.encodeComponent(invoice.invoiceNumber)}';
      
      // ESC/POS Native QR Code Commands
      buffer.addAll(_buildQrCodeCommands(upiUrl));
      buffer.addAll(_encodeText('Scan to Pay via UPI\n'));
      buffer.addAll(_encodeText('UPI ID: ${business.upiId}\n'));
      buffer.addAll(_encodeText('${'-' * columns}\n'));
    }

    // 9. Footer & Branding
    buffer.addAll(cmdAlignCenter);
    buffer.addAll(cmdBoldOn);
    buffer.addAll(_encodeText('Thank You! Visit Again.\n'));
    buffer.addAll(cmdBoldOff);
    buffer.addAll(_encodeText('Generated offline with Billzo\n'));
    buffer.addAll(_encodeText('Billing. Business. Simple.\n'));

    // 10. Feed & Cut
    buffer.addAll(cmdFeed5Lines);
    buffer.addAll(cmdCutPartial);

    return Uint8List.fromList(buffer);
  }

  /// Formats the invoice as a formatted plain text string for screen preview or clipboard copying.
  static String formatAsPlainText({
    required Invoice invoice,
    required Business business,
    Party? customer,
    BusinessSettings? settings,
    required PrintFormat format,
  }) {
    final buffer = StringBuffer();
    final columns = format == PrintFormat.thermal58mm ? 32 : 48;
    final storeName = business.tradeName != null && business.tradeName!.isNotEmpty
        ? business.tradeName!
        : business.name;
    buffer.writeln(_centerText(storeName, columns));
    if (business.tradeName != null &&
        business.tradeName!.isNotEmpty &&
        business.tradeName != business.name) {
      buffer.writeln(_centerText('(${business.name})', columns));
    }
    if (business.addressLine1 != null && business.addressLine1!.isNotEmpty) {
      buffer.writeln(_centerText(business.addressLine1!, columns));
    }
    if (business.city != null && business.city!.isNotEmpty) {
      buffer.writeln(_centerText('${business.city!}, ${business.stateName}', columns));
    }
    if (business.gstin != null && business.gstin!.isNotEmpty) {
      buffer.writeln(_centerText('GSTIN: ${business.gstin!}', columns));
    }
    buffer.writeln(_centerText('Phone: ${business.phone}', columns));
    buffer.writeln('-' * columns);

    final dateStr = invoice.invoiceDate.toIso8601String().substring(0, 10);
    buffer.write(_formatRow('Inv: ${invoice.invoiceNumber}', dateStr, columns));

    final custName = customer?.name ?? invoice.customerName;
    if (custName != null && custName.isNotEmpty) {
      buffer.write(_truncateOrWrap('Cust: $custName', columns));
    }
    final custGstin = customer?.gstin ?? invoice.customerGstin;
    if (custGstin != null && custGstin.isNotEmpty) {
      buffer.writeln('GSTIN: $custGstin');
    }
    buffer.writeln('-' * columns);

    // Items
    if (columns == 48) {
      buffer.writeln(
          '${_padRight('Item', 24)}${_padLeft('Qty', 6)}${_padLeft('Rate', 8)}${_padLeft('Total', 10)}');
    } else {
      buffer.writeln(
          '${_padRight('Item', 14)}${_padLeft('Qty', 4)}${_padLeft('Rate', 6)}${_padLeft('Total', 8)}');
    }
    buffer.writeln('-' * columns);

    for (final item in invoice.items) {
      final qtyFormatted = item.quantity.toStringAsFixed(item.unitCode == 'PCS' ? 0 : 2);
      final rateFormatted = _formatPaise(item.ratePaise);
      final totalFormatted = _formatPaise(item.totalAmountPaise);

      if (columns == 48) {
        final name = item.productName.length > 23
            ? '${item.productName.substring(0, 20)}...'
            : item.productName;
        buffer.writeln(
            '${_padRight(name, 24)}${_padLeft(qtyFormatted, 6)}${_padLeft(rateFormatted, 8)}${_padLeft(totalFormatted, 10)}');
      } else {
        final name = item.productName.length > 13
            ? '${item.productName.substring(0, 11)}..'
            : item.productName;
        buffer.writeln(
            '${_padRight(name, 14)}${_padLeft(qtyFormatted, 4)}${_padLeft(rateFormatted, 6)}${_padLeft(totalFormatted, 8)}');
      }
    }
    buffer.writeln('-' * columns);

    buffer.write(_formatRow('Taxable Amount:', _formatPaise(invoice.taxableAmountPaise), columns));
    if (invoice.discountPaise > 0) {
      buffer.write(_formatRow('Discount:', '-${_formatPaise(invoice.discountPaise)}', columns));
    }
    if (invoice.igstPaise > 0) {
      buffer.write(_formatRow('IGST:', _formatPaise(invoice.igstPaise), columns));
    } else {
      if (invoice.cgstPaise > 0) {
        buffer.write(_formatRow('CGST:', _formatPaise(invoice.cgstPaise), columns));
      }
      if (invoice.sgstPaise > 0) {
        buffer.write(_formatRow('SGST:', _formatPaise(invoice.sgstPaise), columns));
      }
    }
    if (invoice.cessPaise > 0) {
      buffer.write(_formatRow('Cess:', _formatPaise(invoice.cessPaise), columns));
    }
    if (invoice.roundOffPaise != 0) {
      final sign = invoice.roundOffPaise > 0 ? '+' : '';
      buffer.write(_formatRow('Round Off:', '$sign${_formatPaise(invoice.roundOffPaise)}', columns));
    }
    buffer.writeln('=' * columns);
    buffer.write(_formatRow('TOTAL (INR):', _formatPaise(invoice.totalAmountPaise), columns));
    buffer.write(_formatRow('Paid:', _formatPaise(invoice.paidAmountPaise), columns));
    buffer.write(_formatRow('Balance Due:', _formatPaise(invoice.balanceAmountPaise), columns));
    buffer.write(_formatRow('Payment Status:', invoice.paymentStatus.code, columns));
    buffer.writeln('-' * columns);

    if (business.upiId != null && business.upiId!.isNotEmpty) {
      buffer.writeln(_centerText('Scan to Pay via UPI', columns));
      buffer.writeln(_centerText('UPI ID: ${business.upiId}', columns));
      buffer.writeln('-' * columns);
    }

    buffer.writeln(_centerText('Thank You! Visit Again.', columns));
    buffer.writeln(_centerText('Generated offline with Billzo', columns));

    return buffer.toString();
  }

  // --- String & Command Helpers ---

  static List<int> _encodeText(String text) {
    return latin1.encode(text);
  }

  static String _formatPaise(int paise) {
    final absPaise = paise.abs();
    final sign = paise < 0 ? '-' : '';
    final r = absPaise ~/ 100;
    final p = (absPaise % 100).toString().padLeft(2, '0');
    return '$sign$r.$p';
  }

  static String _padRight(String text, int width) {
    if (text.length >= width) return text.substring(0, width);
    return text.padRight(width);
  }

  static String _padLeft(String text, int width) {
    if (text.length >= width) return text.substring(0, width);
    return text.padLeft(width);
  }

  static String _formatRow(String left, String right, int width) {
    final spaceNeeded = width - left.length - right.length;
    if (spaceNeeded <= 0) {
      return '$left $right\n';
    }
    return '$left${' ' * spaceNeeded}$right\n';
  }

  static String _centerText(String text, int width) {
    if (text.length >= width) return text;
    final padding = (width - text.length) ~/ 2;
    return '${' ' * padding}$text';
  }

  static String _truncateOrWrap(String text, int width) {
    if (text.length <= width) return '$text\n';
    return '${text.substring(0, width)}\n';
  }

  static List<int> _buildQrCodeCommands(String data) {
    final bytes = latin1.encode(data);
    final len = bytes.length + 3;
    final pL = len % 256;
    final pH = len ~/ 256;

    final commands = <int>[
      // Select QR model (Model 2)
      gs, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00,
      // Select module size (4 dots)
      gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x04,
      // Select error correction (Level M)
      gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31,
      // Store data
      gs, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30,
      ...bytes,
      // Print QR code
      gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30,
    ];
    return commands;
  }
}
