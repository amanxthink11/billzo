import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/expense/expense.dart';
import 'package:billzo/domain/expense/expense_category.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_expense_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_payment_repository.dart';
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

  late Business testBusiness;
  late CashBankAccount testCashAccount;
  late List<ExpenseCategory> categories;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_expense_rollback_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );

    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    paymentRepo = SqlitePaymentRepository(dbHelper);
    expenseRepo = SqliteExpenseRepository(dbHelper);

    testBusiness = await businessRepo.createBusiness(
      Business(
        id: 'biz-rollback',
        name: 'Rollback Enterprises',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    testCashAccount = await paymentRepo.createCashBankAccount(
      CashBankAccount(
        id: 'acc-cash-rb',
        businessId: testBusiness.id,
        name: 'Vault Cash',
        accountType: CashBankAccountType.cash,
        openingBalancePaise: 5000000, // ₹50,000.00
        currentBalancePaise: 5000000,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    categories = await expenseRepo.getCategories(testBusiness.id);
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Expense Transaction Rollback Verification', () {
    test('Simulated failure during postExpense rolls back entire transaction atomically', () async {
      final rentCat = categories.firstWhere((c) => c.name == 'Rent');

      final expense = Expense(
        id: 'exp-fail-post',
        businessId: testBusiness.id,
        categoryId: rentCat.id,
        categoryName: rentCat.name,
        expenseDate: DateTime(2026, 3, 25),
        payee: 'Mega Landlord Ltd',
        description: 'Office rent crash test',
        taxableAmountPaise: 1000000,
        cgstPaise: 90000,
        sgstPaise: 90000,
        igstPaise: 0,
        totalGstPaise: 180000,
        totalAmountPaise: 1180000,
        paymentAccountId: testCashAccount.id,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Save draft
      await expenseRepo.createDraft(expense);

      // Create a repository with a simulated failure trigger right before commit
      final failingRepo = SqliteExpenseRepository(
        dbHelper,
        onBeforePostCommitForTesting: (txn) async {
          throw Exception('CRASH_SIMULATION: OS power outage during posting transaction');
        },
      );

      // Verify posting fails with exception
      expect(
        () async => await failingRepo.postExpense(expense.id),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('CRASH_SIMULATION'))),
      );

      // 1. Verify expense status remains DRAFT and expenseNumber remains null
      final db = await dbHelper.database;
      final expenseRows = await db.query('expenses', where: 'id = ?', whereArgs: [expense.id]);
      expect(expenseRows.length, equals(1));
      expect(expenseRows.first['status'], equals('DRAFT'));
      expect(expenseRows.first['expense_number'], isNull);

      // 2. Verify NO orphan ledger entries exist
      final ledgerRows = await db.query('ledger_entries', where: 'transaction_id = ?', whereArgs: [expense.id]);
      expect(ledgerRows, isEmpty);

      // 3. Verify cash account balance was NOT deducted
      final accountAfter = await paymentRepo.getCashBankAccountById(testCashAccount.id);
      expect(accountAfter!.currentBalancePaise, equals(5000000)); // Exactly ₹50,000.00 intact!

      // 4. Verify sequence rollback: posting successfully afterwards assigns EXP-2026-0001 (no sequence gap!)
      final successfulPost = await expenseRepo.postExpense(expense.id);
      expect(successfulPost.isPosted, isTrue);
      expect(successfulPost.expenseNumber, equals('EXP-2026-0001')); // 0001 was preserved!
    });

    test('Simulated failure during cancelExpense rolls back reversal entries and keeps cash deducted', () async {
      final utilCat = categories.firstWhere((c) => c.name == 'Utilities');

      final expense = Expense(
        id: 'exp-fail-cancel',
        businessId: testBusiness.id,
        categoryId: utilCat.id,
        categoryName: utilCat.name,
        expenseDate: DateTime(2026, 3, 26),
        payee: 'City Water Works',
        description: 'Water utility',
        taxableAmountPaise: 500000,
        cgstPaise: 0,
        sgstPaise: 0,
        igstPaise: 0,
        totalGstPaise: 0,
        totalAmountPaise: 500000,
        paymentAccountId: testCashAccount.id,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await expenseRepo.createDraft(expense);
      final posted = await expenseRepo.postExpense(expense.id);
      expect(posted.isPosted, isTrue);

      final balanceAfterPosting = (await paymentRepo.getCashBankAccountById(testCashAccount.id))!.currentBalancePaise;
      expect(balanceAfterPosting, equals(5000000 - 500000)); // ₹45,000.00

      // Create a failing repo for cancellation
      final failingCancelRepo = SqliteExpenseRepository(
        dbHelper,
        onBeforeCancelCommitForTesting: (txn) async {
          throw Exception('CRASH_SIMULATION: Disk I/O error during cancellation reversal');
        },
      );

      // Cancellation fails
      expect(
        () async => await failingCancelRepo.cancelExpense(posted.id, reason: 'Duplicate payment'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('CRASH_SIMULATION'))),
      );

      // 1. Verify expense status remains POSTED
      final db = await dbHelper.database;
      final expenseRows = await db.query('expenses', where: 'id = ?', whereArgs: [posted.id]);
      expect(expenseRows.first['status'], equals('POSTED'));
      expect(expenseRows.first['cancelled_at'], isNull);

      // 2. Verify NO reversal ledger entries exist
      final reversals = await db.query(
        'ledger_entries',
        where: 'transaction_id = ? AND transaction_type = ?',
        whereArgs: [posted.id, 'EXPENSE_CANCELLATION'],
      );
      expect(reversals, isEmpty);

      // 3. Verify cash balance remains unchanged from post state (not restored partially)
      final accountAfter = await paymentRepo.getCashBankAccountById(testCashAccount.id);
      expect(accountAfter!.currentBalancePaise, equals(balanceAfterPosting));
    });
  });
}
