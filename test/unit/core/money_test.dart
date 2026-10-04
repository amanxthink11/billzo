import 'package:flutter_test/flutter_test.dart';
import 'package:billzo/core/money/money.dart';

void main() {
  group('Money Value Object Tests', () {
    test('Constructs accurately from paise and rupees', () {
      const m1 = Money.fromPaise(10050); // ₹100.50
      final m2 = Money.fromRupees(100.50);

      expect(m1.paise, equals(10050));
      expect(m2.paise, equals(10050));
      expect(m1, equals(m2));
    });

    test('Zero precision loss during addition and subtraction', () {
      final a = Money.fromRupees(0.10); // 10 paise
      final b = Money.fromRupees(0.20); // 20 paise
      final sum = a + b;

      // Under IEEE 754 double, 0.1 + 0.2 != 0.3.
      // Under Money integer paise, 10 + 20 == 30 exactly.
      expect(sum.paise, equals(30));
      expect(sum.toIndianRupeeString(), equals('₹0.30'));
    });

    test('Multiplies with scaled fractional quantities (e.g. 1.250 Kg)', () {
      // Rate = ₹150.00 / Kg (15000 paise)
      // Quantity = 1.250 Kg (1250 scaled)
      const rate = Money.fromPaise(15000);
      final total = rate.multiplyByScaledQuantity(1250);

      // Expected = 150 * 1.25 = ₹187.50 (18750 paise)
      expect(total.paise, equals(18750));
      expect(total.toIndianRupeeString(), equals('₹187.50'));
    });

    test('Deterministic GST basis points calculation', () {
      // ₹1,000.00 (100000 paise) at 18% GST (1800 bps)
      const taxable = Money.fromPaise(100000);
      final tax = taxable.calculateBasisPoints(1800);

      expect(tax.paise, equals(18000)); // ₹180.00
      expect((taxable + tax).paise, equals(118000)); // ₹1,180.00
    });

    test('Half-up paisa rounding for odd divisions', () {
      // ₹33.33 taxable (3333 paise) at 9% CGST (900 bps)
      // 3333 * 900 / 10000 = 299.97 -> rounds to 300 paise (₹3.00)
      const oddAmount = Money.fromPaise(3333);
      final cgst = oddAmount.calculateBasisPoints(900);
      expect(cgst.paise, equals(300));
    });

    test('Invoice round-off to nearest whole Rupee', () {
      // ₹1,250.40 -> rounds off by -40 paise to ₹1,250.00
      final m1 = Money.fromRupees(1250.40);
      expect(m1.roundOffDifference().paise, equals(-40));
      expect(m1.roundToNearestRupee().paise, equals(125000));

      // ₹1,250.60 -> rounds off by +40 paise to ₹1,251.00
      final m2 = Money.fromRupees(1250.60);
      expect(m2.roundOffDifference().paise, equals(40));
      expect(m2.roundToNearestRupee().paise, equals(125100));

      // ₹1,250.50 -> rounds off by +50 paise to ₹1,251.00
      final m3 = Money.fromRupees(1250.50);
      expect(m3.roundOffDifference().paise, equals(50));
      expect(m3.roundToNearestRupee().paise, equals(125100));
    });

    test('Indian Lakh and Crore formatting', () {
      expect(const Money.fromPaise(2458000).toIndianRupeeString(), equals('₹24,580.00'));
      expect(const Money.fromPaise(14250000).toIndianRupeeString(), equals('₹1,42,500.00'));
      expect(const Money.fromPaise(125000000).toIndianRupeeString(), equals('₹12,50,000.00'));
      expect(const Money.fromPaise(1000000000).toIndianRupeeString(), equals('₹1,00,00,000.00'));
    });

    test('String parsing for currency inputs', () {
      expect(Money.parse('₹1,42,500.50').paise, equals(14250050));
      expect(Money.parse('500').paise, equals(50000));
      expect(Money.parse('0.75').paise, equals(75));
      expect(Money.parse('').paise, equals(0));
    });
  });
}
