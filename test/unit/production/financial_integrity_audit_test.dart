import 'package:flutter_test/flutter_test.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/domain/invoice/tax_engine.dart';

void main() {
  group('Production Financial Integrity Audit — Zero Float Guarantee', () {
    test('Paise integer representation eliminates all IEEE-754 floating point drift', () {
      // 0.1 + 0.2 in floating point produces 0.30000000000000004
      // In Billzo, 10 paise + 20 paise == 30 paise exactly
      final m1 = Money.fromPaise(10);
      final m2 = Money.fromPaise(20);
      final sum = m1 + m2;

      expect(sum.paise, equals(30));
      expect(sum.formatted, equals('₹0.30'));
    });

    test('Large ledger sums do not lose precision or suffer truncation', () {
      final crore = Money.fromPaise(1000000000); // ₹1,00,00,000.00
      final onePaisa = Money.fromPaise(1);

      final total = crore + onePaisa;
      expect(total.paise, equals(1000000001));
      expect(total.formattedWithoutSymbol, equals('1,00,00,000.01'));
    });

    test('Complex Multi-Rate GST Invoice Totals are strictly balanced to the paise', () {
      // Line 1: ₹1,550.75 @ 18% GST (Inter-State IGST)
      final line1 = TaxEngine.calculateLineItemTax(
        ratePaise: 155075,
        quantityScaled: 1000, // 1.000 qty
        discountPaise: 0,
        taxRateBasisPoints: 1800, // 18.00%
        isInterState: true,
      );

      // Line 2: ₹3,200.00 @ 12% GST (Intra-State CGST 6% + SGST 6%)
      final line2 = TaxEngine.calculateLineItemTax(
        ratePaise: 320000,
        quantityScaled: 1000,
        discountPaise: 0,
        taxRateBasisPoints: 1200, // 12.00%
        isInterState: false,
      );

      // Line 3: ₹550.50 @ 5% GST (Intra-State CGST 2.5% + SGST 2.5%)
      final line3 = TaxEngine.calculateLineItemTax(
        ratePaise: 55050,
        quantityScaled: 1000,
        discountPaise: 0,
        taxRateBasisPoints: 500, // 5.00%
        isInterState: false,
      );

      final invoiceTotals = TaxEngine.calculateInvoice(
        lines: [line1, line2, line3],
        enableRoundOff: true,
      );

      // Verify exact arithmetic match
      expect(
        invoiceTotals.taxableAmountPaise +
            invoiceTotals.cgstPaise +
            invoiceTotals.sgstPaise +
            invoiceTotals.igstPaise +
            invoiceTotals.cessPaise +
            invoiceTotals.roundOffPaise,
        equals(invoiceTotals.totalAmountPaise),
      );

      // Verify round-off produced a whole rupee total
      expect(
        invoiceTotals.totalAmountPaise % 100,
        equals(0),
        reason: 'Statutory round-off must produce zero minor paise on grand total',
      );

      // Verify line breakdown integrity
      for (final line in invoiceTotals.lineBreakdowns) {
        expect(
          line.taxableAmountPaise + line.totalTaxPaise,
          equals(line.lineTotalPaise),
          reason: 'Line taxable + tax must equal line total',
        );
      }
    });

    test('Statutory TaxEngine Round-Off behavior adheres to boundary rules', () {
      // 0 to 49 paise rounds DOWN (-remainder)
      expect(TaxEngine.computeRoundOff(10049), equals(-49)); // ₹100.49 -> ₹100.00
      expect(TaxEngine.computeRoundOff(10001), equals(-1));  // ₹100.01 -> ₹100.00

      // 50 to 99 paise rounds UP (+(100 - remainder))
      expect(TaxEngine.computeRoundOff(10050), equals(50));  // ₹100.50 -> ₹101.00
      expect(TaxEngine.computeRoundOff(10099), equals(1));   // ₹100.99 -> ₹101.00

      // Exact whole rupees require 0 adjustment
      expect(TaxEngine.computeRoundOff(10000), equals(0));   // ₹100.00 -> ₹100.00
    });

    test('Tax-inclusive line items decompose back to exact taxable amount and tax split', () {
      // ₹1,180.00 tax-inclusive @ 18% GST intra-state
      // Base: ₹1,000.00 (100000 paise), CGST: ₹90.00 (9000 paise), SGST: ₹90.00 (9000 paise)
      final inclusiveLine = TaxEngine.calculateLineItemTax(
        ratePaise: 118000,
        quantityScaled: 1000,
        discountPaise: 0,
        taxRateBasisPoints: 1800,
        isInterState: false,
        isTaxInclusive: true,
      );

      expect(inclusiveLine.taxableAmountPaise, equals(100000));
      expect(inclusiveLine.cgstPaise, equals(9000));
      expect(inclusiveLine.sgstPaise, equals(9000));
      expect(inclusiveLine.totalTaxPaise, equals(18000));
      expect(inclusiveLine.lineTotalPaise, equals(118000));
    });

    test('Indian Numbering System & Currency Formatter is deterministic and accurate', () {
      final m1 = Money.fromPaise(123456789); // ₹12,34,567.89 (Twelve Lakh Thirty-Four Thousand Five Hundred Sixty-Seven and 89 Paise)
      expect(m1.formattedWithoutSymbol, equals('12,34,567.89'));

      final m2 = Money.fromPaise(1000000000); // ₹1,00,00,000.00 (One Crore)
      expect(m2.formattedWithoutSymbol, equals('1,00,00,000.00'));

      final m3 = Money.fromPaise(500); // ₹5.00
      expect(m3.formatted, equals('₹5.00'));

      final mZero = Money.fromPaise(0);
      expect(mZero.formatted, equals('₹0.00'));
    });
  });
}
