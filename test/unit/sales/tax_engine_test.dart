import 'package:flutter_test/flutter_test.dart';
import 'package:billzo/domain/invoice/tax_engine.dart';

void main() {
  group('TaxEngine GST and Round-Off Calculations', () {
    test('Identifies intra-state vs inter-state supply correctly', () {
      // Same state: Maharashtra (27) to Maharashtra (27) -> Intra-state
      expect(TaxEngine.isInterState(businessStateCode: '27', placeOfSupplyStateCode: '27'), isFalse);

      // Different states: Maharashtra (27) to Karnataka (29) -> Inter-state
      expect(TaxEngine.isInterState(businessStateCode: '27', placeOfSupplyStateCode: '29'), isTrue);

      // Customer state null/empty -> Defaults to intra-state
      expect(TaxEngine.isInterState(businessStateCode: '27', placeOfSupplyStateCode: null), isFalse);
      expect(TaxEngine.isInterState(businessStateCode: '27', placeOfSupplyStateCode: ''), isFalse);
    });

    test('Tax-exclusive calculation for 18% intra-state single item', () {
      // 2 units at ₹500.00 each = ₹1,000.00 (100000 paise)
      // Discount = ₹100.00 (10000 paise)
      // Taxable = ₹900.00 (90000 paise)
      // CGST (9%) = ₹81.00 (8100 paise)
      // SGST (9%) = ₹81.00 (8100 paise)
      // Line Total = ₹1,062.00 (106200 paise)
      final breakdown = TaxEngine.calculateLineItemTax(
        ratePaise: 50000,
        quantityScaled: 2000, // 2.000 units
        discountPaise: 10000,
        taxRateBasisPoints: 1800, // 18.00%
        isInterState: false,
        isTaxInclusive: false,
      );

      expect(breakdown.grossAmountPaise, equals(100000));
      expect(breakdown.discountPaise, equals(10000));
      expect(breakdown.taxableAmountPaise, equals(90000));
      expect(breakdown.cgstRateBasisPoints, equals(900));
      expect(breakdown.sgstRateBasisPoints, equals(900));
      expect(breakdown.igstRateBasisPoints, equals(0));
      expect(breakdown.cgstAmountPaise, equals(8100));
      expect(breakdown.sgstAmountPaise, equals(8100));
      expect(breakdown.igstAmountPaise, equals(0));
      expect(breakdown.taxAmountPaise, equals(16200));
      expect(breakdown.lineTotalPaise, equals(106200));
    });

    test('Tax-exclusive calculation for 18% inter-state single item', () {
      final breakdown = TaxEngine.calculateLineItemTax(
        ratePaise: 50000,
        quantityScaled: 2000,
        discountPaise: 10000,
        taxRateBasisPoints: 1800,
        isInterState: true,
        isTaxInclusive: false,
      );

      expect(breakdown.taxableAmountPaise, equals(90000));
      expect(breakdown.cgstAmountPaise, equals(0));
      expect(breakdown.sgstAmountPaise, equals(0));
      expect(breakdown.igstRateBasisPoints, equals(1800));
      expect(breakdown.igstAmountPaise, equals(16200));
      expect(breakdown.lineTotalPaise, equals(106200));
    });

    test('Tax-inclusive calculation (reverse calculation from MRP/Inclusive price)', () {
      // 1 item with price ₹118.00 inclusive of 18% GST (11800 paise)
      // Base Taxable = 11800 * 10000 / (10000 + 1800) = 11800 * 10000 / 11800 = 10000 paise (₹100.00)
      // Total GST = 1800 paise (₹18.00)
      // CGST (9%) = 900 paise, SGST (9%) = 900 paise
      final breakdown = TaxEngine.calculateLineItemTax(
        ratePaise: 11800,
        quantityScaled: 1000, // 1 unit
        discountPaise: 0,
        taxRateBasisPoints: 1800,
        isInterState: false,
        isTaxInclusive: true,
      );

      expect(breakdown.taxableAmountPaise, equals(10000));
      expect(breakdown.taxAmountPaise, equals(1800));
      expect(breakdown.cgstAmountPaise, equals(900));
      expect(breakdown.sgstAmountPaise, equals(900));
      expect(breakdown.lineTotalPaise, equals(11800));
    });

    test('Tests all standard GST slabs: 0%, 5%, 12%, 18%, 28%', () {
      final slabs = [0, 500, 1200, 1800, 2800];
      const taxable = 100000; // ₹1,000.00

      for (final slab in slabs) {
        final breakdown = TaxEngine.calculateLineItemTax(
          ratePaise: taxable,
          quantityScaled: 1000,
          discountPaise: 0,
          taxRateBasisPoints: slab,
          isInterState: false,
          isTaxInclusive: false,
        );

        final expectedTotalTax = (taxable * slab / 10000).round();
        expect(breakdown.taxAmountPaise, equals(expectedTotalTax));
        expect(breakdown.cgstAmountPaise + breakdown.sgstAmountPaise, equals(expectedTotalTax));
        expect(breakdown.lineTotalPaise, equals(taxable + expectedTotalTax));
      }
    });

    test('Splits odd-paisa tax between CGST and SGST deterministically without losing paise', () {
      // Taxable = ₹1.05 (105 paise) at 5% GST
      // Total tax = 105 * 500 / 10000 = 5.25 -> 5 paise
      // CGST = 5 ~/ 2 = 2 paise
      // SGST = 5 - 2 = 3 paise
      // Sum = 5 paise. Never fractional.
      final breakdown = TaxEngine.calculateLineItemTax(
        ratePaise: 105,
        quantityScaled: 1000,
        discountPaise: 0,
        taxRateBasisPoints: 500,
        isInterState: false,
        isTaxInclusive: false,
      );

      expect(breakdown.taxAmountPaise, equals(5));
      expect(breakdown.cgstAmountPaise, equals(2));
      expect(breakdown.sgstAmountPaise, equals(3));
      expect(breakdown.cgstAmountPaise + breakdown.sgstAmountPaise, equals(breakdown.taxAmountPaise));
    });

    test('Calculates fractional quantity accurately using scaled integers', () {
      // 1.750 kg (1750 scaled) at ₹400.00/kg (40000 paise)
      // Gross = (1750 * 40000) / 1000 = 70000 paise (₹700.00)
      // 5% GST = 3500 paise (₹35.00)
      // Line Total = 73500 paise (₹735.00)
      final breakdown = TaxEngine.calculateLineItemTax(
        ratePaise: 40000,
        quantityScaled: 1750,
        discountPaise: 0,
        taxRateBasisPoints: 500,
        isInterState: false,
        isTaxInclusive: false,
      );

      expect(breakdown.grossAmountPaise, equals(70000));
      expect(breakdown.taxableAmountPaise, equals(70000));
      expect(breakdown.taxAmountPaise, equals(3500));
      expect(breakdown.lineTotalPaise, equals(73500));
    });

    test('Aggregates multiple lines and computes invoice round-off', () {
      final line1 = TaxEngine.calculateLineItemTax(
        ratePaise: 9999, // ₹99.99
        quantityScaled: 1000,
        discountPaise: 0,
        taxRateBasisPoints: 1800,
        isInterState: false,
        isTaxInclusive: false,
      );
      // line1: taxable = 9999, tax = 1800 (CGST 900, SGST 900), total = 11799 paise

      final line2 = TaxEngine.calculateLineItemTax(
        ratePaise: 4950, // ₹49.50
        quantityScaled: 1000,
        discountPaise: 0,
        taxRateBasisPoints: 1200,
        isInterState: false,
        isTaxInclusive: false,
      );
      // line2: taxable = 4950, tax = 594 (CGST 297, SGST 297), total = 5544 paise

      final totals = TaxEngine.calculateInvoiceTotals(
        lines: [line1, line2],
        enableRoundOff: true,
      );

      expect(totals.taxableAmountPaise, equals(9999 + 4950)); // 14949 paise (₹149.49)
      expect(totals.cgstAmountPaise, equals(900 + 297)); // 1197 paise (₹11.97)
      expect(totals.sgstAmountPaise, equals(900 + 297)); // 1197 paise (₹11.97)
      expect(totals.taxAmountPaise, equals(1800 + 594)); // 2394 paise (₹23.94)

      final rawTotal = totals.taxableAmountPaise + totals.taxAmountPaise; // 17343 paise (₹173.43)
      expect(rawTotal, equals(17343));
      // Rounded to nearest rupee: ₹173.00 (17300 paise) -> Round-off is -43 paise
      expect(totals.roundOffPaise, equals(-43));
      expect(totals.totalAmountPaise, equals(17300));
      expect(totals.taxableAmountPaise + totals.taxAmountPaise + totals.roundOffPaise, equals(totals.totalAmountPaise));
    });

    test('Computes positive round-off when paise >= 50', () {
      // Suppose raw total is 17360 paise (₹173.60)
      final roundOff = TaxEngine.computeRoundOff(17360);
      expect(roundOff, equals(40)); // +40 paise to reach 17400
    });

    test('Zero round-off when amount is an exact rupee', () {
      final roundOff = TaxEngine.computeRoundOff(25000); // ₹250.00
      expect(roundOff, equals(0));
    });

    test('Disabling round-off produces 0 round-off and retains exact paise', () {
      final line = TaxEngine.calculateLineItemTax(
        ratePaise: 12345, // ₹123.45
        quantityScaled: 1000,
        discountPaise: 0,
        taxRateBasisPoints: 500,
        isInterState: false,
        isTaxInclusive: false,
      );
      final totals = TaxEngine.calculateInvoiceTotals(
        lines: [line],
        enableRoundOff: false,
      );

      expect(totals.roundOffPaise, equals(0));
      expect(totals.totalAmountPaise, equals(totals.taxableAmountPaise + totals.taxAmountPaise));
    });
  });
}
