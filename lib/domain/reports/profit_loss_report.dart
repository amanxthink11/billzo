import 'package:billzo/core/money/money.dart';

/// Breakdown of operating expenses by category.
class ExpenseCategoryBreakdown {
  final String categoryName;
  final String accountCode;
  final int amountPaise;

  const ExpenseCategoryBreakdown({
    required this.categoryName,
    required this.accountCode,
    required this.amountPaise,
  });

  Money get amount => Money.fromPaise(amountPaise);
}

/// Offline Profit & Loss Statement derived from actual double-entry general ledger accounts.
class ProfitLossReport {
  final String businessId;
  final DateTime startDate;
  final DateTime endDate;
  final int salesRevenuePaise;
  final int otherIncomePaise;
  final int totalRevenuePaise;
  final int cogsPaise;
  final String cogsNote;
  final int grossProfitPaise;
  final List<ExpenseCategoryBreakdown> expenseBreakdown;
  final int roundOffExpensePaise;
  final int totalOperatingExpensesPaise;
  final int netProfitPaise;
  final ProfitLossReport? previousPeriodReport;
  final DateTime generatedAt;

  const ProfitLossReport({
    required this.businessId,
    required this.startDate,
    required this.endDate,
    required this.salesRevenuePaise,
    this.otherIncomePaise = 0,
    required this.totalRevenuePaise,
    required this.cogsPaise,
    required this.cogsNote,
    required this.grossProfitPaise,
    required this.expenseBreakdown,
    this.roundOffExpensePaise = 0,
    required this.totalOperatingExpensesPaise,
    required this.netProfitPaise,
    this.previousPeriodReport,
    required this.generatedAt,
  });

  Money get salesRevenue => Money.fromPaise(salesRevenuePaise);
  Money get otherIncome => Money.fromPaise(otherIncomePaise);
  Money get totalRevenue => Money.fromPaise(totalRevenuePaise);
  Money get cogs => Money.fromPaise(cogsPaise);
  Money get grossProfit => Money.fromPaise(grossProfitPaise);
  Money get roundOffExpense => Money.fromPaise(roundOffExpensePaise);
  Money get totalOperatingExpenses => Money.fromPaise(totalOperatingExpensesPaise);
  Money get netProfit => Money.fromPaise(netProfitPaise);

  bool get isProfitable => netProfitPaise >= 0;
}
