import 'package:billzo/domain/expense/expense.dart';
import 'package:billzo/domain/expense/expense_status.dart';

/// Validation results holder for Expense operations.
class ExpenseValidationResult {
  final bool isValid;
  final List<String> errors;

  const ExpenseValidationResult({
    required this.isValid,
    this.errors = const [],
  });

  factory ExpenseValidationResult.success() => const ExpenseValidationResult(isValid: true);

  factory ExpenseValidationResult.failure(List<String> errors) =>
      ExpenseValidationResult(isValid: false, errors: errors);

  String get errorMessage => errors.join('; ');
}

/// Domain validation rules for Expense creation, updating, posting, and cancellation.
class ExpenseValidator {
  ExpenseValidator._();

  /// Validates an expense before saving (as draft or posted).
  static ExpenseValidationResult validate(Expense expense, {bool isPosting = false}) {
    final errors = <String>[];

    if (expense.businessId.trim().isEmpty) {
      errors.add('Business ID is required');
    }

    if (expense.payee.trim().isEmpty) {
      errors.add('Payee or vendor name is required');
    }

    if (expense.categoryId.trim().isEmpty) {
      errors.add('Expense category is required');
    }

    if (expense.taxableAmountPaise < 0) {
      errors.add('Taxable amount cannot be negative');
    }

    if (expense.cgstPaise < 0 || expense.sgstPaise < 0 || expense.igstPaise < 0) {
      errors.add('Tax amounts cannot be negative');
    }

    final calculatedGst = expense.cgstPaise + expense.sgstPaise + expense.igstPaise;
    if (expense.totalGstPaise != calculatedGst) {
      errors.add('Total GST ($expense.totalGstPaise) does not match sum of CGST, SGST, and IGST ($calculatedGst)');
    }

    final expectedTotal = expense.taxableAmountPaise + expense.totalGstPaise;
    if (expense.totalAmountPaise != expectedTotal) {
      errors.add('Total amount ($expense.totalAmountPaise) does not match taxable + tax ($expectedTotal)');
    }

    if (isPosting || expense.status == ExpenseStatus.posted) {
      if (expense.totalAmountPaise <= 0) {
        errors.add('Total expense amount must be greater than zero to post');
      }

      if (expense.paymentAccountId == null || expense.paymentAccountId!.trim().isEmpty) {
        errors.add('A payment holding account (Cash or Bank) is required to post an expense');
      }
    }

    return errors.isEmpty
        ? ExpenseValidationResult.success()
        : ExpenseValidationResult.failure(errors);
  }

  /// Validates an expense cancellation request.
  static ExpenseValidationResult validateCancellation({
    required Expense expense,
    required String reason,
  }) {
    final errors = <String>[];

    if (expense.status != ExpenseStatus.posted) {
      errors.add('Only posted expenses can be cancelled. Current status: ${expense.status.displayName}');
    }

    if (reason.trim().length < 3) {
      errors.add('A valid cancellation reason (minimum 3 characters) is required');
    }

    return errors.isEmpty
        ? ExpenseValidationResult.success()
        : ExpenseValidationResult.failure(errors);
  }

  /// Validates status transition between two states.
  static ExpenseValidationResult validateStatusTransition(
    ExpenseStatus current,
    ExpenseStatus next,
  ) {
    if (!current.canTransitionTo(next)) {
      return ExpenseValidationResult.failure([
        'Illegal status transition from ${current.displayName} to ${next.displayName}',
      ]);
    }
    return ExpenseValidationResult.success();
  }
}
