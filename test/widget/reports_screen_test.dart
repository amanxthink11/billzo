import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/application/reports/accounting_integrity_service.dart';
import 'package:billzo/core/theme/app_theme.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/reports/aging_analysis_report.dart';
import 'package:billzo/domain/reports/balance_sheet_report.dart';
import 'package:billzo/domain/reports/gst_summary_report.dart';
import 'package:billzo/domain/reports/gstr1_report.dart';
import 'package:billzo/domain/reports/profit_loss_report.dart';
import 'package:billzo/domain/reports/stock_valuation_report.dart';
import 'package:billzo/domain/reports/trial_balance_report.dart';
import 'package:billzo/presentation/providers/report_providers.dart';
import 'package:billzo/presentation/screens/reports/reports_screen.dart';

void main() {
  final now = DateTime(2026, 4, 30, 23, 59, 59);
  final startOfMonth = DateTime(2026, 4, 1, 0, 0, 0);

  final testBiz = Business(
    id: 'biz-widget-reports',
    name: 'Zenith Apex Corp',
    phone: '9876543210',
    stateCode: '27',
    stateName: 'Maharashtra',
    createdAt: now,
    updatedAt: now,
  );

  final mockTrialBalance = TrialBalanceReport(
    businessId: testBiz.id,
    startDate: startOfMonth,
    asOfDate: now,
    entries: const [
      TrialBalanceEntry(
        accountId: 'acc-cash',
        accountCode: '1000',
        accountName: 'Cash on Hand',
        accountType: 'ASSET',
        totalDebitPaise: 5000000,
        totalCreditPaise: 1000000,
        netDebitPaise: 4000000,
        netCreditPaise: 0,
      ),
      TrialBalanceEntry(
        accountId: 'acc-ar',
        accountCode: '1100',
        accountName: 'Accounts Receivable',
        accountType: 'ASSET',
        totalDebitPaise: 3000000,
        totalCreditPaise: 1000000,
        netDebitPaise: 2000000,
        netCreditPaise: 0,
      ),
      TrialBalanceEntry(
        accountId: 'acc-sales',
        accountCode: '4000',
        accountName: 'Sales Revenue',
        accountType: 'INCOME',
        totalDebitPaise: 0,
        totalCreditPaise: 6000000,
        netDebitPaise: 0,
        netCreditPaise: 6000000,
      ),
    ],
    totalDebitsPaise: 8000000,
    totalCreditsPaise: 8000000,
    generatedAt: now,
  );

  final mockProfitLoss = ProfitLossReport(
    businessId: testBiz.id,
    startDate: startOfMonth,
    endDate: now,
    salesRevenuePaise: 6000000,
    totalRevenuePaise: 6000000,
    cogsPaise: 0,
    cogsNote: 'Perpetual inventory method deferred in Asset Account 1200.',
    grossProfitPaise: 6000000,
    expenseBreakdown: const [
      ExpenseCategoryBreakdown(
        categoryName: 'Office Rent',
        accountCode: '5110',
        amountPaise: 1500000,
      ),
      ExpenseCategoryBreakdown(
        categoryName: 'Electricity & Utilities',
        accountCode: '5120',
        amountPaise: 500000,
      ),
    ],
    roundOffExpensePaise: 0,
    totalOperatingExpensesPaise: 2000000,
    netProfitPaise: 4000000,
    generatedAt: now,
  );

  final mockBalanceSheet = BalanceSheetReport(
    businessId: testBiz.id,
    asOfDate: now,
    assetItems: const [
      BalanceSheetItem(accountCode: '1000', accountName: 'Cash on Hand', amountPaise: 4000000),
      BalanceSheetItem(accountCode: '1100', accountName: 'Accounts Receivable', amountPaise: 2000000),
    ],
    totalAssetsPaise: 6000000,
    liabilityItems: const [
      BalanceSheetItem(accountCode: '2100', accountName: 'Accounts Payable', amountPaise: 2000000),
    ],
    totalLiabilitiesPaise: 2000000,
    equityItems: const [],
    currentPeriodEarningsPaise: 4000000,
    totalEquityPaise: 4000000,
    generatedAt: now,
  );

  final mockGstSummary = GstSummaryReport(
    businessId: testBiz.id,
    startDate: startOfMonth,
    endDate: now,
    outwardSupply: const GstTaxBucket(
      taxableAmountPaise: 6000000,
      cgstPaise: 540000,
      sgstPaise: 540000,
      igstPaise: 0,
    ),
    eligiblePurchaseItc: const GstTaxBucket(
      taxableAmountPaise: 2000000,
      cgstPaise: 180000,
      sgstPaise: 180000,
      igstPaise: 0,
    ),
    ineligiblePurchaseItcPaise: 0,
    eligibleExpenseItc: const GstTaxBucket(
      taxableAmountPaise: 2000000,
      cgstPaise: 180000,
      sgstPaise: 180000,
      igstPaise: 0,
    ),
    generatedAt: now,
  );

  final mockAudit = AccountingIntegrityReport(
    businessId: testBiz.id,
    journalEntriesBalanced: true,
    trialBalanceBalanced: true,
    cashBankReconciled: true,
    receivablesReconciled: true,
    payablesReconciled: true,
    expensesReconciled: true,
    issues: const [],
    auditedAt: now,
  );

  final mockGstr1 = Gstr1Report(
    businessId: testBiz.id,
    startDate: startOfMonth,
    endDate: now,
    b2bInvoices: const [],
    b2clInvoices: const [],
    b2csItems: const [],
    hsnSummary: const [],
    generatedAt: now,
  );

  final mockReceivablesAging = ReceivablesAgingReport(
    businessId: testBiz.id,
    asOfDate: now,
    items: const [],
    generatedAt: now,
  );

  final mockPayablesAging = PayablesAgingReport(
    businessId: testBiz.id,
    asOfDate: now,
    items: const [],
    generatedAt: now,
  );

  final mockStockValuation = StockValuationReport(
    businessId: testBiz.id,
    asOfDate: now,
    items: const [],
    generatedAt: now,
  );

  Widget createSubject() {
    return ProviderScope(
      overrides: [
        trialBalanceReportProvider(testBiz.id).overrideWith((ref) => mockTrialBalance),
        profitLossReportProvider(testBiz.id).overrideWith((ref) => mockProfitLoss),
        balanceSheetReportProvider(testBiz.id).overrideWith((ref) => mockBalanceSheet),
        gstSummaryReportProvider(testBiz.id).overrideWith((ref) => mockGstSummary),
        accountingIntegrityAuditProvider(testBiz.id).overrideWith((ref) => mockAudit),
        gstr1ReportProvider(testBiz.id).overrideWith((ref) => mockGstr1),
        receivablesAgingReportProvider(testBiz.id).overrideWith((ref) => mockReceivablesAging),
        payablesAgingReportProvider(testBiz.id).overrideWith((ref) => mockPayablesAging),
        stockValuationReportProvider(testBiz.id).overrideWith((ref) => mockStockValuation),
      ],
      child: MaterialApp(
        theme: BillzoTheme.lightTheme,
        home: Scaffold(
          body: ReportsScreen(business: testBiz),
        ),
      ),
    );
  }

  testWidgets('ReportsScreen renders overview, metrics, and tab navigation', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    // 1. Header & Controls
    expect(find.text('Financial Reports & Accounting'), findsOneWidget);
    expect(find.text('Integrity Audit'), findsOneWidget);
    expect(find.byType(DropdownButton<ReportDatePreset>), findsOneWidget);

    // 2. Tabs
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Profit & Loss'), findsOneWidget);
    expect(find.text('Balance Sheet'), findsOneWidget);
    expect(find.text('Trial Balance'), findsOneWidget);
    expect(find.text('GST Summary'), findsOneWidget);
    expect(find.text('GSTR-1 Portal'), findsOneWidget);
    expect(find.text('Receivables Aging'), findsOneWidget);
    expect(find.text('Payables Aging'), findsOneWidget);
    expect(find.text('Stock Valuation'), findsOneWidget);
    expect(find.text('Expense Breakdown'), findsOneWidget);

    // 3. Overview Tab Content
    expect(find.text('Sales Revenue'), findsOneWidget);
    expect(find.text('Gross Profit'), findsOneWidget);
    expect(find.textContaining('Accounting ledger is in perfect equilibrium'), findsOneWidget);
  });

  testWidgets('ReportsScreen switches to Profit & Loss tab and displays ledger-derived financials', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    // Tap Profit & Loss tab
    await tester.tap(find.text('Profit & Loss'));
    await tester.pumpAndSettle();

    expect(find.text('Statement of Profit & Loss'), findsOneWidget);
    expect(find.text('Operating Revenue'), findsOneWidget);
    expect(find.text('Sales Revenue (Taxable Turnover)'), findsOneWidget);
    expect(find.text('Cost of Goods Sold (COGS)'), findsOneWidget);
    expect(find.text('Gross Profit [A - B]'), findsOneWidget);
    expect(find.text('Operating & Indirect Expenses'), findsOneWidget);
    expect(find.text('Office Rent (5110)'), findsOneWidget);
    expect(find.text('Electricity & Utilities (5120)'), findsOneWidget);
    expect(find.textContaining('NET PROFIT FOR THE PERIOD'), findsOneWidget);
  });

  testWidgets('ReportsScreen switches to Balance Sheet tab and displays accounting equation', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    // Tap Balance Sheet tab
    await tester.tap(find.text('Balance Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Statement of Financial Position (Balance Sheet)'), findsOneWidget);
    expect(find.textContaining('Fundamental Accounting Equation Balances'), findsOneWidget);
    expect(find.text('ASSETS'), findsOneWidget);
    expect(find.text('LIABILITIES'), findsOneWidget);
    expect(find.text('EQUITY'), findsOneWidget);
    expect(find.text('Current Period Net Earnings'), findsOneWidget);
    expect(find.text('TOTAL LIABILITIES & EQUITY'), findsOneWidget);
  });

  testWidgets('ReportsScreen switches to Trial Balance tab and shows balanced badge', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    // Tap Trial Balance tab
    await tester.tap(find.text('Trial Balance'));
    await tester.pumpAndSettle();

    expect(find.text('General Ledger Trial Balance'), findsOneWidget);
    expect(find.text('BALANCED'), findsOneWidget);
    expect(find.text('Cash on Hand'), findsOneWidget);
    expect(find.text('Accounts Receivable'), findsOneWidget);
    expect(find.text('Sales Revenue'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget);
  });

  testWidgets('ReportsScreen switches to GST Summary tab and shows buckets with statutory disclaimer', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    // Tap GST Summary tab
    await tester.tap(find.text('GST Summary'));
    await tester.pumpAndSettle();

    expect(find.text(GstSummaryReport.reportTitle), findsOneWidget);
    expect(find.text(GstSummaryReport.disclaimer), findsOneWidget);
    expect(find.text('1. OUTWARD SUPPLY TAX (Sales Invoices)'), findsOneWidget);
    expect(find.text('2. INPUT TAX CREDIT — PURCHASES (Eligible Supplier Invoices)'), findsOneWidget);
    expect(find.text('3. INPUT TAX CREDIT — EXPENSES (Operational Expenses)'), findsOneWidget);
    expect(find.text('NET STATUTORY RECONCILIATION SUMMARY'), findsOneWidget);
  });

  testWidgets('ReportsScreen opens Accounting Integrity Audit dialog and verifies 6 verification checks', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    // Tap Integrity Audit button
    await tester.tap(find.text('Integrity Audit'));
    await tester.pumpAndSettle();

    expect(find.text('Accounting Integrity Audit'), findsOneWidget);
    expect(find.textContaining('Double-entry accounting integrity verified!'), findsOneWidget);
    expect(find.text('1. Balanced Journal Entries'), findsOneWidget);
    expect(find.text('2. Trial Balance Debits == Credits'), findsOneWidget);
    expect(find.text('3. Cash/Bank Postings Reconciliation'), findsOneWidget);
    expect(find.text('4. Customer Receivables vs Account 1100'), findsOneWidget);
    expect(find.text('5. Supplier Payables vs Account 2100'), findsOneWidget);
    expect(find.text('6. Operational Expenses vs Ledger'), findsOneWidget);
    expect(find.text('PASSED'), findsNWidgets(6));

    // Close Dialog
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Accounting Integrity Audit'), findsNothing);
  });
}
