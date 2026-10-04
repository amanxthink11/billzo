import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/core/theme/app_theme.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/expense/expense_category.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/presentation/providers/expense_providers.dart';
import 'package:billzo/presentation/providers/payment_providers.dart';
import 'package:billzo/presentation/screens/expenses/expense_builder_dialog.dart';

void main() {
  final now = DateTime(2026, 4, 15, 10, 30);
  final testBiz = Business(
    id: 'biz-widget-exp-builder',
    name: 'Zenith Manufacturing',
    phone: '9876543210',
    stateCode: '27',
    stateName: 'Maharashtra',
    createdAt: now,
    updatedAt: now,
  );

  final testCategories = [
    ExpenseCategory(
      id: 'cat-rent',
      businessId: testBiz.id,
      name: 'Rent',
      accountCode: '5110',
      isPredefined: true,
      createdAt: now,
      updatedAt: now,
    ),
    ExpenseCategory(
      id: 'cat-office',
      businessId: testBiz.id,
      name: 'Office Supplies',
      accountCode: '5130',
      isPredefined: true,
      createdAt: now,
      updatedAt: now,
    ),
  ];

  final testCashAccount = CashBankAccount(
    id: 'acc-builder-cash',
    businessId: testBiz.id,
    name: 'Petty Cash',
    accountType: CashBankAccountType.cash,
    openingBalancePaise: 50000000,
    currentBalancePaise: 50000000,
    createdAt: now,
    updatedAt: now,
  );

  testWidgets('ExpenseBuilderDialog renders form fields, live tax calculation, and actions', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseCategoriesProvider.overrideWith((ref, businessId) => Future.value(testCategories)),
          cashBankAccountsProvider.overrideWith((ref, businessId) => Future.value([testCashAccount])),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: ExpenseBuilderDialog(business: testBiz),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify Dialog Header & Actions
    expect(find.text('Record Expense'), findsOneWidget);
    expect(find.text('Save Draft'), findsOneWidget);
    expect(find.text('Post Expense'), findsOneWidget);

    // 2. Verify Field Labels
    expect(find.text('Expense Category *'), findsOneWidget);
    expect(find.text('Expense Date *'), findsOneWidget);
    expect(find.text('Payee / Vendor Name *'), findsOneWidget);
    expect(find.text('Description / Purpose'), findsOneWidget);
    expect(find.text('Amount (₹) *'), findsOneWidget);
    expect(find.text('GST Slab'), findsOneWidget);
    expect(find.text('Tax Inclusive'), findsOneWidget);
    expect(find.text('Inter-state (IGST)'), findsOneWidget);

    // 3. Verify Live Tax Computation UI
    final amountFinder = find.widgetWithText(TextFormField, 'Amount (₹) *');
    expect(amountFinder, findsOneWidget);
    await tester.enterText(amountFinder, '10000.00');
    await tester.pumpAndSettle();

    // Initially 0% GST: Taxable ₹10,000.00, GST ₹0.00, Total ₹10,000.00
    expect(find.text('₹10,000.00'), findsAtLeastNWidgets(1));

    // 4. Change GST rate to 18% via slab dropdown
    final gstDropdown = find.widgetWithText(DropdownButtonFormField<int>, '0% (Exempt/Nil)');
    expect(gstDropdown, findsOneWidget);
    await tester.tap(gstDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('18% GST').last);
    await tester.pumpAndSettle();

    // Live calculation: Taxable ₹10,000.00, GST ₹1,800.00, Total ₹11,800.00
    expect(find.text('₹11,800.00'), findsOneWidget);
  });

  testWidgets('ExpenseBuilderDialog posting requires confirmation dialog', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseCategoriesProvider.overrideWith((ref, businessId) => Future.value(testCategories)),
          cashBankAccountsProvider.overrideWith((ref, businessId) => Future.value([testCashAccount])),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: ExpenseBuilderDialog(business: testBiz),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Fill required form fields
    await tester.enterText(find.widgetWithText(TextFormField, 'Payee / Vendor Name *'), 'Landlord Corp');
    await tester.enterText(find.widgetWithText(TextFormField, 'Description / Purpose'), 'Monthly office rent');
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount (₹) *'), '50000.00');
    await tester.pumpAndSettle();

    // Tap Post Expense
    final postButton = find.text('Post Expense');
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    // Verify confirmation modal before actual ledger commitment
    expect(find.text('Confirm Expense Posting'), findsOneWidget);
    expect(find.text('Confirm & Post'), findsOneWidget);
    expect(find.text('Cancel'), findsNWidgets(2));
  });
}
