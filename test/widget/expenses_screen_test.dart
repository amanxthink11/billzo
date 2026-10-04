import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/core/theme/app_theme.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/expense/expense.dart';
import 'package:billzo/domain/expense/expense_category.dart';
import 'package:billzo/domain/expense/expense_repository.dart';
import 'package:billzo/domain/expense/expense_status.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/expense_providers.dart';
import 'package:billzo/presentation/providers/payment_providers.dart';
import 'package:billzo/presentation/screens/expenses/expenses_screen.dart';

class MockActiveBusinessNotifier extends ActiveBusinessNotifier {
  final Business _biz;
  MockActiveBusinessNotifier(this._biz);

  @override
  Future<Business?> build() async => _biz;
}

void main() {
  final now = DateTime(2026, 4, 15, 10, 30);
  final testBiz = Business(
    id: 'biz-widget-expenses',
    name: 'Zenith Manufacturing',
    phone: '9876543210',
    stateCode: '27',
    stateName: 'Maharashtra',
    createdAt: now,
    updatedAt: now,
  );

  final testCategories = [
    ExpenseCategory(
      id: 'cat-w-rent',
      businessId: testBiz.id,
      name: 'Rent',
      accountCode: '5110',
      isPredefined: true,
      createdAt: now,
      updatedAt: now,
    ),
    ExpenseCategory(
      id: 'cat-w-utils',
      businessId: testBiz.id,
      name: 'Utilities',
      accountCode: '5120',
      isPredefined: true,
      createdAt: now,
      updatedAt: now,
    ),
  ];

  final testCashAccount = CashBankAccount(
    id: 'acc-w-cash',
    businessId: testBiz.id,
    name: 'Main Cash',
    accountType: CashBankAccountType.cash,
    openingBalancePaise: 50000000,
    currentBalancePaise: 50000000,
    createdAt: now,
    updatedAt: now,
  );

  final testExpenses = [
    Expense(
      id: 'exp-w-1',
      businessId: testBiz.id,
      expenseNumber: 'EXP-2026-0001',
      categoryId: 'cat-w-rent',
      categoryName: 'Rent',
      expenseDate: now,
      payee: 'Apex Realtors',
      description: 'Factory shed monthly lease',
      taxableAmountPaise: 4000000, // ₹40,000.00
      cgstPaise: 360000,          // ₹3,600.00
      sgstPaise: 360000,          // ₹3,600.00
      igstPaise: 0,
      totalGstPaise: 720000,       // ₹7,200.00
      totalAmountPaise: 4720000,   // ₹47,200.00
      paymentAccountId: 'acc-w-cash',
      paymentAccountName: 'Main Cash',
      paymentMethod: PaymentMethod.cash,
      status: ExpenseStatus.posted,
      postedAt: now,
      createdAt: now,
      updatedAt: now,
    ),
    Expense(
      id: 'exp-w-2',
      businessId: testBiz.id,
      expenseNumber: null,
      categoryId: 'cat-w-utils',
      categoryName: 'Utilities',
      expenseDate: now,
      payee: 'Power Grid Corp',
      description: 'Pending electric bill review',
      taxableAmountPaise: 1500000, // ₹15,000.00
      cgstPaise: 0,
      sgstPaise: 0,
      igstPaise: 0,
      totalGstPaise: 0,
      totalAmountPaise: 1500000,   // ₹15,000.00
      paymentAccountId: 'acc-w-cash',
      paymentAccountName: 'Main Cash',
      paymentMethod: PaymentMethod.cash,
      status: ExpenseStatus.draft,
      createdAt: now,
      updatedAt: now,
    ),
  ];

  final testSummary = const ExpenseSummary(
    todayExpensesPaise: 4720000,
    thisMonthExpensesPaise: 4720000,
    totalAmountPaise: 4720000,
    cashExpensesPaise: 4720000,
    bankExpensesPaise: 0,
    totalGstPaise: 720000,
    totalExpensesCount: 2,
  );

  testWidgets('ExpensesScreen renders desktop dashboard, KPIs, search, and expense records table', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(() => MockActiveBusinessNotifier(testBiz)),
          expensesListProvider.overrideWith((ref, businessId) => Future.value(testExpenses)),
          expenseSummaryProvider.overrideWith((ref, businessId) => Future.value(testSummary)),
          expenseCategoriesProvider.overrideWith((ref, businessId) => Future.value(testCategories)),
          cashBankAccountsProvider.overrideWith((ref, businessId) => Future.value([testCashAccount])),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: ExpensesScreen(business: testBiz),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Action button
    expect(find.text('Operational Expenses'), findsOneWidget);
    expect(find.text('Record Expense'), findsOneWidget);

    // Verify KPI metric cards
    expect(find.text("Today's Expenses"), findsOneWidget);
    expect(find.text("This Month"), findsOneWidget);
    expect(find.text('Total Expenses'), findsOneWidget);
    expect(find.text('Cash Outflow'), findsOneWidget);
    expect(find.text('Bank Outflow'), findsOneWidget);
    expect(find.text('Input GST Credit'), findsOneWidget);

    // Verify Search hint
    expect(find.text('Search by payee, description, or EXP number...'), findsOneWidget);

    // Verify table records
    expect(find.text('EXP-2026-0001'), findsOneWidget);
    expect(find.text('Apex Realtors'), findsOneWidget);
    expect(find.text('Rent'), findsAtLeastNWidgets(1));
    expect(find.text('Posted'), findsOneWidget);

    expect(find.text('Power Grid Corp'), findsOneWidget);
    expect(find.text('Utilities'), findsAtLeastNWidgets(1));
    expect(find.text('Draft'), findsOneWidget);
  });
}
