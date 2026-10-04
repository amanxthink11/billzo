import 'package:billzo/core/money/money.dart';

/// B2B Invoice line for GSTR-1 (Table 4A, 4B, 4C, 6B, 6C) - Registered Taxpayers.
class Gstr1B2bInvoice {
  final String receiverGstin;
  final String receiverName;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final int invoiceValuePaise;
  final String placeOfSupply;
  final String reverseCharge; // 'N'
  final String invoiceType; // 'Regular'
  final int rateBasisPoints;
  final int taxableValuePaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int cessPaise;

  const Gstr1B2bInvoice({
    required this.receiverGstin,
    required this.receiverName,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.invoiceValuePaise,
    required this.placeOfSupply,
    this.reverseCharge = 'N',
    this.invoiceType = 'Regular',
    required this.rateBasisPoints,
    required this.taxableValuePaise,
    this.cgstPaise = 0,
    this.sgstPaise = 0,
    this.igstPaise = 0,
    this.cessPaise = 0,
  });

  double get ratePercent => rateBasisPoints / 100.0;
  Money get invoiceValue => Money.fromPaise(invoiceValuePaise);
  Money get taxableValue => Money.fromPaise(taxableValuePaise);
  Money get cgst => Money.fromPaise(cgstPaise);
  Money get sgst => Money.fromPaise(sgstPaise);
  Money get igst => Money.fromPaise(igstPaise);
  Money get cess => Money.fromPaise(cessPaise);
}

/// B2CL Invoice line for GSTR-1 (Table 5A, 5B) - Inter-state B2C > ₹2,50,000.
class Gstr1B2clInvoice {
  final String invoiceNumber;
  final DateTime invoiceDate;
  final int invoiceValuePaise;
  final String placeOfSupply;
  final int rateBasisPoints;
  final int taxableValuePaise;
  final int igstPaise;
  final int cessPaise;

  const Gstr1B2clInvoice({
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.invoiceValuePaise,
    required this.placeOfSupply,
    required this.rateBasisPoints,
    required this.taxableValuePaise,
    this.igstPaise = 0,
    this.cessPaise = 0,
  });

  double get ratePercent => rateBasisPoints / 100.0;
  Money get invoiceValue => Money.fromPaise(invoiceValuePaise);
  Money get taxableValue => Money.fromPaise(taxableValuePaise);
  Money get igst => Money.fromPaise(igstPaise);
  Money get cess => Money.fromPaise(cessPaise);
}

/// B2CS Summary row for GSTR-1 (Table 7) - Small B2C grouped by Place of Supply & Tax Rate.
class Gstr1B2csItem {
  final String placeOfSupply;
  final int rateBasisPoints;
  final int taxableValuePaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int cessPaise;

  const Gstr1B2csItem({
    required this.placeOfSupply,
    required this.rateBasisPoints,
    required this.taxableValuePaise,
    this.cgstPaise = 0,
    this.sgstPaise = 0,
    this.igstPaise = 0,
    this.cessPaise = 0,
  });

  double get ratePercent => rateBasisPoints / 100.0;
  Money get taxableValue => Money.fromPaise(taxableValuePaise);
  Money get cgst => Money.fromPaise(cgstPaise);
  Money get sgst => Money.fromPaise(sgstPaise);
  Money get igst => Money.fromPaise(igstPaise);
  Money get cess => Money.fromPaise(cessPaise);
}

/// HSN-wise summary of outward supplies for GSTR-1 (Table 12).
class Gstr1HsnSummaryItem {
  final String hsnSac;
  final String description;
  final String uqc;
  final int totalQuantity;
  final int totalValuePaise;
  final int taxableValuePaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int cessPaise;

  const Gstr1HsnSummaryItem({
    required this.hsnSac,
    required this.description,
    required this.uqc,
    required this.totalQuantity,
    required this.totalValuePaise,
    required this.taxableValuePaise,
    this.cgstPaise = 0,
    this.sgstPaise = 0,
    this.igstPaise = 0,
    this.cessPaise = 0,
  });

  Money get totalValue => Money.fromPaise(totalValuePaise);
  Money get taxableValue => Money.fromPaise(taxableValuePaise);
  Money get cgst => Money.fromPaise(cgstPaise);
  Money get sgst => Money.fromPaise(sgstPaise);
  Money get igst => Money.fromPaise(igstPaise);
  Money get cess => Money.fromPaise(cessPaise);
}

/// Comprehensive GSTR-1 Outward Supplies Report matching official Indian GST portal formats.
class Gstr1Report {
  final String businessId;
  final String? businessGstin;
  final DateTime startDate;
  final DateTime endDate;
  final List<Gstr1B2bInvoice> b2bInvoices;
  final List<Gstr1B2clInvoice> b2clInvoices;
  final List<Gstr1B2csItem> b2csItems;
  final List<Gstr1HsnSummaryItem> hsnSummary;
  final DateTime generatedAt;

  const Gstr1Report({
    required this.businessId,
    this.businessGstin,
    required this.startDate,
    required this.endDate,
    required this.b2bInvoices,
    required this.b2clInvoices,
    required this.b2csItems,
    required this.hsnSummary,
    required this.generatedAt,
  });

  static const int b2clThresholdPaise = 25000000; // ₹2,50,000 in paise

  int get totalB2bTaxablePaise =>
      b2bInvoices.fold<int>(0, (sum, i) => sum + i.taxableValuePaise);
  int get totalB2bTaxPaise =>
      b2bInvoices.fold<int>(0, (sum, i) => sum + i.cgstPaise + i.sgstPaise + i.igstPaise + i.cessPaise);

  int get totalB2clTaxablePaise =>
      b2clInvoices.fold<int>(0, (sum, i) => sum + i.taxableValuePaise);
  int get totalB2clTaxPaise =>
      b2clInvoices.fold<int>(0, (sum, i) => sum + i.igstPaise + i.cessPaise);

  int get totalB2csTaxablePaise =>
      b2csItems.fold<int>(0, (sum, i) => sum + i.taxableValuePaise);
  int get totalB2csTaxPaise =>
      b2csItems.fold<int>(0, (sum, i) => sum + i.cgstPaise + i.sgstPaise + i.igstPaise + i.cessPaise);

  int get grandTotalTaxablePaise =>
      totalB2bTaxablePaise + totalB2clTaxablePaise + totalB2csTaxablePaise;
  int get grandTotalTaxPaise =>
      totalB2bTaxPaise + totalB2clTaxPaise + totalB2csTaxPaise;

  Money get grandTotalTaxable => Money.fromPaise(grandTotalTaxablePaise);
  Money get grandTotalTax => Money.fromPaise(grandTotalTaxPaise);
}
