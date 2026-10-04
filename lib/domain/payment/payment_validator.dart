import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/payment/payment.dart';
import 'package:billzo/domain/payment/payment_allocation.dart';
import 'package:billzo/domain/purchase/purchase.dart';

class PaymentValidationResult {
  final Map<String, String> errors;

  const PaymentValidationResult([this.errors = const {}]);

  bool get isValid => errors.isEmpty;
  bool get hasErrors => errors.isNotEmpty;
  String? get firstError => errors.values.isEmpty ? null : errors.values.first;
}

/// Pure domain validator for customer payments and invoice allocations.
class PaymentValidator {
  PaymentValidator._();

  /// Validates a payment aggregate for statutory, relational, and mathematical correctness.
  static PaymentValidationResult validate(Payment payment) {
    final Map<String, String> errors = {};

    if (payment.businessId.trim().isEmpty) {
      errors['businessId'] = 'Business ID is required.';
    }

    if (payment.customerId.trim().isEmpty) {
      final message = payment.isSupplierPayment
          ? 'Supplier selection is required.'
          : 'Customer selection is required.';
      errors['customerId'] = message;
      errors['partyId'] = message;
    }

    if (payment.amountPaise <= 0) {
      errors['amount'] = 'Payment amount must be strictly greater than zero.';
    }

    // Mathematical invariant: Allocated amount cannot exceed payment amount
    if (payment.allocatedAmountPaise > payment.amountPaise) {
      errors['allocations'] =
          'Total allocated amount (₹${payment.allocatedAmount.toIndianRupeeString()}) cannot exceed the payment amount (₹${payment.amount.toIndianRupeeString()}).';
    }

    // Verify allocations uniqueness (no duplicate document allocation within same payment)
    final seenDocIds = <String>{};
    for (final allocation in payment.allocations) {
      if (allocation.allocatedAmountPaise <= 0) {
        errors['allocation_${allocation.documentId}'] =
            'Allocation amount for document ${allocation.invoiceNumber ?? allocation.documentId} must be greater than zero.';
      }
      if (seenDocIds.contains(allocation.documentId)) {
        errors['duplicate_${allocation.documentId}'] =
            'Duplicate allocation found for document ${allocation.invoiceNumber ?? allocation.documentId}.';
      }
      seenDocIds.add(allocation.documentId);
    }

    return PaymentValidationResult(errors);
  }

  /// Validates whether an allocation can be applied against an invoice.
  static PaymentValidationResult validateAllocationAgainstInvoice({
    required PaymentAllocation allocation,
    required Invoice invoice,
  }) {
    final Map<String, String> errors = {};

    if (allocation.allocatedAmountPaise <= 0) {
      errors['amount'] = 'Allocated amount must be strictly greater than zero.';
      return PaymentValidationResult(errors);
    }

    if (invoice.status == InvoiceStatus.draft) {
      errors['status'] =
          'Cannot allocate payment to a draft invoice (${invoice.invoiceNumber}). The invoice must be finalized first.';
    }

    if (invoice.status == InvoiceStatus.cancelled) {
      errors['status'] =
          'Cannot allocate payment to a cancelled invoice (${invoice.invoiceNumber}).';
    }

    if (allocation.allocatedAmountPaise > invoice.balanceAmountPaise) {
      errors['overAllocation'] =
          'Allocated amount (₹${allocation.allocatedAmount.toIndianRupeeString()}) cannot exceed invoice outstanding balance (₹${invoice.balanceAmount.toIndianRupeeString()}).';
    }

    return PaymentValidationResult(errors);
  }

  /// Validates whether an allocation can be applied against a purchase bill.
  static PaymentValidationResult validateAllocationAgainstPurchase({
    required PaymentAllocation allocation,
    required Purchase purchase,
  }) {
    final Map<String, String> errors = {};

    if (allocation.allocatedAmountPaise <= 0) {
      errors['amount'] = 'Allocated amount must be strictly greater than zero.';
      return PaymentValidationResult(errors);
    }

    if (purchase.isDraft) {
      errors['status'] =
          'Cannot allocate payment to a draft purchase bill (${purchase.purchaseNumber}). The purchase bill must be finalized first.';
    }

    if (purchase.isCancelled) {
      errors['status'] =
          'Cannot allocate payment to a cancelled purchase bill (${purchase.purchaseNumber}).';
    }

    if (allocation.allocatedAmountPaise > purchase.balanceAmountPaise) {
      errors['overAllocation'] =
          'Allocated amount (₹${allocation.allocatedAmount.toIndianRupeeString()}) cannot exceed purchase outstanding balance (₹${purchase.balanceAmount.toIndianRupeeString()}).';
    }

    return PaymentValidationResult(errors);
  }
}
