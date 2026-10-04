import 'package:billzo/core/constants/indian_states.dart';
import 'package:billzo/domain/invoice/invoice.dart';

/// Validation result holding structured validation errors.
class InvoiceValidationResult {
  final Map<String, String> errors;

  const InvoiceValidationResult({this.errors = const {}});

  bool get isValid => errors.isEmpty;
  bool get hasErrors => errors.isNotEmpty;
  String? get firstError => errors.values.isNotEmpty ? errors.values.first : null;
}

/// Pure domain validator for Sales Invoices.
class InvoiceValidator {
  InvoiceValidator._();

  static InvoiceValidationResult validate(Invoice invoice) {
    final Map<String, String> errors = {};

    if (invoice.businessId.trim().isEmpty) {
      errors['businessId'] = 'Business ID is required.';
    }

    if (invoice.customerId.trim().isEmpty) {
      errors['customerId'] = 'Customer selection is required.';
    }

    final posCode = invoice.placeOfSupplyStateCode.trim().padLeft(2, '0');
    final validStates = IndianStates.all.map((s) => s.code).toSet();
    if (!validStates.contains(posCode)) {
      errors['placeOfSupply'] = 'Valid 2-digit Indian State code is required for Place of Supply.';
    }

    if (invoice.dueDate.isBefore(DateTime(invoice.invoiceDate.year, invoice.invoiceDate.month, invoice.invoiceDate.day))) {
      errors['dueDate'] = 'Due date cannot be earlier than invoice date.';
    }

    if (invoice.items.isEmpty) {
      errors['items'] = 'Invoice must have at least one line item.';
    }

    for (int i = 0; i < invoice.items.length; i++) {
      final item = invoice.items[i];
      if (item.productId.trim().isEmpty) {
        errors['item_${i}_product'] = 'Item #${i + 1} has invalid product reference.';
      }
      if (item.quantityScaled <= 0) {
        errors['item_${i}_quantity'] = 'Item #${i + 1} ("${item.productName}") must have quantity greater than 0.';
      }
      if (item.ratePaise < 0) {
        errors['item_${i}_rate'] = 'Item #${i + 1} ("${item.productName}") cannot have negative rate.';
      }
      if (item.discountPaise < 0) {
        errors['item_${i}_discount'] = 'Item #${i + 1} ("${item.productName}") cannot have negative discount.';
      }
      if (item.taxableAmountPaise < 0) {
        errors['item_${i}_taxable'] = 'Item #${i + 1} ("${item.productName}") cannot have negative taxable amount.';
      }
    }

    // Financial invariant verification
    final expectedTotal = invoice.taxableAmountPaise +
        invoice.cgstPaise +
        invoice.sgstPaise +
        invoice.igstPaise +
        invoice.cessPaise +
        invoice.roundOffPaise;

    if (expectedTotal != invoice.totalAmountPaise) {
      errors['financialInvariant'] =
          'Financial invariant failure: Expected total $expectedTotal paise, but got ${invoice.totalAmountPaise} paise.';
    }

    return InvoiceValidationResult(errors: errors);
  }
}
