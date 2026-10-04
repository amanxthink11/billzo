import 'package:billzo/core/money/money.dart';

/// Converts monetary amounts into standard Indian English words representation
/// e.g., "Rupees Seven Thousand Eighty Only".
class IndianNumberToWords {
  IndianNumberToWords._();

  static const List<String> _units = [
    '',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen',
  ];

  static const List<String> _tens = [
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety',
  ];

  static String convert(Money money) {
    if (money.isZero) {
      return 'Rupees Zero Only';
    }

    final totalPaise = money.paise.abs();
    final rupees = totalPaise ~/ 100;
    final paise = totalPaise % 100;

    final buffer = StringBuffer();
    buffer.write('Rupees ');

    if (rupees > 0) {
      buffer.write(_convertRupees(rupees));
    } else {
      buffer.write('Zero');
    }

    if (paise > 0) {
      buffer.write(' and ');
      buffer.write(_convertTwoDigits(paise));
      buffer.write(' Paise');
    }

    buffer.write(' Only');
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _convertRupees(int n) {
    if (n == 0) return '';

    final buffer = StringBuffer();

    // Crores (1,00,00,000)
    final crores = n ~/ 10000000;
    var remainder = n % 10000000;

    if (crores > 0) {
      buffer.write('${_convertRupees(crores)} Crore ');
    }

    // Lakhs (1,00,000)
    final lakhs = remainder ~/ 100000;
    remainder = remainder % 100000;

    if (lakhs > 0) {
      buffer.write('${_convertTwoDigits(lakhs)} Lakh ');
    }

    // Thousands (1,000)
    final thousands = remainder ~/ 1000;
    remainder = remainder % 1000;

    if (thousands > 0) {
      buffer.write('${_convertTwoDigits(thousands)} Thousand ');
    }

    // Hundreds (100)
    final hundreds = remainder ~/ 100;
    remainder = remainder % 100;

    if (hundreds > 0) {
      buffer.write('${_units[hundreds]} Hundred ');
    }

    // Tens and Units
    if (remainder > 0) {
      buffer.write(_convertTwoDigits(remainder));
    }

    return buffer.toString().trim();
  }

  static String _convertTwoDigits(int n) {
    if (n < 20) {
      return _units[n];
    }
    final ten = n ~/ 10;
    final unit = n % 10;
    if (unit > 0) {
      return '${_tens[ten]} ${_units[unit]}';
    }
    return _tens[ten];
  }
}
