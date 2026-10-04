import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_item.dart';
import 'package:billzo/domain/purchase/purchase_return.dart';

/// Validation result container for purchase domain operations.
class PurchaseValidationResult {
  final Map<String, String> errors;

  const PurchaseValidationResult(this.errors);

  bool get isValid => errors.isEmpty;
  bool get hasErrors => errors.isNotEmpty;
  String? get firstError => errors.values.isNotEmpty ? errors.values.first : null;
}

/// Domain validation service for purchases and purchase returns.
class PurchaseValidator {
  PurchaseValidator._();

  /// Validates a [Purchase] bill aggregate.
  static PurchaseValidationResult validate(Purchase purchase) {
    final errors = <String, String>{};

    if (purchase.businessId.trim().isEmpty) {
      errors['businessId'] = 'Business ID is required.';
    }

    if (purchase.supplierId.trim().isEmpty) {
      errors['supplierId'] = 'Supplier is required.';
    }

    if (purchase.isFinalized &&
        (purchase.supplierInvoiceNumber == null ||
            purchase.supplierInvoiceNumber!.trim().isEmpty)) {
      errors['supplierInvoiceNumber'] =
          'Supplier invoice number is mandatory for finalized bills.';
    }

    if (purchase.items.isEmpty) {
      errors['items'] = 'At least one item is required in the purchase bill.';
    }

    for (int i = 0; i < purchase.items.length; i++) {
      final item = purchase.items[i];
      final itemErrors = validateItem(item, index: i);
      errors.addAll(itemErrors);
    }

    // Invariant: Total = Taxable + CGST + SGST + IGST + Cess + RoundOff
    final expectedTotalBeforeRoundOff = purchase.taxableAmountPaise +
        purchase.cgstPaise +
        purchase.sgstPaise +
        purchase.igstPaise +
        purchase.cessPaise;

    final expectedGrandTotal = expectedTotalBeforeRoundOff + purchase.roundOffPaise;
    if (purchase.totalAmountPaise != expectedGrandTotal) {
      errors['totalAmount'] =
          'Purchase total ($purchase.totalAmountPaise) does not match components sum ($expectedGrandTotal).';
    }

    // Invariant: Balance = Total - Paid
    final expectedBalance = purchase.totalAmountPaise - purchase.paidAmountPaise;
    if (purchase.balanceAmountPaise != expectedBalance) {
      errors['balanceAmount'] =
          'Purchase balance ($purchase.balanceAmountPaise) does not match total minus paid ($expectedBalance).';
    }

    return PurchaseValidationResult(errors);
  }

  /// Validates an individual [PurchaseItem].
  static Map<String, String> validateItem(PurchaseItem item, {int? index}) {
    final prefix = index != null ? 'items[$index].' : '';
    final errors = <String, String>{};

    if (item.productId.trim().isEmpty) {
      errors['${prefix}productId'] = 'Product is required for each line item.';
    }

    if (item.quantityScaled <= 0) {
      errors['${prefix}quantity'] = 'Quantity must be greater than zero.';
    }

    if (item.purchaseRatePaise < 0) {
      errors['${prefix}rate'] = 'Purchase rate cannot be negative.';
    }

    if (item.discountPaise < 0) {
      errors['${prefix}discount'] = 'Discount cannot be negative.';
    }

    if (item.taxableAmountPaise < 0) {
      errors['${prefix}taxableAmount'] = 'Taxable amount cannot be negative.';
    }

    if (item.totalAmountPaise < 0) {
      errors['${prefix}totalAmount'] = 'Line total cannot be negative.';
    }

    return errors;
  }

  /// Validates a [PurchaseReturn] / Debit Note.
  static PurchaseValidationResult validateReturn(
    PurchaseReturn purchaseReturn, {
    Purchase? originalPurchase,
    Map<String, int>? previouslyReturnedQuantities,
  }) {
    final errors = <String, String>{};

    if (purchaseReturn.businessId.trim().isEmpty) {
      errors['businessId'] = 'Business ID is required.';
    }

    if (purchaseReturn.supplierId.trim().isEmpty) {
      errors['supplierId'] = 'Supplier is required.';
    }

    if (purchaseReturn.originalPurchaseId.trim().isEmpty) {
      errors['originalPurchaseId'] = 'Original purchase reference is required for a return.';
    }

    if (purchaseReturn.items.isEmpty) {
      errors['items'] = 'At least one item must be returned.';
    }

    if (originalPurchase != null) {
      if (originalPurchase.isCancelled) {
        errors['originalPurchase'] = 'Cannot return items from a cancelled purchase bill.';
      }

      if (originalPurchase.isDraft) {
        errors['originalPurchase'] = 'Cannot return items from an unfinalized draft purchase.';
      }

      // Quantity validation against original purchase
      final originalItemMap = {
        for (final item in originalPurchase.items)
          (item.id.isNotEmpty ? item.id : item.productId): item,
      };

      for (int i = 0; i < purchaseReturn.items.length; i++) {
        final retItem = purchaseReturn.items[i];
        if (retItem.quantityScaled <= 0) {
          errors['items[$i].quantity'] = 'Return quantity must be strictly positive.';
          continue;
        }

        // Match against original purchase item
        final origItem = (retItem.purchaseItemId != null
                ? originalItemMap[retItem.purchaseItemId]
                : null) ??
            originalPurchase.items.cast<PurchaseItem?>().firstWhere(
                  (item) => item?.productId == retItem.productId,
                  orElse: () => null,
                );

        if (origItem == null) {
          errors['items[$i].product'] =
              'Product ${retItem.productName} was not found on the original purchase bill.';
          continue;
        }

        final previouslyReturned =
            previouslyReturnedQuantities?[origItem.id] ??
            previouslyReturnedQuantities?[origItem.productId] ??
            0;

        final availableToReturn = origItem.quantityScaled - previouslyReturned;
        if (retItem.quantityScaled > availableToReturn) {
          final maxDecimal = availableToReturn / 1000.0;
          errors['items[$i].quantity'] =
              'Cannot return ${retItem.quantity} of ${retItem.productName}. Maximum returnable: $maxDecimal.';
        }
      }
    }

    return PurchaseValidationResult(errors);
  }
}
