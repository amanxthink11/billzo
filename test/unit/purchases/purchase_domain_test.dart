import 'package:flutter_test/flutter_test.dart';
import 'package:billzo/domain/invoice/tax_engine.dart';
import 'package:billzo/domain/purchase/itc_eligibility.dart';
import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_item.dart';
import 'package:billzo/domain/purchase/purchase_return.dart';
import 'package:billzo/domain/purchase/purchase_return_item.dart';
import 'package:billzo/domain/purchase/purchase_status.dart';
import 'package:billzo/domain/purchase/purchase_validator.dart';

void main() {
  group('Purchase Domain Model & Validation Tests', () {
    final now = DateTime(2026, 4, 1, 10, 0);

    PurchaseItem createItem({
      String id = 'item-1',
      String purchaseId = 'pur-1',
      String productId = 'prod-1',
      String productName = 'Raw Material Cotton',
      int quantityScaled = 2000, // 2.000 Units
      int purchaseRatePaise = 50000, // ₹500.00
      int discountPaise = 0,
      int taxableAmountPaise = 100000, // ₹1,000.00
      int rateBasisPoints = 1800, // 18% GST
      int cgstAmountPaise = 9000, // ₹90.00
      int sgstAmountPaise = 9000, // ₹90.00
      int igstAmountPaise = 0,
      int totalAmountPaise = 118000, // ₹1,180.00
      bool isItcEligible = true,
      bool trackInventory = true,
    }) {
      return PurchaseItem(
        id: id,
        purchaseId: purchaseId,
        productId: productId,
        productName: productName,
        unitCode: 'KG',
        quantityScaled: quantityScaled,
        purchaseRatePaise: purchaseRatePaise,
        discountPaise: discountPaise,
        taxableAmountPaise: taxableAmountPaise,
        taxRateId: 'GST_18',
        rateBasisPoints: rateBasisPoints,
        cgstRateBasisPoints: rateBasisPoints ~/ 2,
        cgstAmountPaise: cgstAmountPaise,
        sgstRateBasisPoints: rateBasisPoints ~/ 2,
        sgstAmountPaise: sgstAmountPaise,
        igstRateBasisPoints: 0,
        igstAmountPaise: igstAmountPaise,
        totalAmountPaise: totalAmountPaise,
        isItcEligible: isItcEligible,
        trackInventory: trackInventory,
        createdAt: now,
        updatedAt: now,
      );
    }

    Purchase createPurchase({
      String id = 'pur-1',
      String businessId = 'biz-1',
      String supplierId = 'supp-1',
      String purchaseNumber = 'PO-2026-0001',
      String? supplierInvoiceNumber = 'SUPP-INV-999',
      PurchaseStatus status = PurchaseStatus.draft,
      ItcEligibility itcEligibility = ItcEligibility.eligible,
      int taxableAmountPaise = 100000,
      int cgstPaise = 9000,
      int sgstPaise = 9000,
      int igstPaise = 0,
      int totalAmountPaise = 118000,
      int paidAmountPaise = 0,
      int balanceAmountPaise = 118000,
      List<PurchaseItem>? items,
    }) {
      final itemList = items ?? [createItem()];
      return Purchase(
        id: id,
        businessId: businessId,
        supplierId: supplierId,
        purchaseNumber: purchaseNumber,
        supplierInvoiceNumber: supplierInvoiceNumber,
        supplierInvoiceDate: now,
        purchaseDate: now,
        dueDate: now.add(const Duration(days: 30)),
        placeOfSupplyStateCode: '27',
        status: status,
        subtotalPaise: taxableAmountPaise,
        discountPaise: 0,
        taxableAmountPaise: taxableAmountPaise,
        cgstPaise: cgstPaise,
        sgstPaise: sgstPaise,
        igstPaise: igstPaise,
        cessPaise: 0,
        roundOffPaise: 0,
        totalAmountPaise: totalAmountPaise,
        paidAmountPaise: paidAmountPaise,
        balanceAmountPaise: balanceAmountPaise,
        itcEligibility: itcEligibility,
        inputCgstPaise: itcEligibility == ItcEligibility.eligible ? cgstPaise : 0,
        inputSgstPaise: itcEligibility == ItcEligibility.eligible ? sgstPaise : 0,
        inputIgstPaise: itcEligibility == ItcEligibility.eligible ? igstPaise : 0,
        items: itemList,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('Valid draft purchase passes validation', () {
      final purchase = createPurchase(status: PurchaseStatus.draft);
      final result = PurchaseValidator.validate(purchase);
      expect(result.isValid, isTrue);
      expect(result.hasErrors, isFalse);
    });

    test('Finalized purchase requires supplier invoice number', () {
      final purchase = createPurchase(
        status: PurchaseStatus.finalized,
        supplierInvoiceNumber: '',
      );
      final result = PurchaseValidator.validate(purchase);
      expect(result.isValid, isFalse);
      expect(result.errors.containsKey('supplierInvoiceNumber'), isTrue);
    });

    test('Purchase requires businessId and supplierId', () {
      final noBiz = createPurchase(businessId: '   ');
      expect(PurchaseValidator.validate(noBiz).errors.containsKey('businessId'), isTrue);

      final noSupp = createPurchase(supplierId: '');
      expect(PurchaseValidator.validate(noSupp).errors.containsKey('supplierId'), isTrue);
    });

    test('Purchase requires at least one item', () {
      final noItems = createPurchase(items: []);
      final result = PurchaseValidator.validate(noItems);
      expect(result.isValid, isFalse);
      expect(result.errors.containsKey('items'), isTrue);
    });

    test('Purchase item requires strictly positive quantity and non-negative rate', () {
      final badQtyItem = createItem(quantityScaled: 0);
      final p1 = createPurchase(items: [badQtyItem]);
      expect(PurchaseValidator.validate(p1).errors.containsKey('items[0].quantity'), isTrue);

      final negRateItem = createItem(purchaseRatePaise: -100);
      final p2 = createPurchase(items: [negRateItem]);
      expect(PurchaseValidator.validate(p2).errors.containsKey('items[0].rate'), isTrue);
    });

    test('GST calculation handles intra-state CGST + SGST properly', () {
      final breakdown = TaxEngine.calculateLineItemTax(
        ratePaise: 100000, // ₹1,000.00
        quantityScaled: 1000, // 1 unit
        discountPaise: 0,
        taxRateBasisPoints: 1800, // 18%
        isInterState: false,
      );

      expect(breakdown.cgstAmount.paise, 9000); // ₹90.00
      expect(breakdown.sgstAmount.paise, 9000); // ₹90.00
      expect(breakdown.igstAmount.paise, 0);
      expect(breakdown.totalTax.paise, 18000); // ₹180.00
    });

    test('GST calculation handles inter-state IGST properly', () {
      final breakdown = TaxEngine.calculateLineItemTax(
        ratePaise: 100000, // ₹1,000.00
        quantityScaled: 1000, // 1 unit
        discountPaise: 0,
        taxRateBasisPoints: 1800, // 18%
        isInterState: true,
      );

      expect(breakdown.cgstAmount.paise, 0);
      expect(breakdown.sgstAmount.paise, 0);
      expect(breakdown.igstAmount.paise, 18000); // ₹180.00
      expect(breakdown.totalTax.paise, 18000);
    });

    test('Input Tax Credit eligibility distinction works as expected', () {
      final eligiblePurchase = createPurchase(
        itcEligibility: ItcEligibility.eligible,
        cgstPaise: 9000,
        sgstPaise: 9000,
      );
      expect(eligiblePurchase.eligibleItcPaise, 18000);
      expect(eligiblePurchase.ineligibleItcPaise, 0);

      final ineligiblePurchase = createPurchase(
        itcEligibility: ItcEligibility.ineligible,
        cgstPaise: 9000,
        sgstPaise: 9000,
      );
      expect(ineligiblePurchase.eligibleItcPaise, 0);
      expect(ineligiblePurchase.ineligibleItcPaise, 18000);
    });

    test('Purchase return validation enforces strict positive quantity and limits against purchase', () {
      final origItem = createItem(id: 'item-10', quantityScaled: 5000); // 5.000 KG
      final origPurchase = createPurchase(
        id: 'pur-10',
        status: PurchaseStatus.finalized,
        items: [origItem],
      );

      final returnItem = PurchaseReturnItem(
        id: 'ret-item-1',
        purchaseReturnId: 'ret-1',
        purchaseItemId: 'item-10',
        productId: origItem.productId,
        productName: origItem.productName,
        quantityScaled: 2000, // 2.000 KG returned
        ratePaise: origItem.ratePaise,
        taxableAmountPaise: 100000,
        totalAmountPaise: 118000,
        createdAt: now,
        updatedAt: now,
      );

      final purchaseReturn = PurchaseReturn(
        id: 'ret-1',
        businessId: origPurchase.businessId,
        supplierId: origPurchase.supplierId,
        originalPurchaseId: origPurchase.id,
        returnNumber: 'DN-2026-0001',
        returnDate: now,
        taxableAmountPaise: 100000,
        totalAmountPaise: 118000,
        items: [returnItem],
        createdAt: now,
        updatedAt: now,
      );

      final validResult = PurchaseValidator.validateReturn(
        purchaseReturn,
        originalPurchase: origPurchase,
      );
      expect(validResult.isValid, isTrue);

      // Over-return scenario: returning 6.000 KG when only 5.000 KG purchased
      final overReturnItem = PurchaseReturnItem(
        id: 'ret-item-2',
        purchaseReturnId: 'ret-1',
        purchaseItemId: 'item-10',
        productId: origItem.productId,
        productName: origItem.productName,
        quantityScaled: 6000, // exceeds 5.000
        ratePaise: origItem.ratePaise,
        taxableAmountPaise: 300000,
        totalAmountPaise: 354000,
        createdAt: now,
        updatedAt: now,
      );

      final overReturn = purchaseReturn.copyWith(items: [overReturnItem]);
      final overResult = PurchaseValidator.validateReturn(
        overReturn,
        originalPurchase: origPurchase,
      );
      expect(overResult.isValid, isFalse);
      expect(overResult.firstError, contains('Maximum returnable'));
    });

    test('Purchase return rejects returning from draft or cancelled purchase', () {
      final draftPurchase = createPurchase(status: PurchaseStatus.draft);
      final returnItem = PurchaseReturnItem(
        id: 'ret-item-1',
        purchaseReturnId: 'ret-1',
        purchaseItemId: draftPurchase.items.first.id,
        productId: draftPurchase.items.first.productId,
        productName: draftPurchase.items.first.productName,
        quantityScaled: 1000,
        ratePaise: 10000,
        taxableAmountPaise: 10000,
        totalAmountPaise: 11800,
        createdAt: now,
        updatedAt: now,
      );

      final pReturn = PurchaseReturn(
        id: 'ret-1',
        businessId: draftPurchase.businessId,
        supplierId: draftPurchase.supplierId,
        originalPurchaseId: draftPurchase.id,
        returnNumber: 'DN-2026-0001',
        returnDate: now,
        taxableAmountPaise: 10000,
        totalAmountPaise: 11800,
        items: [returnItem],
        createdAt: now,
        updatedAt: now,
      );

      final draftReturnResult = PurchaseValidator.validateReturn(
        pReturn,
        originalPurchase: draftPurchase,
      );
      expect(draftReturnResult.isValid, isFalse);
      expect(draftReturnResult.firstError, contains('unfinalized draft'));

      final cancelledPurchase = createPurchase(status: PurchaseStatus.cancelled);
      final cancelledReturnResult = PurchaseValidator.validateReturn(
        pReturn,
        originalPurchase: cancelledPurchase,
      );
      expect(cancelledReturnResult.isValid, isFalse);
      expect(cancelledReturnResult.firstError, contains('cancelled purchase'));
    });
  });
}
