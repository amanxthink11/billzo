import 'package:billzo/domain/reports/aging_analysis_report.dart';
import 'package:billzo/domain/reports/gstr1_report.dart';
import 'package:billzo/domain/reports/stock_valuation_report.dart';

/// RFC 4180 compliant CSV export generator for statutory and management reports.
class CsvExportHelper {
  CsvExportHelper._();

  /// Formats integer paise into a standard 2-decimal string (e.g. 100050 -> "1000.50")
  /// using 100% deterministic integer arithmetic with zero floating-point operations.
  static String formatPaise(int paise) {
    final absPaise = paise.abs();
    final sign = paise < 0 ? '-' : '';
    final r = absPaise ~/ 100;
    final p = (absPaise % 100).toString().padLeft(2, '0');
    return '$sign$r.$p';
  }

  static String _escapeCell(dynamic value) {
    if (value == null) return '';
    final str = value.toString();
    if (str.contains(',') || str.contains('"') || str.contains('\n') || str.contains('\r')) {
      return '"${str.replaceAll('"', '""')}"';
    }
    return str;
  }

  static String _buildRow(List<dynamic> cells) {
    return cells.map(_escapeCell).join(',');
  }

  /// Exports GSTR-1 Table 4 (B2B) to portal-compatible CSV format.
  static String exportGstr1B2b(List<Gstr1B2bInvoice> invoices) {
    final buffer = StringBuffer();
    buffer.writeln(_buildRow([
      'GSTIN/UIN of Recipient',
      'Receiver Name',
      'Invoice Number',
      'Invoice date',
      'Invoice Value',
      'Place Of Supply',
      'Reverse Charge',
      'Invoice Type',
      'Rate',
      'Taxable Value',
      'Central Tax Amount',
      'State Tax Amount',
      'Integrated Tax Amount',
      'Cess Amount',
    ]));

    for (final inv in invoices) {
      final dateStr = '${inv.invoiceDate.day.toString().padLeft(2, '0')}-${inv.invoiceDate.month.toString().padLeft(2, '0')}-${inv.invoiceDate.year}';
      buffer.writeln(_buildRow([
        inv.receiverGstin,
        inv.receiverName,
        inv.invoiceNumber,
        dateStr,
        formatPaise(inv.invoiceValuePaise),
        inv.placeOfSupply,
        inv.reverseCharge,
        inv.invoiceType,
        inv.ratePercent.toStringAsFixed(2),
        formatPaise(inv.taxableValuePaise),
        formatPaise(inv.cgstPaise),
        formatPaise(inv.sgstPaise),
        formatPaise(inv.igstPaise),
        formatPaise(inv.cessPaise),
      ]));
    }

    return buffer.toString();
  }

  /// Exports GSTR-1 Table 5 (B2CL) to portal-compatible CSV format.
  static String exportGstr1B2cl(List<Gstr1B2clInvoice> invoices) {
    final buffer = StringBuffer();
    buffer.writeln(_buildRow([
      'Invoice Number',
      'Invoice date',
      'Invoice Value',
      'Place Of Supply',
      'Rate',
      'Taxable Value',
      'Integrated Tax Amount',
      'Cess Amount',
    ]));

    for (final inv in invoices) {
      final dateStr = '${inv.invoiceDate.day.toString().padLeft(2, '0')}-${inv.invoiceDate.month.toString().padLeft(2, '0')}-${inv.invoiceDate.year}';
      buffer.writeln(_buildRow([
        inv.invoiceNumber,
        dateStr,
        formatPaise(inv.invoiceValuePaise),
        inv.placeOfSupply,
        inv.ratePercent.toStringAsFixed(2),
        formatPaise(inv.taxableValuePaise),
        formatPaise(inv.igstPaise),
        formatPaise(inv.cessPaise),
      ]));
    }

    return buffer.toString();
  }

  /// Exports GSTR-1 Table 7 (B2CS) to portal-compatible CSV format.
  static String exportGstr1B2cs(List<Gstr1B2csItem> items) {
    final buffer = StringBuffer();
    buffer.writeln(_buildRow([
      'Type',
      'Place Of Supply',
      'Rate',
      'Taxable Value',
      'Central Tax Amount',
      'State Tax Amount',
      'Integrated Tax Amount',
      'Cess Amount',
    ]));

    for (final item in items) {
      buffer.writeln(_buildRow([
        'OE',
        item.placeOfSupply,
        item.ratePercent.toStringAsFixed(2),
        formatPaise(item.taxableValuePaise),
        formatPaise(item.cgstPaise),
        formatPaise(item.sgstPaise),
        formatPaise(item.igstPaise),
        formatPaise(item.cessPaise),
      ]));
    }

    return buffer.toString();
  }

