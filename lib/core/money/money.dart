/// Immutable representation of monetary values denominated in Indian Paise (minor units).
///
/// Under no circumstances should floating point types (double) be used
/// for financial calculations or persisted balances in Billzo.
/// 1 Rupee = 100 Paise.
class Money implements Comparable<Money> {
  /// The amount in minor units (integer paise).
  final int paise;

  /// Canonical constructor from integer paise.
  const Money(this.paise);

  /// Private internal constructor.
  const Money._(this.paise);

  /// Constructs a [Money] instance from integer paise.
  const Money.fromPaise(this.paise);

  /// Formats an integer amount of paise into Indian Rupee notation with symbol.
  static String formatPaise(int paise) => Money(paise).formattedWithSymbol;

  /// Shorthand getter for formatted representation.
  String get formatted => formattedWithSymbol;

  /// Constructs a zero amount [Money] instance.
  static const Money zero = Money(0);

  /// Constructs a [Money] instance from a rupee decimal value,
  /// safely converting to integer paise using deterministic round-half-up.
  factory Money.fromRupees(double rupees) {
    if (rupees.isNaN || rupees.isInfinite) {
      throw ArgumentError.value(rupees, 'rupees', 'Invalid monetary amount');
    }
    // Round to nearest integer paisa
    final paise = (rupees * 100.0).round();
    return Money._(paise);
  }

  /// Parses a string representation such as "1250.50", "1250", or "-45.00".
  factory Money.parse(String text) {
    final sanitized = text.replaceAll('₹', '').replaceAll(',', '').trim();
    if (sanitized.isEmpty) return Money.zero;

    final parts = sanitized.split('.');
    if (parts.length > 2) {
      throw FormatException('Invalid monetary format: $text');
    }

    final isNegative = sanitized.startsWith('-');
    final absSanitized = isNegative ? sanitized.substring(1) : sanitized;
    final absParts = absSanitized.split('.');

    final rupees = int.parse(absParts[0].isEmpty ? '0' : absParts[0]);
    int paiseFraction = 0;

    if (absParts.length == 2) {
      final fracStr = absParts[1];
      if (fracStr.length == 1) {
        paiseFraction = int.parse(fracStr) * 10;
      } else if (fracStr.length >= 2) {
        paiseFraction = int.parse(fracStr.substring(0, 2));
      }
    }

    final totalPaise = (rupees * 100) + paiseFraction;
    return Money._(isNegative ? -totalPaise : totalPaise);
  }

  /// Returns true if this amount is strictly positive (> 0).
  bool get isPositive => paise > 0;

  /// Returns true if this amount is strictly negative (< 0).
  bool get isNegative => paise < 0;

  /// Returns true if this amount is exactly zero.
  bool get isZero => paise == 0;

  /// Adds another [Money] value.
  Money operator +(Money other) => Money._(paise + other.paise);

  /// Subtracts another [Money] value.
  Money operator -(Money other) => Money._(paise - other.paise);

  /// Unary negation.
  Money operator -() => Money._(-paise);

  /// Multiplies by an integer quantity.
  Money operator *(int factor) => Money._(paise * factor);

  /// Multiplies by a fractional quantity scaled by 1,000 (e.g. 1.250 Kg = 1250).
  Money multiplyByScaledQuantity(int scaledQuantity, {int scaleFactor = 1000}) {
    // (paise * scaledQuantity) / scaleFactor rounded half-up
    final numerator = paise * scaledQuantity;
    final remainder = numerator % scaleFactor;
    int quotient = numerator ~/ scaleFactor;
    if (remainder.abs() * 2 >= scaleFactor) {
      quotient += numerator >= 0 ? 1 : -1;
    }
    return Money._(quotient);
  }

  /// Multiplies by basis points (where 1% = 100 bps, 18% = 1800 bps)
  /// using deterministic half-up rounding to the nearest paisa.
  Money calculateBasisPoints(int basisPoints) {
    if (basisPoints == 0 || paise == 0) return Money.zero;
    final product = paise * basisPoints;
    final quotient = (product + 5000) ~/ 10000;
    return Money._(quotient);
  }

  /// Calculates percentage using basis points.
  Money percentage(double percent) {
    final basisPoints = (percent * 100).round();
    return calculateBasisPoints(basisPoints);
  }

  /// Extracts the round-off difference in paise to reach the nearest whole Rupee.
  /// (e.g. +40 paise or -35 paise)
  Money roundOffDifference() {
    final remainder = paise % 100;
    if (remainder == 0) return Money.zero;
    if (remainder >= 50) {
      return Money._(100 - remainder);
    } else {
      return Money._(-remainder);
    }
  }

  /// Rounds this money instance to the nearest whole Rupee.
  Money roundToNearestRupee() {
    return this + roundOffDifference();
  }

  /// Returns the absolute money value.
  Money abs() => Money._(paise.abs());

  /// Returns value with rupee symbol formatted in standard Indian notation: e.g. "₹1,42,500.00".
  String get formattedWithSymbol => toIndianRupeeString(includeSymbol: true);

  /// Returns value without rupee symbol formatted in standard Indian notation: e.g. "1,42,500.00".
  String get formattedWithoutSymbol => toIndianRupeeString(includeSymbol: false);

  /// Returns the value formatted in standard Indian Lakh/Crore notation:
  /// e.g. "₹1,42,500.00" or "₹24,580.00".
  String toIndianRupeeString({bool includeSymbol = true, bool alwaysDecimals = true}) {
    final isNeg = isNegative;
    final absPaise = paise.abs();
    final rupees = absPaise ~/ 100;
    final paiseRemainder = absPaise % 100;

    final rupeesStr = rupees.toString();
    String formattedRupees;

    if (rupeesStr.length <= 3) {
      formattedRupees = rupeesStr;
    } else {
      // Indian numbering format: 3 digits from right, then 2 digits recursively
      final lastThree = rupeesStr.substring(rupeesStr.length - 3);
      final remaining = rupeesStr.substring(0, rupeesStr.length - 3);

      final buffer = StringBuffer();
      for (int i = 0; i < remaining.length; i++) {
        if (i > 0 && (remaining.length - i) % 2 == 0) {
          buffer.write(',');
        }
        buffer.write(remaining[i]);
      }
      formattedRupees = '${buffer.toString()},$lastThree';
    }

    final paiseStr = paiseRemainder.toString().padLeft(2, '0');
    final decimalPart = alwaysDecimals || paiseRemainder > 0 ? '.$paiseStr' : '';
    final sign = isNeg ? '-' : '';
    final symbol = includeSymbol ? '₹' : '';

    return '$sign$symbol$formattedRupees$decimalPart';
  }

  @override
  int compareTo(Money other) => paise.compareTo(other.paise);

  bool operator <(Money other) => paise < other.paise;
  bool operator <=(Money other) => paise <= other.paise;
  bool operator >(Money other) => paise > other.paise;
  bool operator >=(Money other) => paise >= other.paise;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Money && other.paise == paise);

  @override
  int get hashCode => paise.hashCode;

  @override
  String toString() => toIndianRupeeString();
}
