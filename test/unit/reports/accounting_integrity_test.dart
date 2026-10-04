import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
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
  late AccountingIntegrityService integrityService;

  late Business testBusiness;
  late CashBankAccount cashAccount;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_audit_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );

    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    paymentRepo = SqlitePaymentRepository(dbHelper);
    expenseRepo = SqliteExpenseRepository(dbHelper);
    integrityService = AccountingIntegrityService(dbHelper);

    testBusiness = await businessRepo.createBusiness(
      Business(
        id: 'biz-audit',
        name: 'Integrity Assurance Corp',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    cashAccount = await paymentRepo.createCashBankAccount(
      CashBankAccount(
        id: 'acc-audit-cash',
        businessId: testBusiness.id,
        name: 'Audit Cash',
        accountType: CashBankAccountType.cash,
        openingBalancePaise: 50000000,
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

  group('Accounting Data Integrity & Audit Service Tests', () {
    test('Clean state reports isClean == true with 0 issues', () async {
      final report = await integrityService.runIntegrityAudit(testBusiness.id);

      expect(report.isClean, isTrue);
      expect(report.journalEntriesBalanced, isTrue);
      expect(report.trialBalanceBalanced, isTrue);
      expect(report.cashBankReconciled, isTrue);
      expect(report.receivablesReconciled, isTrue);
      expect(report.payablesReconciled, isTrue);
      expect(report.expensesReconciled, isTrue);
      expect(report.issues, isEmpty);
    });

    test('Clean state after posted and cancelled expense operations', () async {
      final categories = await expenseRepo.getCategories(testBusiness.id);
      final rentCategory = categories.firstWhere((c) => c.name == 'Rent');

      // 1. Post rent expense: ₹20,000 + 18% GST (₹3,600) = ₹23,600 from cash
      final rentExpense = Expense(
        id: 'exp-audit-rent',
        businessId: testBusiness.id,
        categoryId: rentCategory.id,
        categoryName: rentCategory.name,
        expenseDate: DateTime.now(),
        payee: 'Office Realty Ltd',
        description: 'Monthly office rent',
        taxableAmountPaise: 2000000,
        cgstPaise: 180000,
        sgstPaise: 180000,
        igstPaise: 0,
        totalGstPaise: 360000,
        totalAmountPaise: 2360000,
        paymentAccountId: cashAccount.id,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      await expenseRepo.createDraft(rentExpense);
      await expenseRepo.postExpense(rentExpense.id);

      // Audit after posting
      var report = await integrityService.runIntegrityAudit(testBusiness.id);
      expect(report.isClean, isTrue);
      expect(report.expensesReconciled, isTrue);
      expect(report.cashBankReconciled, isTrue);
      expect(report.journalEntriesBalanced, isTrue);
      expect(report.trialBalanceBalanced, isTrue);

      // 2. Post and then cancel an insurance expense
      final insCategory = categories.firstWhere((c) => c.name == 'Insurance');
      final insExpense = Expense(
        id: 'exp-audit-ins',
        businessId: testBusiness.id,
        categoryId: insCategory.id,
        categoryName: insCategory.name,
        expenseDate: DateTime.now(),
        payee: 'Shield Insurance',
        description: 'Transit insurance policy',
        taxableAmountPaise: 500000,
        cgstPaise: 45000,
        sgstPaise: 45000,
        igstPaise: 0,
        totalGstPaise: 90000,
        totalAmountPaise: 590000,
        paymentAccountId: cashAccount.id,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      await expenseRepo.createDraft(insExpense);
      await expenseRepo.postExpense(insExpense.id);
      await expenseRepo.cancelExpense(insExpense.id, reason: 'Duplicate policy issued');

      // Audit after cancellation and reversal
      report = await integrityService.runIntegrityAudit(testBusiness.id);
      expect(report.isClean, isTrue);
      expect(report.expensesReconciled, isTrue);
      expect(report.cashBankReconciled, isTrue);
      expect(report.journalEntriesBalanced, isTrue);
      expect(report.trialBalanceBalanced, isTrue);
    });

    test('Catches unbalanced journal entry discrepancy', () async {
      final db = await dbHelper.database;
      final nowStr = DateTime.now().toUtc().toIso8601String();

      // Ensure account 1010 exists
      final cashAccountRow = await db.query('ledger_accounts', where: 'code = ? AND business_id = ?', whereArgs: ['1010', testBusiness.id]);
      late String accId;
      if (cashAccountRow.isEmpty) {
        accId = 'acc-audit-1010';
        await db.insert('ledger_accounts', {
          'id': accId,
          'business_id': testBusiness.id,
          'code': '1010',
          'name': 'Cash in Hand',
          'account_type': 'ASSET',
          'created_at': nowStr,
          'updated_at': nowStr,
        });
      } else {
        accId = cashAccountRow.first['id'] as String;
      }

      // Insert an intentionally unbalanced entry: debit 10,000 paise, credit 5,000 paise
      await db.insert('ledger_entries', {
        'id': 'le-unbalanced-1',
        'business_id': testBusiness.id,
        'transaction_id': 'txn-corrupt-1',
        'transaction_type': 'MANUAL_JOURNAL',
        'account_id': accId,
        'debit_paise': 10000,
        'credit_paise': 0,
        'entry_date': nowStr,
        'created_at': nowStr,
      });
      await db.insert('ledger_entries', {
        'id': 'le-unbalanced-2',
        'business_id': testBusiness.id,
        'transaction_id': 'txn-corrupt-1',
        'transaction_type': 'MANUAL_JOURNAL',
        'account_id': accId,
        'debit_paise': 0,
        'credit_paise': 5000,
        'entry_date': nowStr,
        'created_at': nowStr,
      });

      final report = await integrityService.runIntegrityAudit(testBusiness.id);

      expect(report.isClean, isFalse);
      expect(report.journalEntriesBalanced, isFalse);
      expect(report.issues.any((i) => i.category == 'JOURNAL'), isTrue);
      final issue = report.issues.firstWhere((i) => i.category == 'JOURNAL');
      expect(issue.discrepancyPaise, equals(5000));
    });

    test('Catches cash/bank holding discrepancy against ledger', () async {
      final db = await dbHelper.database;

      // Tamper with cash_bank_accounts current_balance directly
      await db.update(
        'cash_bank_accounts',
        {'current_balance_paise': 99999999}, // Arbitrary stolen/modified balance
        where: 'id = ?',
        whereArgs: [cashAccount.id],
      );

      final report = await integrityService.runIntegrityAudit(testBusiness.id);

      expect(report.isClean, isFalse);
      expect(report.cashBankReconciled, isFalse);
      expect(report.issues.any((i) => i.category == 'CASH_BANK'), isTrue);
    });

    test('Catches expense ledger disagreement if expense record deleted or tampered', () async {
      final categories = await expenseRepo.getCategories(testBusiness.id);
      final cat = categories.first;

      final expense = Expense(
        id: 'exp-audit-tamper',
        businessId: testBusiness.id,
        categoryId: cat.id,
        categoryName: cat.name,
        expenseDate: DateTime.now(),
        payee: 'Vendor X',
        description: 'Office supply',
        taxableAmountPaise: 1000000,
        cgstPaise: 0,
        sgstPaise: 0,
        igstPaise: 0,
        totalGstPaise: 0,
        totalAmountPaise: 1000000,
        paymentAccountId: cashAccount.id,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      await expenseRepo.createDraft(expense);
      await expenseRepo.postExpense(expense.id);

      // Now tamper with the expense taxable amount in expenses table without updating ledger
      final db = await dbHelper.database;
      await db.update(
        'expenses',
        {'taxable_amount_paise': 2000000}, // Changed from 10,000 to 20,000
        where: 'id = ?',
        whereArgs: [expense.id],
      );

      final report = await integrityService.runIntegrityAudit(testBusiness.id);

      expect(report.isClean, isFalse);
      expect(report.expensesReconciled, isFalse);
      expect(report.issues.any((i) => i.category == 'EXPENSE'), isTrue);
      final issue = report.issues.firstWhere((i) => i.category == 'EXPENSE');
      expect(issue.discrepancyPaise, equals(1000000));
    });
  });
}
