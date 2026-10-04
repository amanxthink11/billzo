import 'package:billzo/domain/expense/expense.dart';
import 'package:billzo/domain/expense/expense_category.dart';
import 'package:billzo/domain/expense/expense_repository.dart';
import 'package:billzo/domain/expense/expense_status.dart';
import 'package:billzo/domain/invoice/tax_engine.dart';
import 'package:billzo/domain/payment/payment_method.dart';

/// Calculation result for live tax estimation in the expense entry form.
class ExpenseTaxCalculation {
  final int taxableAmountPaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int totalTaxPaise;
  final int totalAmountPaise;

  const ExpenseTaxCalculation({
    required this.taxableAmountPaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.totalTaxPaise,
    required this.totalAmountPaise,
  });
}

/// Application service orchestrating Expense workflows, validations, and tax calculations.
class ExpenseService {
  final IExpenseRepository _expenseRepository;

  ExpenseService(this._expenseRepository);

  Future<Expense> createDraft(Expense expense) => _expenseRepository.createDraft(expense);

  Future<Expense> updateDraft(Expense expense) => _expenseRepository.updateDraft(expense);

  Future<void> deleteDraft(String expenseId) => _expenseRepository.deleteDraft(expenseId);

  Future<Expense> postExpense(String expenseId, {String? paymentAccountId}) =>
      _expenseRepository.postExpense(expenseId, paymentAccountId: paymentAccountId);

  Future<Expense> cancelExpense(String expenseId, {required String reason}) =>
      _expenseRepository.cancelExpense(expenseId, reason: reason);

  Future<Expense?> getExpenseById(String expenseId) => _expenseRepository.getExpenseById(expenseId);

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
  }) =>
      _expenseRepository.getExpenses(
        businessId: businessId,
        categoryId: categoryId,
        status: status,
        paymentMethod: paymentMethod,
        startDate: startDate,
        endDate: endDate,
        searchQuery: searchQuery,
        limit: limit,
        offset: offset,
      );

  Future<int> getExpensesCount({
    required String businessId,
    String? categoryId,
    ExpenseStatus? status,
    PaymentMethod? paymentMethod,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) =>
      _expenseRepository.getExpensesCount(
        businessId: businessId,
        categoryId: categoryId,
        status: status,
        paymentMethod: paymentMethod,
        startDate: startDate,
        endDate: endDate,
        searchQuery: searchQuery,
      );

  Future<ExpenseSummary> getExpenseSummary(
    String businessId, {
    DateTime? startDate,
    DateTime? endDate,
  }) =>
      _expenseRepository.getExpenseSummary(
        businessId,
        startDate: startDate,
        endDate: endDate,
      );

  Future<List<ExpenseCategory>> getCategories(
    String businessId, {
    bool includeInactive = false,
  }) =>
      _expenseRepository.getCategories(businessId, includeInactive: includeInactive);

  Future<ExpenseCategory> createCategory(ExpenseCategory category) =>
      _expenseRepository.createCategory(category);

  Future<ExpenseCategory> updateCategory(ExpenseCategory category) =>
      _expenseRepository.updateCategory(category);

  Future<void> ensurePredefinedCategories(String businessId) =>
      _expenseRepository.ensurePredefinedCategories(businessId);

  /// Computes tax split and taxable amount using the statutory TaxEngine.
  ExpenseTaxCalculation calculateExpenseTax({
    required int amountPaise,
    required int taxRateBasisPoints,
    required bool isTaxInclusive,
    required bool isInterState,
  }) {
    if (amountPaise <= 0 || taxRateBasisPoints <= 0) {
      return ExpenseTaxCalculation(
        taxableAmountPaise: amountPaise,
        cgstPaise: 0,
        sgstPaise: 0,
        igstPaise: 0,
        totalTaxPaise: 0,
        totalAmountPaise: amountPaise,
      );
    }

    final breakdown = TaxEngine.calculateLineItemTax(
      ratePaise: amountPaise,
      quantityScaled: 1000,
      discountPaise: 0,
      taxRateBasisPoints: taxRateBasisPoints,
      isInterState: isInterState,
      isTaxInclusive: isTaxInclusive,
    );

    return ExpenseTaxCalculation(
      taxableAmountPaise: breakdown.taxableAmountPaise,
      cgstPaise: breakdown.cgstPaise,
      sgstPaise: breakdown.sgstPaise,
      igstPaise: breakdown.igstPaise,
      totalTaxPaise: breakdown.totalTaxPaise,
      totalAmountPaise: breakdown.lineTotalPaise,
    );
  }
}
