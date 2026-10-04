import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
  late DatabaseHelper dbHelper;
  late SqliteBusinessRepository businessRepo;
  late SqlitePaymentRepository paymentRepo;
  late SqliteExpenseRepository expenseRepo;
  late SqliteReportRepository reportRepo;

  late Business testBusiness;
  late CashBankAccount cashAccount;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_pl_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );

    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    paymentRepo = SqlitePaymentRepository(dbHelper);
    expenseRepo = SqliteExpenseRepository(dbHelper);
    reportRepo = SqliteReportRepository(dbHelper);

    testBusiness = await businessRepo.createBusiness(
      Business(
        id: 'biz-pl',
        name: 'Profit Dynamics Ltd',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    cashAccount = await paymentRepo.createCashBankAccount(
      CashBankAccount(
        id: 'acc-pl-cash',
        businessId: testBusiness.id,
        name: 'Main Cash',
        accountType: CashBankAccountType.cash,
        openingBalancePaise: 10000000,
        currentBalancePaise: 10000000,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Profit & Loss Statement Tests', () {
    test('Empty period reports zero revenue, expenses, and net profit', () async {
      final pl = await reportRepo.getProfitLoss(
        testBusiness.id,
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 31, 23, 59, 59),
      );

      expect(pl.salesRevenuePaise, equals(0));
      expect(pl.totalOperatingExpensesPaise, equals(0));
      expect(pl.grossProfitPaise, equals(0));
      expect(pl.netProfitPaise, equals(0));
      expect(pl.isProfitable, isTrue); // Zero net profit
      expect(pl.expenseBreakdown, isEmpty);
      expect(pl.cogsNote, contains('Perpetual COGS tracking deferred'));
    });

    test('P&L reflects operating sales turnover, category-wise expenses, and net surplus/loss', () async {
      final db = await dbHelper.database;
      final nowStr = DateTime(2026, 3, 15).toIso8601String();

      // Seed sales revenue in account 4000 directly via ledger entries
      final salesAccountId = 'acc-sales-4000';
      await db.insert('ledger_accounts', {
        'id': salesAccountId,
        'business_id': testBusiness.id,
        'code': '4000',
        'name': 'Sales Revenue',
        'account_type': 'INCOME',
        'is_system_account': 1,
        'created_at': nowStr,
        'updated_at': nowStr,
      });

      // Credit 4000 with ₹100,000.00
      await db.insert('ledger_entries', {
        'id': 'le-sales-1',
        'business_id': testBusiness.id,
        'account_id': salesAccountId,
        'transaction_id': 'inv-101',
        'transaction_type': 'INVOICE',
        'entry_date': nowStr,
        'debit_paise': 0,
        'credit_paise': 10000000, // ₹100,000.00
        'description': 'Taxable sales revenue',
        'created_at': nowStr,
      });

      // Post expenses via ExpenseRepository
      final categories = await expenseRepo.getCategories(testBusiness.id);
      final rentCat = categories.firstWhere((c) => c.name == 'Rent');
      final travelCat = categories.firstWhere((c) => c.name == 'Travel');

      // Rent: ₹30,000
      final exp1 = Expense(
        id: 'exp-pl-rent',
        businessId: testBusiness.id,
        categoryId: rentCat.id,
        categoryName: rentCat.name,
        expenseDate: DateTime(2026, 3, 16),
        payee: 'Office Landlord',
        description: 'Office Rent',
        taxableAmountPaise: 3000000,
        totalGstPaise: 0,
        totalAmountPaise: 3000000,
        paymentAccountId: cashAccount.id,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await expenseRepo.createDraft(exp1);
      await expenseRepo.postExpense(exp1.id);

      // Travel: ₹10,000
      final exp2 = Expense(
        id: 'exp-pl-travel',
        businessId: testBusiness.id,
        categoryId: travelCat.id,
        categoryName: travelCat.name,
        expenseDate: DateTime(2026, 3, 18),
        payee: 'Airline Services',
        description: 'Client visit flight',
        taxableAmountPaise: 1000000,
        totalGstPaise: 0,
        totalAmountPaise: 1000000,
        paymentAccountId: cashAccount.id,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await expenseRepo.createDraft(exp2);
      await expenseRepo.postExpense(exp2.id);

      // Generate P&L for March 2026
      final pl = await reportRepo.getProfitLoss(
        testBusiness.id,
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 31, 23, 59, 59),
      );

      // Verify Revenue
      expect(pl.salesRevenuePaise, equals(10000000)); // ₹100,000.00
      expect(pl.totalRevenuePaise, equals(10000000));

      // Verify Operating Expenses Breakdown
      expect(pl.expenseBreakdown.length, equals(2));
      final rentItem = pl.expenseBreakdown.firstWhere((e) => e.accountCode == '5110');
      expect(rentItem.categoryName, equals('Rent'));
      expect(rentItem.amountPaise, equals(3000000));

      final travelItem = pl.expenseBreakdown.firstWhere((e) => e.accountCode == '5160');
      expect(travelItem.categoryName, equals('Travel'));
      expect(travelItem.amountPaise, equals(1000000));

      // Verify Totals
      expect(pl.totalOperatingExpensesPaise, equals(4000000)); // ₹40,000.00
      expect(pl.grossProfitPaise, equals(10000000)); // Revenue minus 0 COGS
      expect(pl.netProfitPaise, equals(6000000)); // ₹100,000 - ₹40,000 = ₹60,000.00
      expect(pl.isProfitable, isTrue);
      expect(pl.netProfit.formatted, equals('₹60,000.00'));
    });

    test('Period comparison includes previous period P&L report', () async {
      final pl = await reportRepo.getProfitLoss(
        testBusiness.id,
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 31, 23, 59, 59),
        includePreviousPeriod: true,
      );

      expect(pl.previousPeriodReport, isNotNull);
      expect(pl.previousPeriodReport!.startDate.isBefore(pl.startDate), isTrue);
    });
  });
}
