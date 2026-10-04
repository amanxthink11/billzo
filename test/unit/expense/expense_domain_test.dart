import 'package:flutter_test/flutter_test.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/domain/expense/expense.dart';
import 'package:billzo/domain/expense/expense_category.dart';
import 'package:billzo/domain/expense/expense_status.dart';
import 'package:billzo/domain/payment/payment_method.dart';

void main() {
  group('Expense Category Tests', () {
    test('Standard predefined categories contain 12 standard categories with correct accounts', () {
      final categories = ExpenseCategory.standardCategories;
      expect(categories.length, equals(12));

      final names = categories.map((c) => c.name).toList();
      expect(names, containsAll([
        'Rent',
        'Utilities',
        'Salaries/Wages',
        'Office Supplies',
        'Internet/Telephone',
        'Travel',
        'Advertising/Marketing',
        'Repairs & Maintenance',
        'Professional Fees',
        'Bank Charges',
        'Insurance',
        'Miscellaneous',
      ]));

      // Verify account codes are in 5100..5199 range
      for (final cat in categories) {
        expect(cat.accountCode, startsWith('51'));
      }
    });

    test('Custom category creation supports custom ledger account mapping', () {
      final customCat = ExpenseCategory(
        id: 'cat-custom-1',
        businessId: 'biz-101',
        name: 'Staff Welfare & Refreshments',
        accountCode: '5195',
        isPredefined: false,
        createdAt: DateTime(2026, 3, 1),
        updatedAt: DateTime(2026, 3, 1),
      );

      expect(customCat.isPredefined, isFalse);
      expect(customCat.accountCode, equals('5195'));

      final map = customCat.toMap();
      expect(map['name'], equals('Staff Welfare & Refreshments'));
      expect(map['is_predefined'], equals(0));

      final restored = ExpenseCategory.fromMap(map);
      expect(restored.id, equals(customCat.id));
      expect(restored.name, equals(customCat.name));
      expect(restored.isPredefined, isFalse);
    });
  });

  group('Expense Aggregate Domain Tests', () {
    final baseExpense = Expense(
      id: 'exp-1',
      businessId: 'biz-101',
      categoryId: 'cat-rent',
      categoryName: 'Rent',
      expenseDate: DateTime(2026, 3, 15),
      payee: 'Prime Commercial Towers Ltd',
      description: 'Office rent for March 2026',
      taxableAmountPaise: 5000000, // ₹50,000.00
      cgstPaise: 450000,          // ₹4,500.00 (9%)
      sgstPaise: 450000,          // ₹4,500.00 (9%)
      igstPaise: 0,
      totalGstPaise: 900000,      // ₹9,000.00
      totalAmountPaise: 5900000,  // ₹59,000.00
      paymentAccountId: 'acc-bank-1',
      paymentMethod: PaymentMethod.bankTransfer,
      referenceNumber: 'NEFT-12345678',
      notes: 'Paid via corporate bank account',
      createdAt: DateTime(2026, 3, 15, 10, 0),
      updatedAt: DateTime(2026, 3, 15, 10, 0),
    );

    test('Financial properties return accurate Money instances without floating-point errors', () {
      expect(baseExpense.taxableAmount, equals(const Money(5000000)));
      expect(baseExpense.cgst, equals(const Money(450000)));
      expect(baseExpense.sgst, equals(const Money(450000)));
      expect(baseExpense.igst, equals(Money.zero));
      expect(baseExpense.totalGst, equals(const Money(900000)));
      expect(baseExpense.totalAmount, equals(const Money(5900000)));

      expect(baseExpense.totalAmount.formatted, equals('₹59,000.00'));
      expect(baseExpense.totalGst.formatted, equals('₹9,000.00'));
    });

    test('Draft expense initial state and permissions', () {
      expect(baseExpense.status, equals(ExpenseStatus.draft));
      expect(baseExpense.isDraft, isTrue);
      expect(baseExpense.isPosted, isFalse);
      expect(baseExpense.isCancelled, isFalse);
      expect(baseExpense.canEdit, isTrue);
      expect(baseExpense.canPost, isTrue);
      expect(baseExpense.canCancel, isFalse);
      expect(baseExpense.expenseNumber, isNull);
    });

    test('Posted expense state and immutability permissions', () {
      final posted = baseExpense.copyWith(
        status: ExpenseStatus.posted,
        expenseNumber: 'EXP-2026-0001',
        postedAt: DateTime(2026, 3, 15, 10, 30),
      );

      expect(posted.isDraft, isFalse);
      expect(posted.isPosted, isTrue);
      expect(posted.isCancelled, isFalse);
      expect(posted.canEdit, isFalse); // Posted expenses are immutable!
      expect(posted.canPost, isFalse);
      expect(posted.canCancel, isTrue);
      expect(posted.expenseNumber, equals('EXP-2026-0001'));
      expect(posted.postedAt, isNotNull);
    });

    test('Cancelled expense state and cancellation metadata', () {
      final cancelled = baseExpense.copyWith(
        status: ExpenseStatus.cancelled,
        expenseNumber: 'EXP-2026-0001',
        postedAt: DateTime(2026, 3, 15, 10, 30),
        cancelledAt: DateTime(2026, 3, 16, 9, 0),
        cancellationReason: 'Duplicate entry recorded by error',
      );

      expect(cancelled.isDraft, isFalse);
      expect(cancelled.isPosted, isFalse);
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.canEdit, isFalse);
      expect(cancelled.canPost, isFalse);
      expect(cancelled.canCancel, isFalse);
      expect(cancelled.cancellationReason, equals('Duplicate entry recorded by error'));
    });

    test('Inter-state and tax inclusive helper getters', () {
      expect(baseExpense.isInterState, isFalse);

      final interstateExp = baseExpense.copyWith(
        cgstPaise: 0,
        sgstPaise: 0,
        igstPaise: 900000,
      );
      expect(interstateExp.isInterState, isTrue);
    });

    test('Serialization toMap and deserialization fromMap roundtrips accurately', () {
      final postedExpense = baseExpense.copyWith(
        status: ExpenseStatus.posted,
        expenseNumber: 'EXP-2026-0042',
        postedAt: DateTime(2026, 3, 15, 12, 0),
      );

      final map = postedExpense.toMap();
      expect(map['id'], equals('exp-1'));
      expect(map['business_id'], equals('biz-101'));
      expect(map['expense_number'], equals('EXP-2026-0042'));
      expect(map['status'], equals('POSTED'));
      expect(map['taxable_amount_paise'], equals(5000000));
      expect(map['total_amount_paise'], equals(5900000));
      expect(map['cgst_paise'], equals(450000));
      expect(map['sgst_paise'], equals(450000));
      expect(map['igst_paise'], equals(0));
      expect(map['payment_method'], equals('BANK_TRANSFER'));

      final reconstructed = Expense.fromMap(map);
      expect(reconstructed.id, equals(postedExpense.id));
      expect(reconstructed.expenseNumber, equals(postedExpense.expenseNumber));
      expect(reconstructed.status, equals(ExpenseStatus.posted));
      expect(reconstructed.totalAmountPaise, equals(postedExpense.totalAmountPaise));
      expect(reconstructed.payee, equals(postedExpense.payee));
      expect(reconstructed.categoryName, equals('Rent'));
    });
  });
}
