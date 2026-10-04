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
  late SqlitePaymentRepository paymentRepository;
  late SqliteExpenseRepository expenseRepo;
  late SqliteReportRepository reportRepo;

  late Business testBusiness;
  late CashBankAccount cashAccount;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_bs_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );

    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    paymentRepository = SqlitePaymentRepository(dbHelper);
    expenseRepo = SqliteExpenseRepository(dbHelper);
    reportRepo = SqliteReportRepository(dbHelper);

    testBusiness = await businessRepo.createBusiness(
      Business(
        id: 'biz-bs',
        name: 'Solvency Holdings',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    cashAccount = await paymentRepository.createCashBankAccount(
      CashBankAccount(
        id: 'acc-bs-cash',
        businessId: testBusiness.id,
        name: 'Operating Cash',
        accountType: CashBankAccountType.cash,
        openingBalancePaise: 50000000, // ₹500,000.00
        currentBalancePaise: 50000000,
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

  group('Balance Sheet Accounting Invariant Tests', () {
    test('Balanced double-entry ledger yields balanced Balance Sheet without balancing plugs', () async {
      final db = await dbHelper.database;
      final nowStr = DateTime(2026, 3, 20).toIso8601String();

      // Seed Owner Capital (Account 3000, EQUITY): Credit ₹500,000.00
      // Balanced by Cash (Account 1010, ASSET): Debit ₹500,000.00
      final capitalAccountId = 'acc-cap-3000';
      await db.insert('ledger_accounts', {
        'id': capitalAccountId,
        'business_id': testBusiness.id,
        'code': '3000',
        'name': "Owner's Capital",
        'account_type': 'EQUITY',
        'is_system_account': 1,
        'created_at': nowStr,
        'updated_at': nowStr,
      });

      final cashAccountId = 'acc-cash-1010';
      await db.insert('ledger_accounts', {
        'id': cashAccountId,
        'business_id': testBusiness.id,
        'code': '1010',
        'name': 'Cash on Hand',
        'account_type': 'ASSET',
        'is_system_account': 1,
        'created_at': nowStr,
        'updated_at': nowStr,
      });

      // Capital injection journal entry: Debit 1010, Credit 3000
      await db.insert('ledger_entries', {
        'id': 'le-cap-debit',
        'business_id': testBusiness.id,
        'account_id': cashAccountId,
        'transaction_id': 'tx-init',
        'transaction_type': 'OPENING',
        'entry_date': nowStr,
        'debit_paise': 50000000,
        'credit_paise': 0,
        'description': 'Initial Capital Cash Injection',
        'created_at': nowStr,
      });

      await db.insert('ledger_entries', {
        'id': 'le-cap-credit',
        'business_id': testBusiness.id,
        'account_id': capitalAccountId,
        'transaction_id': 'tx-init',
        'transaction_type': 'OPENING',
        'entry_date': nowStr,
        'debit_paise': 0,
        'credit_paise': 50000000,
        'description': 'Initial Capital Investment',
        'created_at': nowStr,
      });

      // Post an expense: Rent ₹20,000 (Reduces cash 1010, records expense 5110)
      final categories = await expenseRepo.getCategories(testBusiness.id);
      final rentCat = categories.firstWhere((c) => c.name == 'Rent');

      final expense = Expense(
        id: 'exp-bs-rent',
        businessId: testBusiness.id,
        categoryId: rentCat.id,
        categoryName: rentCat.name,
        expenseDate: DateTime(2026, 3, 21),
        payee: 'Apex Commercial',
        description: 'Rent',
        taxableAmountPaise: 2000000,
        totalGstPaise: 0,
        totalAmountPaise: 2000000,
        paymentAccountId: cashAccount.id,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await expenseRepo.createDraft(expense);
      await expenseRepo.postExpense(expense.id);

      // Generate Balance Sheet as of March 31, 2026
      final bs = await reportRepo.getBalanceSheet(
        testBusiness.id,
        asOfDate: DateTime(2026, 3, 31, 23, 59, 59),
      );

      // 1. Mandatory Invariant Check: Assets == Liabilities + Equity
      expect(bs.isBalanced, isTrue);
      expect(bs.imbalancePaise, equals(0));

      // 2. Check Assets
      expect(bs.totalAssetsPaise, equals(48000000)); // ₹500,000 - ₹20,000 = ₹480,000.00
      final cashAsset = bs.assetItems.firstWhere((a) => a.accountCode == '1010');
      expect(cashAsset.amountPaise, equals(48000000));

      // 3. Check Liabilities
      expect(bs.totalLiabilitiesPaise, equals(0));

      // 4. Check Equity
      expect(bs.equityAccountsTotalPaise, equals(50000000)); // Owner capital: ₹500,000
      expect(bs.currentPeriodEarningsPaise, equals(-2000000)); // Net Loss: -₹20,000
      expect(bs.totalEquityPaise, equals(48000000)); // ₹500,000 - ₹20,000 = ₹480,000

      // Total Liabilities & Equity == ₹480,000.00
      expect(bs.totalLiabilitiesAndEquityPaise, equals(48000000));
    });

    test('Corrupted/unbalanced ledger exposes imbalance explicitly without artificial plugs', () async {
      final db = await dbHelper.database;
      final nowStr = DateTime(2026, 3, 20).toIso8601String();

      // Seed an orphan asset without a corresponding credit (fraud/corruption scenario)
      final dummyAssetId = 'acc-dummy-asset';
      await db.insert('ledger_accounts', {
        'id': dummyAssetId,
        'business_id': testBusiness.id,
        'code': '1999',
        'name': 'Orphan Asset',
        'account_type': 'ASSET',
        'is_system_account': 0,
        'created_at': nowStr,
        'updated_at': nowStr,
      });

      await db.insert('ledger_entries', {
        'id': 'le-orphan-asset',
        'business_id': testBusiness.id,
        'account_id': dummyAssetId,
        'transaction_id': 'corrupt-tx',
        'transaction_type': 'UNKNOWN',
        'entry_date': nowStr,
        'debit_paise': 9999900, // ₹99,999.00 orphan debit
        'credit_paise': 0,
        'description': 'Unbalanced entry',
        'created_at': nowStr,
      });

      final bs = await reportRepo.getBalanceSheet(
        testBusiness.id,
        asOfDate: DateTime(2026, 3, 31, 23, 59, 59),
      );

      // Verify the report explicitly exposes the imbalance and does NOT fake equality
      expect(bs.isBalanced, isFalse);
      expect(bs.imbalancePaise, equals(9999900));
      expect(bs.totalAssetsPaise, isNot(equals(bs.totalLiabilitiesAndEquityPaise)));
    });
  });
}
