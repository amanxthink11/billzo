import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/domain/expense/expense.dart';
import 'package:billzo/domain/expense/expense_category.dart';
import 'package:billzo/domain/expense/expense_repository.dart';
import 'package:billzo/domain/expense/expense_status.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/presentation/providers/database_providers.dart';

/// Search query state for expenses list.
class ExpenseSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  @override
  set state(String value) => super.state = value;
}

final expenseSearchQueryProvider =
    NotifierProvider<ExpenseSearchQueryNotifier, String>(ExpenseSearchQueryNotifier.new);

/// Selected status filter for expenses list.
class ExpenseStatusFilterNotifier extends Notifier<ExpenseStatus?> {
  @override
  ExpenseStatus? build() => null;

  @override
  set state(ExpenseStatus? value) => super.state = value;
}

final expenseStatusFilterProvider =
    NotifierProvider<ExpenseStatusFilterNotifier, ExpenseStatus?>(ExpenseStatusFilterNotifier.new);

/// Selected category ID filter for expenses list.
class ExpenseCategoryFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  @override
  set state(String? value) => super.state = value;
}

final expenseCategoryFilterProvider =
    NotifierProvider<ExpenseCategoryFilterNotifier, String?>(ExpenseCategoryFilterNotifier.new);

/// Selected payment method filter for expenses list.
class ExpensePaymentMethodFilterNotifier extends Notifier<PaymentMethod?> {
  @override
  PaymentMethod? build() => null;

  @override
  set state(PaymentMethod? value) => super.state = value;
}

final expensePaymentMethodFilterProvider =
    NotifierProvider<ExpensePaymentMethodFilterNotifier, PaymentMethod?>(ExpensePaymentMethodFilterNotifier.new);

/// Selected date range filter for expenses list.
class ExpenseDateRangeFilterNotifier extends Notifier<DateTimeRange?> {
  @override
  DateTimeRange? build() => null;

  @override
  set state(DateTimeRange? value) => super.state = value;
}

final expenseDateRangeFilterProvider =
    NotifierProvider<ExpenseDateRangeFilterNotifier, DateTimeRange?>(ExpenseDateRangeFilterNotifier.new);

/// Provider for loading the list of expenses based on current filters.
final expensesListProvider = FutureProvider.family<List<Expense>, String>((ref, businessId) async {
  final service = ref.watch(expenseServiceProvider);
  final search = ref.watch(expenseSearchQueryProvider);
  final status = ref.watch(expenseStatusFilterProvider);
  final category = ref.watch(expenseCategoryFilterProvider);
  final method = ref.watch(expensePaymentMethodFilterProvider);
  final dateRange = ref.watch(expenseDateRangeFilterProvider);

  return service.getExpenses(
    businessId: businessId,
    searchQuery: search.isEmpty ? null : search,
    status: status,
    categoryId: category,
    paymentMethod: method,
    startDate: dateRange?.start,
    endDate: dateRange != null
        ? DateTime(dateRange.end.year, dateRange.end.month, dateRange.end.day, 23, 59, 59, 999)
        : null,
    limit: 100,
  );
});

/// Provider for loading expense summary KPI metrics.
final expenseSummaryProvider = FutureProvider.family<ExpenseSummary, String>((ref, businessId) async {
  final service = ref.watch(expenseServiceProvider);
  final dateRange = ref.watch(expenseDateRangeFilterProvider);

  return service.getExpenseSummary(
    businessId,
    startDate: dateRange?.start,
    endDate: dateRange != null
        ? DateTime(dateRange.end.year, dateRange.end.month, dateRange.end.day, 23, 59, 59, 999)
        : null,
  );
});

/// Provider for loading available expense categories for a business.
final expenseCategoriesProvider = FutureProvider.family<List<ExpenseCategory>, String>((ref, businessId) async {
  final service = ref.watch(expenseServiceProvider);
  return service.getCategories(businessId);
});
