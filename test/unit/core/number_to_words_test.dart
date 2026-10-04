import 'package:flutter_test/flutter_test.dart';
import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/utils/number_to_words.dart';

void main() {
  group('IndianNumberToWords Tests', () {
    test('Converts exact sample from Brand Kit Invoice (₹7,080)', () {
      final m = Money.fromRupees(7080.00);
      expect(IndianNumberToWords.convert(m), equals('Rupees Seven Thousand Eighty Only'));
    });

    test('Converts zero rupees', () {
      expect(IndianNumberToWords.convert(Money.zero), equals('Rupees Zero Only'));
    });

    test('Converts lakhs and thousands correctly', () {
      final m = Money.fromRupees(142500.50);
      expect(
        IndianNumberToWords.convert(m),
        equals('Rupees One Lakh Forty Two Thousand Five Hundred and Fifty Paise Only'),
      );
    });

    test('Converts crores correctly', () {
      final m = Money.fromRupees(25000000.00); // 2.5 Crore
      expect(
        IndianNumberToWords.convert(m),
        equals('Rupees Two Crore Fifty Lakh Only'),
      );
    });
  });
}