  /// Exports GSTR-1 Table 12 (HSN Summary) to portal-compatible CSV format.
  static String exportGstr1Hsn(List<Gstr1HsnSummaryItem> items) {
    final buffer = StringBuffer();
    buffer.writeln(_buildRow([
      'HSN',
      'Description',
      'UQC',
      'Total Quantity',
      'Total Value',
      'Taxable Value',
      'Central Tax Amount',
      'State Tax Amount',
      'Integrated Tax Amount',
      'Cess Amount',
    ]));

    for (final item in items) {
      buffer.writeln(_buildRow([
        item.hsnSac,
        item.description,
        item.uqc,
        item.totalQuantity,
        formatPaise(item.totalValuePaise),
        formatPaise(item.taxableValuePaise),
        formatPaise(item.cgstPaise),
        formatPaise(item.sgstPaise),
        formatPaise(item.igstPaise),
        formatPaise(item.cessPaise),
      ]));
    }

    return buffer.toString();
  }

  /// Exports Receivables Aging report to CSV.
  static String exportReceivablesAging(ReceivablesAgingReport report) {
    final buffer = StringBuffer();
    buffer.writeln(_buildRow([
      'Customer Name',
      'Phone',
      'GSTIN',
      'Total Outstanding',
      'Not Due (Current)',
      '1-30 Days Overdue',
      '31-60 Days Overdue',
      '61-90 Days Overdue',
      '90+ Days Overdue',
    ]));

    for (final item in report.items) {
      buffer.writeln(_buildRow([
        item.partyName,
        item.phone ?? '',
        item.gstin ?? '',
        formatPaise(item.totalOutstandingPaise),
        formatPaise(item.currentPaise),
        formatPaise(item.days1To30Paise),
        formatPaise(item.days31To60Paise),
        formatPaise(item.days61To90Paise),
        formatPaise(item.days90PlusPaise),
      ]));
    }

    buffer.writeln(_buildRow([
      'TOTAL',
      '',
      '',
      formatPaise(report.totalOutstandingPaise),
      formatPaise(report.totalCurrentPaise),
      formatPaise(report.totalDays1To30Paise),
      formatPaise(report.totalDays31To60Paise),
      formatPaise(report.totalDays61To90Paise),
      formatPaise(report.totalDays90PlusPaise),
    ]));

    return buffer.toString();
  }

  /// Exports Payables Aging report to CSV.
  static String exportPayablesAging(PayablesAgingReport report) {
    final buffer = StringBuffer();
    buffer.writeln(_buildRow([
      'Supplier Name',
      'Phone',
      'GSTIN',
      'Total Outstanding',
      'Not Due (Current)',
      '1-30 Days Overdue',
      '31-60 Days Overdue',
      '61-90 Days Overdue',
      '90+ Days Overdue',
    ]));

    for (final item in report.items) {
      buffer.writeln(_buildRow([
        item.partyName,
        item.phone ?? '',
        item.gstin ?? '',
        formatPaise(item.totalOutstandingPaise),
        formatPaise(item.currentPaise),
        formatPaise(item.days1To30Paise),
        formatPaise(item.days31To60Paise),
        formatPaise(item.days61To90Paise),
        formatPaise(item.days90PlusPaise),
      ]));
    }

    buffer.writeln(_buildRow([
      'TOTAL',
      '',
      '',
      formatPaise(report.totalOutstandingPaise),
      formatPaise(report.totalCurrentPaise),
      formatPaise(report.totalDays1To30Paise),
      formatPaise(report.totalDays31To60Paise),
      formatPaise(report.totalDays61To90Paise),
      formatPaise(report.totalDays90PlusPaise),
    ]));

    return buffer.toString();
  }

  /// Exports Stock Valuation report to CSV.
  static String exportStockValuation(StockValuationReport report) {
    final buffer = StringBuffer();
    buffer.writeln(_buildRow([
      'Product Name',
      'SKU',
      'Category',
      'Unit',
      'Current Stock',
      'Purchase Price',
      'Selling Price',
      'Cost Valuation',
      'Retail Valuation',
      'Stock Status',
    ]));

    for (final item in report.items) {
      String status = 'Normal';
      if (item.isOutOfStock) {
        status = 'Out of Stock';
      } else if (item.isLowStock) {
        status = 'Low Stock';
      }

      buffer.writeln(_buildRow([
        item.productName,
        item.sku ?? '',
        item.categoryName ?? 'Uncategorized',
        item.unitCode,
        item.currentStock,
        formatPaise(item.purchasePricePaise),
        formatPaise(item.sellingPricePaise),
        formatPaise(item.costValuationPaise),
        formatPaise(item.retailValuationPaise),
        status,
      ]));
    }

    buffer.writeln(_buildRow([
      'TOTAL',
      '',
      '',
      '',
      report.totalStockQuantity,
      '',
      '',
      formatPaise(report.totalCostValuationPaise),
      formatPaise(report.totalRetailValuationPaise),
      '',
    ]));

    return buffer.toString();
  }
}
