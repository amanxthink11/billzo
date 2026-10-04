import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_item.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/invoice/tax_engine.dart';

void main() {
  const uuid = Uuid();

  group('Service Billing Regression Tests', () {
    test('Service items have ItemType.service and do not require inventory stock', () {
      final serviceProduct = Product(
        id: uuid.v4(),
        businessId: 'biz-1',
        name: 'WhatsApp Business API Starter Plan',
        itemType: ItemType.service,
        unitId: 'unit-srv',
        sellingPricePaise: 99900,
        purchasePricePaise: 0,
        hsnSacCode: '998313', // Information technology consulting and support services
        taxRateId: 'tax-18',
        isTaxInclusive: false,
        currentStock: 0, // Zero inventory stock is completely normal for services
        lowStockThreshold: null, // Services do not track inventory thresholds
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      expect(serviceProduct.isService, isTrue);
      expect(serviceProduct.isGoods, isFalse);
      expect(serviceProduct.sellingPrice.paise, equals(99900));
      expect(serviceProduct.hsnSacCode, equals('998313'));
      expect(serviceProduct.currentStock, equals(0));
    });

    test('Service GST calculation works exactly like goods taxation (18% Intra-state & Inter-state)', () {
      // Intra-state service billing (e.g., selling ₹1,000 service with 18% GST)
      final intraResult = TaxEngine.calculateLineItemTax(
        ratePaise: 100000,
        quantityScaled: 1000,
        discountPaise: 0,
        taxRateBasisPoints: 1800,
        isInterState: false,
        isTaxInclusive: false,
      );

      expect(intraResult.taxableAmountPaise, equals(100000));
      expect(intraResult.cgstAmountPaise, equals(9000)); // 9%
      expect(intraResult.sgstAmountPaise, equals(9000)); // 9%
      expect(intraResult.igstAmountPaise, equals(0));
      expect(intraResult.lineTotalPaise, equals(118000)); // ₹1,180.00

      // Inter-state service billing (e.g., selling ₹1,000 service with 18% IGST)
      final interResult = TaxEngine.calculateLineItemTax(
        ratePaise: 100000,
        quantityScaled: 1000,
        discountPaise: 0,
        taxRateBasisPoints: 1800,
        isInterState: true,
        isTaxInclusive: false,
      );

      expect(interResult.taxableAmountPaise, equals(100000));
      expect(interResult.cgstAmountPaise, equals(0));
      expect(interResult.sgstAmountPaise, equals(0));
      expect(interResult.igstAmountPaise, equals(18000)); // 18% IGST
      expect(interResult.lineTotalPaise, equals(118000)); // ₹1,180.00
    });

    test('Service invoice items can be combined with goods in same invoice with accurate accounting totals', () {
      final invoiceId = uuid.v4();
      final now = DateTime.now().toUtc();
      final items = [
        InvoiceItem(
          id: uuid.v4(),
          invoiceId: invoiceId,
          productId: 'prod-service-1',
          taxRateId: 'tax-18',
          productName: 'Web Development & Maintenance Service',
          hsnSac: '998314',
          quantityScaled: 1000,
          unitCode: 'SRV',
          ratePaise: 500000, // ₹5,000.00
          discountPaise: 0,
          taxableAmountPaise: 500000,
          cgstRateBasisPoints: 900,
          cgstAmountPaise: 45000,
          sgstRateBasisPoints: 900,
          sgstAmountPaise: 45000,
          igstRateBasisPoints: 0,
          igstAmountPaise: 0,
          cessRateBasisPoints: 0,
          cessAmountPaise: 0,
          totalAmountPaise: 590000, // ₹5,900.00
          trackInventory: false, // Services do not track or deduct inventory stock
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final invoice = Invoice(
        id: invoiceId,
        businessId: 'biz-1',
        invoiceNumber: 'INV-2026-0001',
        customerId: 'cust-1',
        invoiceDate: now,
        dueDate: now.add(const Duration(days: 15)),
        placeOfSupplyStateCode: '27',
        status: InvoiceStatus.finalized,
        subtotalPaise: 500000,
        taxableAmountPaise: 500000,
        cgstPaise: 45000,
        sgstPaise: 45000,
        igstPaise: 0,
        roundOffPaise: 0,
        totalAmountPaise: 590000,
        paidAmountPaise: 0,
        balanceAmountPaise: 590000,
        items: items,
        createdAt: now,
        updatedAt: now,
      );

      // Verify invoice totals and payment status
      expect(invoice.totalAmount, equals(Money.fromPaise(590000)));
      expect(invoice.taxableAmount, equals(Money.fromPaise(500000)));
      expect(invoice.cgst, equals(Money.fromPaise(45000)));
      expect(invoice.sgst, equals(Money.fromPaise(45000)));
      expect(invoice.paymentStatus, equals(InvoicePaymentStatus.due));
      expect(invoice.lifecycleStatus, equals(InvoiceLifecycleStatus.finalized));
      expect(invoice.items.first.trackInventory, isFalse);
    });
  });
}
