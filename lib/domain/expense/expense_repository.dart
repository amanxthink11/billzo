import 'package:billzo/domain/expense/expense.dart';
import 'package:billzo/domain/expense/expense_category.dart';
import 'package:billzo/domain/expense/expense_status.dart';
import 'package:billzo/domain/payment/payment_method.dart';

/// Summary metrics for expenses within a specific period.
class ExpenseSummary {
  final int totalExpensesCount;
  final int totalAmountPaise;
  final int totalTaxablePaise;
  final int totalGstPaise;
  final int cashExpensesPaise;
  final int bankExpensesPaise;
  final int todayExpensesPaise;
  final int thisMonthExpensesPaise;

  const ExpenseSummary({
    this.totalExpensesCount = 0,
    this.totalAmountPaise = 0,
    this.totalTaxablePaise = 0,
    this.totalGstPaise = 0,
    this.cashExpensesPaise = 0,
    this.bankExpensesPaise = 0,
    this.todayExpensesPaise = 0,
    this.thisMonthExpensesPaise = 0,
  });
}

/// Abstract contract for Expense repository operations.
abstract class IExpenseRepository {
  /// Saves a new expense in DRAFT state. Does not consume sequence or post ledger entries.
  Future<Expense> createDraft(Expense expense);

  /// Updates an existing DRAFT expense. Throws if expense is already POSTED or CANCELLED.
  Future<Expense> updateDraft(Expense expense);

  /// Permanently deletes an unposted DRAFT expense.
  Future<void> deleteDraft(String expenseId);

  /// Atomically posts a DRAFT expense:
  /// 1. Allocates sequence number (EXP-YYYY-####)
  /// 2. Sets status to POSTED
  /// 3. Debits expense account, debits input GST (if taxable), credits cash/bank account in ledger_entries
  /// 4. Deducts cash_bank_accounts current balance
  /// 5. Records audit log
  /// Rolls back 100% on failure without consuming sequence.
  Future<Expense> postExpense(String expenseId, {String? paymentAccountId});

  /// Atomically cancels a POSTED expense:
  /// 1. Sets status to CANCELLED with cancellation reason and timestamp
  /// 2. Posts reversing accounting entries in ledger_entries
  /// 3. Restores cash_bank_accounts current balance
  /// 4. Records audit log
  /// Rolls back 100% on failure.
  Future<Expense> cancelExpense(String expenseId, {required String reason});

  /// Retrieves an expense by its ID.
  Future<Expense?> getExpenseById(String expenseId);

  /// Queries expenses matching filters with pagination.
  Future<List<Expense>> getExpenses({
    required String businessId,
    String? categoryId,
    ExpenseStatus? status,
    PaymentMethod? paymentMethod,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    int limit = 50,
    int offset = 0,
  });

  /// Counts expenses matching filters.
  Future<int> getExpensesCount({
    required String businessId,
    String? categoryId,
    ExpenseStatus? status,
    PaymentMethod? paymentMethod,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  });

  /// Retrieves dashboard summary metrics for expenses.
  Future<ExpenseSummary> getExpenseSummary(
    String businessId, {
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Retrieves all categories for a business (predefined and custom).
  Future<List<ExpenseCategory>> getCategories(
    String businessId, {
    bool includeInactive = false,
  });

  /// Creates a custom expense category.
  Future<ExpenseCategory> createCategory(ExpenseCategory category);

  /// Updates an expense category.
  Future<ExpenseCategory> updateCategory(ExpenseCategory category);

  /// Ensures that standard predefined categories exist for the business.
  Future<void> ensurePredefinedCategories(String businessId);
}
