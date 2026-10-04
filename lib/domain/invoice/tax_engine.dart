import 'package:flutter/foundation.dart';
import 'package:billzo/core/money/money.dart';

/// Calculation breakdown for an individual line item.
@immutable
class LineTaxBreakdown {
  final int grossAmountPaise;
  final int discountPaise;
  final int taxableAmountPaise;
  final int cgstRateBasisPoints;
  final int cgstAmountPaise;
  final int sgstRateBasisPoints;
  final int sgstAmountPaise;
  final int igstRateBasisPoints;
  final int igstAmountPaise;
  final int cessRateBasisPoints;
  final int cessAmountPaise;
  final int totalTaxPaise;
  final int lineTotalPaise;

  const LineTaxBreakdown({
    required this.grossAmountPaise,
    required this.discountPaise,
    required this.taxableAmountPaise,
    required this.cgstRateBasisPoints,
    required this.cgstAmountPaise,
    required this.sgstRateBasisPoints,
    required this.sgstAmountPaise,
    required this.igstRateBasisPoints,
    required this.igstAmountPaise,
    required this.cessRateBasisPoints,
    required this.cessAmountPaise,
    required this.totalTaxPaise,
    required this.lineTotalPaise,
  });

  Money get taxableAmount => Money.fromPaise(taxableAmountPaise);
  Money get cgstAmount => Money.fromPaise(cgstAmountPaise);
  Money get sgstAmount => Money.fromPaise(sgstAmountPaise);
  Money get igstAmount => Money.fromPaise(igstAmountPaise);
  Money get totalTax => Money.fromPaise(totalTaxPaise);
  int get taxAmountPaise => totalTaxPaise;
  int get totalTaxAmountPaise => totalTaxPaise;
  int get cgstPaise => cgstAmountPaise;
  int get sgstPaise => sgstAmountPaise;
  int get igstPaise => igstAmountPaise;
  int get cessPaise => cessAmountPaise;
  Money get lineTotal => Money.fromPaise(lineTotalPaise);
}

/// Comprehensive invoice calculation summary.
@immutable
class InvoiceTaxCalculation {
  final int subtotalPaise;
  final int discountPaise;
  final int taxableAmountPaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int cessPaise;
  final int totalTaxPaise;
  final int totalBeforeRoundOffPaise;
  final int roundOffPaise;
  final int totalAmountPaise;
  final List<LineTaxBreakdown> lineBreakdowns;

  const InvoiceTaxCalculation({
    required this.subtotalPaise,
    required this.discountPaise,
    required this.taxableAmountPaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.cessPaise,
    required this.totalTaxPaise,
    required this.totalBeforeRoundOffPaise,
    required this.roundOffPaise,
    required this.totalAmountPaise,
    required this.lineBreakdowns,
  });

  Money get subtotal => Money.fromPaise(subtotalPaise);
  Money get discount => Money.fromPaise(discountPaise);
  Money get taxableAmount => Money.fromPaise(taxableAmountPaise);
  Money get cgst => Money.fromPaise(cgstPaise);
  Money get sgst => Money.fromPaise(sgstPaise);
  Money get igst => Money.fromPaise(igstPaise);
  Money get cess => Money.fromPaise(cessPaise);
  Money get totalTax => Money.fromPaise(totalTaxPaise);
  int get taxAmountPaise => totalTaxPaise;
  int get cgstAmountPaise => cgstPaise;
  int get sgstAmountPaise => sgstPaise;
  int get igstAmountPaise => igstPaise;
  int get grossTaxableAmountPaise => taxableAmountPaise;
  int get totalDiscountPaise => discountPaise;
  int get totalCgstPaise => cgstPaise;
  int get totalSgstPaise => sgstPaise;
  int get totalIgstPaise => igstPaise;
  int get finalPayablePaise => totalAmountPaise;
  Money get totalBeforeRoundOff => Money.fromPaise(totalBeforeRoundOffPaise);
  Money get roundOff => Money.fromPaise(roundOffPaise);
  Money get totalAmount => Money.fromPaise(totalAmountPaise);
}

/// Stateless, deterministic GST & Tax calculation engine.
///
/// Implements Indian Accounting Standards and statutory GST calculation rules
/// completely offline using integer minor units (paise) and basis points.
class TaxEngine {
  TaxEngine._();

  /// Determines if supply is inter-state based on 2-digit Indian State codes.
  static bool isInterState({
    required String businessStateCode,
    String? placeOfSupplyStateCode,
  }) {
    if (placeOfSupplyStateCode == null || placeOfSupplyStateCode.trim().isEmpty) {
      return false;
    }
    final bState = businessStateCode.trim().padLeft(2, '0');
    final pState = placeOfSupplyStateCode.trim().padLeft(2, '0');
    return bState != pState;
  }

