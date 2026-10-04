import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/application/reports/accounting_integrity_service.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/expense/expense.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_expense_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_payment_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_report_repository.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

class MockPathProvider implements IAppPathProvider {
  final Directory tempDir;
  MockPathProvider(this.tempDir);

  @override
  Future<String> getDatabaseDirectory() async => tempDir.path;
  @override
  Future<String> getBackupsDirectory() async => tempDir.path;
  @override
  Future<String> getMediaDirectory() async => tempDir.path;
  @override
  Future<String> getExportsDirectory() async => tempDir.path;
}

void main() {
  late Directory tempDir;
  late String dbFilePath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_persist_test_');
    dbFilePath = p.join(tempDir.path, 'persistence_test.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Reports produce identical results across database close and reopen', () async {
    const businessId = 'biz-persist-1';

    // ==========================================
    // SESSION 1: Create, Post, and Report
    // ==========================================
    final dbHelper1 = DatabaseHelper.createForTesting(
      dbPath: dbFilePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );

    final bizRepo1 = SqliteBusinessRepository(dbHelper: dbHelper1);
    final payRepo1 = SqlitePaymentRepository(dbHelper1);
    final expRepo1 = SqliteExpenseRepository(dbHelper1);
    final repRepo1 = SqliteReportRepository(dbHelper1);
    final auditService1 = AccountingIntegrityService(dbHelper1);

    await bizRepo1.createBusiness(
      Business(
        id: businessId,
        name: 'Persistence Enterprises',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    final cashAccount = await payRepo1.createCashBankAccount(
      CashBankAccount(
        id: 'acc-persist-cash',
        businessId: businessId,
        name: 'Safe Cash',
        accountType: CashBankAccountType.cash,
        openingBalancePaise: 100000000, // ₹1,000,000.00
        currentBalancePaise: 100000000,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    final categories = await expRepo1.getCategories(businessId);
    final rentCat = categories.firstWhere((c) => c.name == 'Rent');

    // Post an expense: ₹50,000 taxable + 9% CGST (₹4,500) + 9% SGST (₹4,500) = ₹59,000
    final expense = Expense(
      id: 'exp-persist-1',
      businessId: businessId,
      categoryId: rentCat.id,
      categoryName: rentCat.name,
      expenseDate: DateTime(2026, 5, 10),
      payee: 'Commercial Towers',
      description: 'May 2026 rent',
      taxableAmountPaise: 5000000,
      cgstPaise: 450000,
      sgstPaise: 450000,
      igstPaise: 0,
      totalGstPaise: 900000,
      totalAmountPaise: 5900000,
      paymentAccountId: cashAccount.id,
      paymentMethod: PaymentMethod.cash,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );

    await expRepo1.createDraft(expense);
    final postedExpense = await expRepo1.postExpense(expense.id);
    expect(postedExpense.expenseNumber, isNotNull);

    // Fetch reports in Session 1
    final tb1 = await repRepo1.getTrialBalance(businessId);
    final pl1 = await repRepo1.getProfitLoss(
      businessId,
      startDate: DateTime(2026, 5, 1),
      endDate: DateTime(2026, 5, 31, 23, 59, 59),
    );
    final bs1 = await repRepo1.getBalanceSheet(businessId, asOfDate: DateTime(2026, 5, 31));
    final gst1 = await repRepo1.getGstSummary(
      businessId,
      startDate: DateTime(2026, 5, 1),
      endDate: DateTime(2026, 5, 31, 23, 59, 59),
    );
    final audit1 = await auditService1.runIntegrityAudit(businessId);
    expect(audit1.isClean, isTrue);

    // Close Database Session 1
    await dbHelper1.close();

    // ==========================================
    // SESSION 2: Reopen and Re-verify Reports
    // ==========================================
    final dbHelper2 = DatabaseHelper.createForTesting(
      dbPath: dbFilePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );

    final repRepo2 = SqliteReportRepository(dbHelper2);
    final auditService2 = AccountingIntegrityService(dbHelper2);

    final tb2 = await repRepo2.getTrialBalance(businessId);
    final pl2 = await repRepo2.getProfitLoss(
      businessId,
      startDate: DateTime(2026, 5, 1),
      endDate: DateTime(2026, 5, 31, 23, 59, 59),
    );
    final bs2 = await repRepo2.getBalanceSheet(businessId, asOfDate: DateTime(2026, 5, 31));
    final gst2 = await repRepo2.getGstSummary(
      businessId,
      startDate: DateTime(2026, 5, 1),
      endDate: DateTime(2026, 5, 31, 23, 59, 59),
    );
    final audit2 = await auditService2.runIntegrityAudit(businessId);

    // 1. Verify Trial Balance persistence
    expect(tb2.isBalanced, isTrue);
    expect(tb2.totalDebitsPaise, equals(tb1.totalDebitsPaise));
    expect(tb2.totalCreditsPaise, equals(tb1.totalCreditsPaise));
    expect(tb2.entries.length, equals(tb1.entries.length));

    // 2. Verify Profit & Loss persistence
    expect(pl2.salesRevenuePaise, equals(pl1.salesRevenuePaise));
    expect(pl2.totalOperatingExpensesPaise, equals(pl1.totalOperatingExpensesPaise));
    expect(pl2.totalOperatingExpensesPaise, equals(5000000));
    expect(pl2.netProfitPaise, equals(pl1.netProfitPaise));
    expect(pl2.expenseBreakdown.length, equals(pl1.expenseBreakdown.length));

    // 3. Verify Balance Sheet persistence
    expect(bs2.isBalanced, isTrue);
    expect(bs2.totalAssetsPaise, equals(bs1.totalAssetsPaise));
    expect(bs2.totalLiabilitiesPaise, equals(bs1.totalLiabilitiesPaise));
    expect(bs2.totalEquityPaise, equals(bs1.totalEquityPaise));
    expect(bs2.imbalancePaise, equals(0));

    // 4. Verify GST Summary persistence
    expect(gst2.totalOutputGstPaise, equals(gst1.totalOutputGstPaise));
    expect(gst2.eligibleExpenseItc.totalTaxPaise, equals(gst1.eligibleExpenseItc.totalTaxPaise));
    expect(gst2.eligibleExpenseItc.totalTaxPaise, equals(900000));
    expect(gst2.netGstLiabilityPaise, equals(gst1.netGstLiabilityPaise));

    // 5. Verify Integrity Audit persistence
    expect(audit2.isClean, isTrue);
    expect(audit2.totalIssuesCount, equals(0));

    await dbHelper2.close();
  });
}
