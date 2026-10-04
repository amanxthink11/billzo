import 'package:flutter_test/flutter_test.dart';
import 'package:billzo/domain/invoice/discount_engine.dart';

void main() {
  group('DiscountEngine Pure Integer Arithmetic Tests', () {
    test('Calculates 0% discount correctly', () {
      final discountPaise = DiscountEngine.calculateLineDiscountPaise(
        grossAmountPaise: 100000, // ₹1,000.00
        discountType: DiscountType.percentage,
        discountValue: 0.0,
      );
      expect(discountPaise, equals(0));
    });

    test('Calculates percentage discount using deterministic basis points', () {
      // 10% on ₹1,250.00 (125000 paise) = 12500 paise (₹125.00)
      final discountPaise = DiscountEngine.calculateLineDiscountPaise(
        grossAmountPaise: 125000,
        discountType: DiscountType.percentage,
        discountValue: 10.0,
      );
      expect(discountPaise, equals(12500));
    });

    test('Calculates odd fractional percentage discount with proper rounding', () {
      // 5.5% on ₹99.99 (9999 paise) = 549.945 paise -> rounded to 550 paise
      final discountPaise = DiscountEngine.calculateLineDiscountPaise(
        grossAmountPaise: 9999,
        discountType: DiscountType.percentage,
        discountValue: 5.5,
      );
      expect(discountPaise, equals(550));
    });

    test('Calculates fixed discount in rupees accurately', () {
      // ₹150.50 fixed discount on ₹1,000.00
      final discountPaise = DiscountEngine.calculateLineDiscountPaise(
        grossAmountPaise: 100000,
        discountType: DiscountType.fixed,
        discountValue: 150.50,
      );
      expect(discountPaise, equals(15050));
    });

    test('Clamps discount so it never exceeds gross amount (Full discount)', () {
      // 100% discount
      final fullPct = DiscountEngine.calculateLineDiscountPaise(
        grossAmountPaise: 50000,
        discountType: DiscountType.percentage,
        discountValue: 100.0,
      );
      expect(fullPct, equals(50000));

      // Over 100% discount
      final overPct = DiscountEngine.calculateLineDiscountPaise(
        grossAmountPaise: 50000,
        discountType: DiscountType.percentage,
        discountValue: 150.0,
      );
      expect(overPct, equals(50000));

      // Fixed discount exceeding total
      final overFixed = DiscountEngine.calculateLineDiscountPaise(
        grossAmountPaise: 50000,
        discountType: DiscountType.fixed,
        discountValue: 600.0, // ₹600.00 on ₹500.00
      );
      expect(overFixed, equals(50000));
    });

    test('Negative discount value is rejected/clamped to 0', () {
      final negativePct = DiscountEngine.calculateLineDiscountPaise(
        grossAmountPaise: 50000,
        discountType: DiscountType.percentage,
        discountValue: -15.0,
      );
      expect(negativePct, equals(0));

      final negativeFixed = DiscountEngine.calculateLineDiscountPaise(
        grossAmountPaise: 50000,
        discountType: DiscountType.fixed,
        discountValue: -50.0,
      );
      expect(negativeFixed, equals(0));
    });

    test('Total invoice discount distributes across multiple line items', () {
      final lineGrossAmounts = [10000, 20000, 30000]; // ₹100, ₹200, ₹300 (Total ₹600)
      final totalDiscountPaise = 6000; // ₹60 total discount

      final distributed = DiscountEngine.distributeInvoiceDiscount(
        lineGrossAmountsPaise: lineGrossAmounts,
        totalDiscountPaise: totalDiscountPaise,
      );

      expect(distributed.length, equals(3));
      // Proportions: 1/6, 2/6, 3/6 -> 1000, 2000, 3000
      expect(distributed[0], equals(1000));
      expect(distributed[1], equals(2000));
      expect(distributed[2], equals(3000));
      expect(distributed.reduce((a, b) => a + b), equals(totalDiscountPaise));
    });

    test('Handles remainder when distributing invoice discount without losing paise', () {
      final lineGrossAmounts = [10000, 10000, 10000]; // 3 items of ₹100 each
      final totalDiscountPaise = 100; // ₹1 discount (100 paise)
      // 100 / 3 = 33 with 1 remainder

      final distributed = DiscountEngine.distributeInvoiceDiscount(
        lineGrossAmountsPaise: lineGrossAmounts,
        totalDiscountPaise: totalDiscountPaise,
      );

      expect(distributed.reduce((a, b) => a + b), equals(100));
      expect(distributed, contains(34));
      expect(distributed, contains(33));
    });
  });
}