  /// Explicitly calculates round-off to nearest whole rupee.
  static int computeRoundOff(int amountPaise) {
    if (amountPaise <= 0) return 0;
    final remainder = amountPaise % 100;
    if (remainder == 0) return 0;
    return remainder >= 50 ? (100 - remainder) : -remainder;
  }

  /// Convenience method for calculating taxes on a single line item when explicit CGST/SGST basis points are split evenly.
  static LineTaxBreakdown calculateLineItemTax({
    required int ratePaise,
    required int quantityScaled,
    required int discountPaise,
    required int taxRateBasisPoints,
    required bool isInterState,
    bool isTaxInclusive = false,
  }) {
    final halfRate = taxRateBasisPoints ~/ 2;
    return calculateLine(
      rateOrMrpPaise: ratePaise,
      quantityScaled: quantityScaled,
      discountPaise: discountPaise,
      rateBasisPoints: taxRateBasisPoints,
      cgstBasisPoints: halfRate,
      sgstBasisPoints: taxRateBasisPoints - halfRate,
      igstBasisPoints: taxRateBasisPoints,
      isInterState: isInterState,
      isTaxInclusive: isTaxInclusive,
    );
  }

  /// Convenience method for aggregating line breakdowns into invoice totals.
  static InvoiceTaxCalculation calculateInvoiceTotals({
    required List<LineTaxBreakdown> lines,
    bool enableRoundOff = true,
  }) {
    return calculateInvoice(
      lines: lines,
      enableRoundOff: enableRoundOff,
    );
  }

  /// Calculates taxes and totals for a single line item.
  ///
  /// - [rateOrMrpPaise]: Unit rate in paise (base selling price if tax-exclusive, MRP if tax-inclusive).
  /// - [quantityScaled]: Quantity scaled by 1,000 (e.g., 2.500 units = 2500).
  /// - [discountPaise]: Pre-calculated discount in paise for the line item.
  /// - [rateBasisPoints]: Total tax rate basis points (e.g. 1800 for 18%).
  /// - [cgstBasisPoints]: CGST rate basis points (e.g. 900 for 9%).
  /// - [sgstBasisPoints]: SGST rate basis points (e.g. 900 for 9%).
  /// - [igstBasisPoints]: IGST rate basis points (e.g. 1800 for 18%).
  /// - [cessBasisPoints]: Cess rate basis points (defaults to 0).
  /// - [isTaxInclusive]: True if price is MRP (inclusive of tax).
  /// - [isInterState]: True if Place of Supply is outside merchant state.
  static LineTaxBreakdown calculateLine({
    required int rateOrMrpPaise,
    required int quantityScaled,
    required int discountPaise,
    required int rateBasisPoints,
    required int cgstBasisPoints,
    required int sgstBasisPoints,
    required int igstBasisPoints,
    int cessBasisPoints = 0,
    bool isTaxInclusive = false,
    required bool isInterState,
  }) {
    if (quantityScaled <= 0 || rateOrMrpPaise <= 0) {
      return LineTaxBreakdown(
        grossAmountPaise: 0,
        discountPaise: 0,
        taxableAmountPaise: 0,
        cgstRateBasisPoints: isInterState ? 0 : cgstBasisPoints,
        cgstAmountPaise: 0,
        sgstRateBasisPoints: isInterState ? 0 : sgstBasisPoints,
        sgstAmountPaise: 0,
        igstRateBasisPoints: isInterState ? igstBasisPoints : 0,
        igstAmountPaise: 0,
        cessRateBasisPoints: cessBasisPoints,
        cessAmountPaise: 0,
        totalTaxPaise: 0,
        lineTotalPaise: 0,
      );
    }

    // 1. Calculate Gross Amount (Half-Up integer scaling: (rate * qty + 500) ~/ 1000)
    final grossNumerator = rateOrMrpPaise * quantityScaled;
    final grossAmountPaise = (grossNumerator + 500) ~/ 1000;

    // 2. Ensure discount does not exceed gross amount
    final effectiveDiscountPaise = discountPaise.clamp(0, grossAmountPaise);

    int taxableAmountPaise;
    int cgstAmountPaise = 0;
    int sgstAmountPaise = 0;
    int igstAmountPaise = 0;
    int cessAmountPaise = 0;
    int totalTaxPaise = 0;
    int lineTotalPaise;

    if (isTaxInclusive) {
      // --- Tax-Inclusive Pricing (Reverse Calculation) ---
      final grossInclusive = grossAmountPaise - effectiveDiscountPaise;
      final totalApplicableBps =
          (isInterState ? igstBasisPoints : (cgstBasisPoints + sgstBasisPoints)) + cessBasisPoints;

      if (totalApplicableBps <= 0) {
        taxableAmountPaise = grossInclusive;
        totalTaxPaise = 0;
      } else {
        // TaxableAmount = round((GrossInclusive * 10000) / (10000 + TotalTax_bps))
        final divisor = 10000 + totalApplicableBps;
        taxableAmountPaise = (grossInclusive * 10000 + (divisor ~/ 2)) ~/ divisor;
        totalTaxPaise = grossInclusive - taxableAmountPaise;
      }

      if (isInterState) {
        igstAmountPaise = totalTaxPaise;
        cgstAmountPaise = 0;
        sgstAmountPaise = 0;
      } else {
        // Intra-state equal split. Any odd 1-paisa assigned to SGST deterministically
        cgstAmountPaise = totalTaxPaise ~/ 2;
        sgstAmountPaise = totalTaxPaise - cgstAmountPaise;
        igstAmountPaise = 0;
      }

      lineTotalPaise = grossInclusive;
    } else {
      // --- Tax-Exclusive Pricing ---
      taxableAmountPaise = grossAmountPaise - effectiveDiscountPaise;

      if (isInterState) {
        if (igstBasisPoints > 0 && taxableAmountPaise > 0) {
          igstAmountPaise = (taxableAmountPaise * igstBasisPoints + 5000) ~/ 10000;
        }
        cgstAmountPaise = 0;
        sgstAmountPaise = 0;
      } else {
        final totalGstBps = cgstBasisPoints + sgstBasisPoints;
        if (totalGstBps > 0 && taxableAmountPaise > 0) {
          final totalGst = (taxableAmountPaise * totalGstBps + 5000) ~/ 10000;
          cgstAmountPaise = totalGst ~/ 2;
          sgstAmountPaise = totalGst - cgstAmountPaise;
        }
        igstAmountPaise = 0;
      }

      if (cessBasisPoints > 0 && taxableAmountPaise > 0) {
        cessAmountPaise = (taxableAmountPaise * cessBasisPoints + 5000) ~/ 10000;
      }

      totalTaxPaise = cgstAmountPaise + sgstAmountPaise + igstAmountPaise + cessAmountPaise;
      lineTotalPaise = taxableAmountPaise + totalTaxPaise;
    }

    return LineTaxBreakdown(
      grossAmountPaise: grossAmountPaise,
      discountPaise: effectiveDiscountPaise,
      taxableAmountPaise: taxableAmountPaise,
      cgstRateBasisPoints: isInterState ? 0 : cgstBasisPoints,
      cgstAmountPaise: cgstAmountPaise,
      sgstRateBasisPoints: isInterState ? 0 : sgstBasisPoints,
      sgstAmountPaise: sgstAmountPaise,
      igstRateBasisPoints: isInterState ? igstBasisPoints : 0,
      igstAmountPaise: igstAmountPaise,
      cessRateBasisPoints: cessBasisPoints,
      cessAmountPaise: cessAmountPaise,
      totalTaxPaise: totalTaxPaise,
      lineTotalPaise: lineTotalPaise,
    );
  }

