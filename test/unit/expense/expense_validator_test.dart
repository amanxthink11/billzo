import 'package:flutter_test/flutter_test.dart';

import 'package:billzo/domain/expense/expense.dart';
import 'package:billzo/domain/expense/expense_status.dart';
import 'package:billzo/domain/expense/expense_validator.dart';
import 'package:billzo/domain/payment/payment_method.dart';

void main() {
  group('ExpenseValidator Validation Tests', () {
    final validExpense = Expense(
      id: 'exp-valid-1',
      businessId: 'biz-1',
      categoryId: 'cat-rent',
      categoryName: 'Rent',
      expenseDate: DateTime(2026, 3, 10),
      payee: 'Apex Office Complexes',
      description: 'Monthly office rent',
      taxableAmountPaise: 1000000, // ₹10,000.00
      cgstPaise: 90000,           // ₹900.00
      sgstPaise: 90000,           // ₹900.00
      igstPaise: 0,
      totalGstPaise: 180000,       // ₹1,800.00
      totalAmountPaise: 1180000,   // ₹11,800.00
      paymentAccountId: 'acc-bank-1',
      paymentMethod: PaymentMethod.bankTransfer,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    test('Valid draft expense passes validation', () {
      final res = ExpenseValidator.validate(validExpense);
      expect(res.isValid, isTrue);
      expect(res.errors, isEmpty);
    });

    test('Valid posted expense passes posting validation', () {
      final res = ExpenseValidator.validate(validExpense, isPosting: true);
      expect(res.isValid, isTrue);
      expect(res.errors, isEmpty);
    });

    test('Missing businessId fails validation', () {
      final res = ExpenseValidator.validate(validExpense.copyWith(businessId: ''));
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Business ID is required'));
    });

    test('Missing payee fails validation', () {
      final res = ExpenseValidator.validate(validExpense.copyWith(payee: '   '));
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Payee or vendor name is required'));
    });

    test('Missing categoryId fails validation', () {
      final res = ExpenseValidator.validate(validExpense.copyWith(categoryId: ''));
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Expense category is required'));
    });

    test('Negative taxable amount fails validation', () {
      final res = ExpenseValidator.validate(validExpense.copyWith(
        taxableAmountPaise: -500,
        totalAmountPaise: -500 + validExpense.totalGstPaise,
      ));
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Taxable amount cannot be negative'));
    });

    test('Negative tax amounts fail validation', () {
      final res = ExpenseValidator.validate(validExpense.copyWith(
        cgstPaise: -100,
      ));
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Tax amounts cannot be negative'));
    });

    test('Mismatched total GST fails validation', () {
      final res = ExpenseValidator.validate(validExpense.copyWith(
        totalGstPaise: 200000, // Should be 180000 (90000 + 90000)
      ));
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Total GST'));
    });

    test('Mismatched total amount fails validation', () {
      final res = ExpenseValidator.validate(validExpense.copyWith(
        totalAmountPaise: 9999999, // Should be 1180000
      ));
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Total amount'));
    });

    test('Zero or negative total amount rejected when posting', () {
      final zeroExpense = Expense(
        id: 'exp-zero',
        businessId: 'biz-1',
        categoryId: 'cat-rent',
        expenseDate: DateTime.now(),
        payee: 'Payee',
        description: '',
        taxableAmountPaise: 0,
        totalGstPaise: 0,
        totalAmountPaise: 0,
        paymentAccountId: 'acc-cash',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final res = ExpenseValidator.validate(zeroExpense, isPosting: true);
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Total expense amount must be greater than zero to post'));
    });

    test('Missing payment account rejected when posting', () {
      final noAccount = validExpense.copyWith(paymentAccountId: '');
      final res = ExpenseValidator.validate(noAccount, isPosting: true);
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('A payment holding account (Cash or Bank) is required'));
    });
  });

  group('Expense Cancellation Validation Tests', () {
    final postedExpense = Expense(
      id: 'exp-posted',
      businessId: 'biz-1',
      categoryId: 'cat-utils',
      expenseDate: DateTime.now(),
      payee: 'Electricity Board',
      description: '',
      taxableAmountPaise: 50000,
      totalGstPaise: 0,
      totalAmountPaise: 50000,
      status: ExpenseStatus.posted,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    test('Valid cancellation of posted expense with reason passes', () {
      final res = ExpenseValidator.validateCancellation(
        expense: postedExpense,
        reason: 'Duplicate bill entered by admin',
      );
      expect(res.isValid, isTrue);
    });

    test('Cancelling a draft expense is rejected', () {
      final draft = postedExpense.copyWith(status: ExpenseStatus.draft);
      final res = ExpenseValidator.validateCancellation(
        expense: draft,
        reason: 'Valid reason',
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Only posted expenses can be cancelled'));
    });

    test('Cancelling without adequate reason is rejected', () {
      final res = ExpenseValidator.validateCancellation(
        expense: postedExpense,
        reason: 'no',
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('minimum 3 characters'));
    });
  });

  group('Expense Status Transition Validation Tests', () {
    test('Draft can transition to posted', () {
      final res = ExpenseValidator.validateStatusTransition(ExpenseStatus.draft, ExpenseStatus.posted);
      expect(res.isValid, isTrue);
    });

    test('Posted can transition to cancelled', () {
      final res = ExpenseValidator.validateStatusTransition(ExpenseStatus.posted, ExpenseStatus.cancelled);
      expect(res.isValid, isTrue);
    });

    test('Draft cannot transition directly to cancelled', () {
      final res = ExpenseValidator.validateStatusTransition(ExpenseStatus.draft, ExpenseStatus.cancelled);
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Illegal status transition'));
    });

    test('Cancelled cannot transition back to posted or draft', () {
      final resPosted = ExpenseValidator.validateStatusTransition(ExpenseStatus.cancelled, ExpenseStatus.posted);
      expect(resPosted.isValid, isFalse);

      final resDraft = ExpenseValidator.validateStatusTransition(ExpenseStatus.cancelled, ExpenseStatus.draft);
      expect(resDraft.isValid, isFalse);
    });
  });
}
