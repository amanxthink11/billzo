import 'package:billzo/core/money/money.dart';

/// Single tax bucket summarizing taxable amount and split components.
class GstTaxBucket {
  final int taxableAmountPaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;

  const GstTaxBucket({
    this.taxableAmountPaise = 0,
    this.cgstPaise = 0,
    this.sgstPaise = 0,
    this.igstPaise = 0,
  });

  int get totalTaxPaise => cgstPaise + sgstPaise + igstPaise;

  Money get taxableAmount => Money.fromPaise(taxableAmountPaise);
  Money get cgst => Money.fromPaise(cgstPaise);
  Money get sgst => Money.fromPaise(sgstPaise);
  Money get igst => Money.fromPaise(igstPaise);
  Money get totalTax => Money.fromPaise(totalTaxPaise);
}

/// Offline GST Summary / Management Report aggregating Outward Sales Tax, Inward Purchase ITC,
/// and Operational Expense ITC.
class GstSummaryReport {
  final String businessId;
  final DateTime startDate;
  final DateTime endDate;

  // Outward Tax (Sales)
  final GstTaxBucket outwardSupply;

  // Inward Tax (Purchases)
  final GstTaxBucket eligiblePurchaseItc;
  final int ineligiblePurchaseItcPaise;

  // Expense Tax (Indirect / Operational Expenses)
  final GstTaxBucket eligibleExpenseItc;

  final DateTime generatedAt;

  const GstSummaryReport({
    required this.businessId,
    required this.startDate,
    required this.endDate,
    required this.outwardSupply,
    required this.eligiblePurchaseItc,
    this.ineligiblePurchaseItcPaise = 0,
    required this.eligibleExpenseItc,
    required this.generatedAt,
  });

  static const String reportTitle = 'GST Summary / Management Report';
  static const String disclaimer =
      'Internal management reconciliation report only. Not an official statutory GST return (GSTR-1, GSTR-3B).';

  int get totalOutputGstPaise => outwardSupply.totalTaxPaise;
  Money get totalOutputGst => Money.fromPaise(totalOutputGstPaise);

  int get totalInputGstPaise => eligiblePurchaseItc.totalTaxPaise + eligibleExpenseItc.totalTaxPaise;
  Money get totalInputGst => Money.fromPaise(totalInputGstPaise);

  /// Net GST Liability = Output GST - Total Eligible ITC.
  /// Positive value indicates net tax payable to the government.
  /// Negative value indicates excess input tax credit carried forward.
  int get netGstLiabilityPaise => totalOutputGstPaise - totalInputGstPaise;
  Money get netGstLiability => Money.fromPaise(netGstLiabilityPaise.abs());

  bool get isPayable => netGstLiabilityPaise > 0;
  bool get hasExcessCredit => netGstLiabilityPaise < 0;
  bool get isNil => netGstLiabilityPaise == 0;
}
