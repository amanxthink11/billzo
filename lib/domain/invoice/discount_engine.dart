import 'package:billzo/core/money/money.dart';

/// Type of discount applied to an invoice or line item.
enum DiscountType {
  percentage,
  fixed;

  String get displayName {
    switch (this) {
      case DiscountType.percentage:
        return 'Percentage (%)';
      case DiscountType.fixed:
        return 'Fixed (₹)';
    }
  }

  String get dbValue => name;

  static DiscountType fromDbValue(String value) {
    switch (value.toLowerCase()) {
      case 'percentage':
        return DiscountType.percentage;
      case 'fixed':
        return DiscountType.fixed;
      default:
        return DiscountType.percentage;
    }
  }
}

/// Pure domain discount calculation engine with deterministic integer math.
class DiscountEngine {
  DiscountEngine._();

  /// Calculates the discount amount in minor units (paise) for a given gross amount.
  ///
  /// - [grossPaise]: Base amount before discount in paise.
  /// - [type]: Percentage or Fixed.
  /// - [value]: Discount rate (e.g. 10.0 for 10%) or fixed rupees (e.g. 150.00 for ₹150)
  ///   or direct paise if passed.
  ///
  /// Guarantee: The calculated discount is never negative and never exceeds [grossPaise].
  static int calculateDiscountPaise({
    required int grossPaise,
    required DiscountType type,
    required num value,
  }) {
    if (grossPaise <= 0 || value <= 0) {
      return 0;
    }

    int discountPaise = 0;

    switch (type) {
      case DiscountType.percentage:
        // Value is percentage (e.g., 5.0% or 12.5%)
        // Percentage in basis points: 5.0% -> 500 bps
        final basisPoints = (value * 100).round();
        if (basisPoints <= 0) return 0;
        if (basisPoints >= 10000) return grossPaise; // 100% discount
        // Half-up rounding to nearest paisa: (grossPaise * basisPoints + 5000) ~/ 10000
        discountPaise = (grossPaise * basisPoints + 5000) ~/ 10000;
        break;

      case DiscountType.fixed:
        // Value is in Rupees if fractional/decimal, or can be converted to integer paise
        discountPaise = Money.fromRupees(value.toDouble()).paise;
        break;
    }

    // Invariant: 0 <= discountPaise <= grossPaise
    if (discountPaise < 0) return 0;
    if (discountPaise > grossPaise) return grossPaise;

    return discountPaise;
  }

  /// Convenience alias for [calculateDiscountPaise].
  static int calculateLineDiscountPaise({
    required int grossAmountPaise,
    required DiscountType discountType,
    required num discountValue,
  }) {
    return calculateDiscountPaise(
      grossPaise: grossAmountPaise,
      type: discountType,
      value: discountValue,
    );
  }

  /// Distributes an overall invoice-level discount proportionally across line item gross amounts.
  static List<int> distributeInvoiceDiscount({
    required List<int> lineGrossAmountsPaise,
    required int totalDiscountPaise,
  }) {
    if (lineGrossAmountsPaise.isEmpty || totalDiscountPaise <= 0) {
      return List.filled(lineGrossAmountsPaise.length, 0);
    }

    final totalGross = lineGrossAmountsPaise.reduce((a, b) => a + b);
    if (totalGross <= 0) {
      return List.filled(lineGrossAmountsPaise.length, 0);
    }

    int allocatedSoFar = 0;
    final results = <int>[];

    for (int i = 0; i < lineGrossAmountsPaise.length; i++) {
      if (i == lineGrossAmountsPaise.length - 1) {
        // Last item absorbs any rounding remainder
        final remaining = totalDiscountPaise - allocatedSoFar;
        results.add(remaining.clamp(0, lineGrossAmountsPaise[i]));
      } else {
        final share = (totalDiscountPaise * lineGrossAmountsPaise[i] + (totalGross ~/ 2)) ~/ totalGross;
        final clampedShare = share.clamp(0, lineGrossAmountsPaise[i]);
        results.add(clampedShare);
        allocatedSoFar += clampedShare;
      }
    }

    return results;
  }
}
