import 'package:billzo/domain/recurring/recurring_frequency.dart';
import 'package:billzo/domain/recurring/recurring_invoice.dart';
import 'package:billzo/domain/recurring/recurring_invoice_item.dart';
import 'package:billzo/domain/recurring/recurring_invoice_status.dart';

/// Domain validation rules for recurring invoice profiles and transitions.
class RecurringInvoiceValidator {
  RecurringInvoiceValidator._();

  static List<String> validate(RecurringInvoice profile) {
    final errors = <String>[];

    if (profile.profileName.trim().isEmpty) {
      errors.add('Profile name cannot be empty.');
    }

    if (profile.businessId.trim().isEmpty) {
      errors.add('Business ID is required.');
    }

    if (profile.customerId.trim().isEmpty) {
      errors.add('Customer must be selected.');
    }

    if (profile.frequency == RecurringFrequency.custom) {
      if (profile.customIntervalDays == null || profile.customIntervalDays! <= 0) {
        errors.add('Custom frequency requires an interval of at least 1 day.');
      }
    }

    if (profile.endDate != null) {
      final startDay = DateTime(profile.startDate.year, profile.startDate.month, profile.startDate.day);
      final endDay = DateTime(profile.endDate!.year, profile.endDate!.month, profile.endDate!.day);
      if (endDay.isBefore(startDay)) {
        errors.add('End date cannot be earlier than start date.');
      }
    }

    if (profile.items.isEmpty) {
      errors.add('At least one item line is required for a recurring invoice.');
    }

    for (int i = 0; i < profile.items.length; i++) {
      final item = profile.items[i];
      errors.addAll(validateItem(item, index: i + 1));
    }

    return errors;
  }

  static List<String> validateItem(RecurringInvoiceItem item, {int index = 1}) {
    final errors = <String>[];

    if (item.productId.trim().isEmpty) {
      errors.add('Line $index: Product must be selected.');
    }

    if (item.quantity <= 0) {
      errors.add('Line $index: Quantity must be greater than zero.');
    }

    if (item.ratePaise < 0) {
      errors.add('Line $index: Rate cannot be negative.');
    }

    if (item.discountPaise < 0) {
      errors.add('Line $index: Discount cannot be negative.');
    }

    return errors;
  }

  static void checkStatusTransition(RecurringInvoiceStatus current, RecurringInvoiceStatus target) {
    if (current == target) return;

    if (current == RecurringInvoiceStatus.cancelled) {
      throw StateError('Cannot change status of a cancelled recurring profile.');
    }

    if (current == RecurringInvoiceStatus.completed) {
      throw StateError('Cannot change status of a completed recurring profile.');
    }

    if (current == RecurringInvoiceStatus.active && target == RecurringInvoiceStatus.paused) {
      return;
    }

    if (current == RecurringInvoiceStatus.paused && target == RecurringInvoiceStatus.active) {
      return;
    }

    if (target == RecurringInvoiceStatus.cancelled || target == RecurringInvoiceStatus.completed) {
      return;
    }

    throw StateError('Invalid status transition from ${current.name} to ${target.name}.');
  }
}