  /// Calculates invoice totals, tax aggregates, and statutory round-off.
  static InvoiceTaxCalculation calculateInvoice({
    required List<LineTaxBreakdown> lines,
    bool enableRoundOff = true,
  }) {
    int subtotalPaise = 0;
    int discountPaise = 0;
    int taxableAmountPaise = 0;
    int cgstPaise = 0;
    int sgstPaise = 0;
    int igstPaise = 0;
    int cessPaise = 0;

    for (final line in lines) {
      subtotalPaise += line.grossAmountPaise;
      discountPaise += line.discountPaise;
      taxableAmountPaise += line.taxableAmountPaise;
      cgstPaise += line.cgstAmountPaise;
      sgstPaise += line.sgstAmountPaise;
      igstPaise += line.igstAmountPaise;
      cessPaise += line.cessAmountPaise;
    }

    final totalTaxPaise = cgstPaise + sgstPaise + igstPaise + cessPaise;
    final totalBeforeRoundOffPaise = taxableAmountPaise + totalTaxPaise;

    int roundOffPaise = 0;
    if (enableRoundOff && totalBeforeRoundOffPaise > 0) {
      final remainder = totalBeforeRoundOffPaise % 100;
      if (remainder != 0) {
        if (remainder >= 50) {
          roundOffPaise = 100 - remainder;
        } else {
          roundOffPaise = -remainder;
        }
      }
    }

    final totalAmountPaise = totalBeforeRoundOffPaise + roundOffPaise;

    return InvoiceTaxCalculation(
      subtotalPaise: subtotalPaise,
      discountPaise: discountPaise,
      taxableAmountPaise: taxableAmountPaise,
      cgstPaise: cgstPaise,
      sgstPaise: sgstPaise,
      igstPaise: igstPaise,
      cessPaise: cessPaise,
      totalTaxPaise: totalTaxPaise,
      totalBeforeRoundOffPaise: totalBeforeRoundOffPaise,
      roundOffPaise: roundOffPaise,
      totalAmountPaise: totalAmountPaise,
      lineBreakdowns: lines,
    );
  }
}
