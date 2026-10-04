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

  late Business businessA;
  late Business businessB;
  late CashBankAccount cashAccountA;
  late CashBankAccount bankAccountA;
  late List<ExpenseCategory> categoriesA;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_expense_workflow_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );

    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    paymentRepo = SqlitePaymentRepository(dbHelper);
    expenseRepo = SqliteExpenseRepository(dbHelper);

    // Seed Business A (Maharashtra, 27)
    businessA = await businessRepo.createBusiness(
      Business(
        id: 'biz-a',
        name: 'Alpha Traders',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    // Seed Business B (Karnataka, 29)
    businessB = await businessRepo.createBusiness(
      Business(
        id: 'biz-b',
        name: 'Beta Services',
        phone: '9876543211',
        stateCode: '29',
        stateName: 'Karnataka',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    // Create Cash and Bank accounts for Business A with starting balances
    cashAccountA = await paymentRepo.createCashBankAccount(
      CashBankAccount(
        id: 'acc-cash-a',
        businessId: businessA.id,
        name: 'Main Cash Drawer',
        accountType: CashBankAccountType.cash,
        openingBalancePaise: 10000000, // ₹100,000.00
        currentBalancePaise: 10000000,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    bankAccountA = await paymentRepo.createCashBankAccount(
      CashBankAccount(
        id: 'acc-bank-a',
        businessId: businessA.id,
        name: 'HDFC Corporate Current',
        accountType: CashBankAccountType.bank,
        openingBalancePaise: 50000000, // ₹500,000.00
        currentBalancePaise: 50000000,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    categoriesA = await expenseRepo.getCategories(businessA.id);
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Expense Workflow & Double-Entry Accounting Tests', () {
    test('Draft expense creation does not allocate sequence, alter cash balance, or post to ledger', () async {
      final rentCategory = categoriesA.firstWhere((c) => c.name == 'Rent');

      final draftExpense = Expense(
        id: 'exp-draft-1',
        businessId: businessA.id,
        categoryId: rentCategory.id,
        categoryName: rentCategory.name,
        expenseDate: DateTime.now(),
        payee: 'Apex Landlords',
        description: 'Office rent draft',
        taxableAmountPaise: 2000000, // ₹20,000.00
        cgstPaise: 180000,          // ₹1,800.00
        sgstPaise: 180000,          // ₹1,800.00
        igstPaise: 0,
        totalGstPaise: 360000,       // ₹3,600.00
        totalAmountPaise: 2360000,   // ₹23,600.00
        paymentAccountId: cashAccountA.id,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final saved = await expenseRepo.createDraft(draftExpense);

      // Verify draft status and no sequence consumed
      expect(saved.isDraft, isTrue);
      expect(saved.expenseNumber, isNull);

      // Verify cash balance is untouched
      final cashAfter = await paymentRepo.getCashBankAccountById(cashAccountA.id);
      expect(cashAfter!.currentBalancePaise, equals(10000000));

      // Verify no ledger entries created for this expense
      final db = await dbHelper.database;
      final ledgerEntries = await db.query(
        'ledger_entries',
        where: 'transaction_id = ?',
        whereArgs: [saved.id],
      );
      expect(ledgerEntries, isEmpty);
    });

    test('Posting cash expense allocates sequence, deducts cash, and creates balanced journal entries', () async {
      final rentCat = categoriesA.firstWhere((c) => c.name == 'Rent');

      final expense = Expense(
        id: 'exp-post-cash-1',
        businessId: businessA.id,
        categoryId: rentCat.id,
        categoryName: rentCat.name,
        expenseDate: DateTime(2026, 3, 20),
        payee: 'Apex Realty',
        description: 'Office rent',
        taxableAmountPaise: 3000000, // ₹30,000.00
        cgstPaise: 270000,          // ₹2,700.00
        sgstPaise: 270000,          // ₹2,700.00
        igstPaise: 0,
        totalGstPaise: 540000,       // ₹5,400.00
        totalAmountPaise: 3540000,   // ₹35,400.00
        paymentAccountId: cashAccountA.id,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await expenseRepo.createDraft(expense);
      final posted = await expenseRepo.postExpense(expense.id);

      // 1. Verify sequence allocated correctly
      expect(posted.isPosted, isTrue);
      expect(posted.expenseNumber, startsWith('EXP-2026-'));
      expect(posted.expenseNumber, equals('EXP-2026-0001'));
      expect(posted.postedAt, isNotNull);

      // 2. Verify cash account balance deducted exactly by total amount
      final cashAfter = await paymentRepo.getCashBankAccountById(cashAccountA.id);
      expect(cashAfter!.currentBalancePaise, equals(10000000 - 3540000)); // ₹64,600.00

      // 3. Verify double-entry ledger postings
      final db = await dbHelper.database;
      final entries = await db.rawQuery('''
        SELECT le.*, la.code as account_code
        FROM ledger_entries le
        JOIN ledger_accounts la ON le.account_id = la.id
        WHERE le.transaction_id = ?
      ''', [posted.id]);

      // Expect entries: Debit Expense (5110), Debit Input CGST (2310), Debit Input SGST (2320), Credit Cash (1010)
      expect(entries.length, equals(4));

      int totalDebits = 0;
      int totalCredits = 0;
      for (final e in entries) {
        totalDebits += (e['debit_paise'] as num).toInt();
        totalCredits += (e['credit_paise'] as num).toInt();
      }

      // Mandatory Double-Entry Balance Check
      expect(totalDebits, equals(totalCredits));
      expect(totalDebits, equals(3540000));

      // Check specific ledger accounts
      final rentEntry = entries.firstWhere((e) => (e['account_code'] as String).startsWith('51'));
      expect(rentEntry['debit_paise'], equals(3000000));
      expect(rentEntry['credit_paise'], equals(0));

      final cgstEntry = entries.firstWhere((e) => e['account_code'] == '2310');
      expect(cgstEntry['debit_paise'], equals(270000));

      final sgstEntry = entries.firstWhere((e) => e['account_code'] == '2320');
      expect(sgstEntry['debit_paise'], equals(270000));

      final cashEntry = entries.firstWhere((e) => e['account_code'] == '1010');
      expect(cashEntry['credit_paise'], equals(3540000));
      expect(cashEntry['debit_paise'], equals(0));
    });

    test('Posting bank expense with IGST creates balanced entries crediting Bank (1020)', () async {
      final profFeesCat = categoriesA.firstWhere((c) => c.name == 'Professional Fees');

      final expense = Expense(
        id: 'exp-post-bank-igst',
        businessId: businessA.id,
        categoryId: profFeesCat.id,
        categoryName: profFeesCat.name,
        expenseDate: DateTime(2026, 3, 21),
        payee: 'Bengaluru Tech Legal Advisors',
        description: 'Interstate Legal consultation',
        taxableAmountPaise: 4000000, // ₹40,000.00
        cgstPaise: 0,
        sgstPaise: 0,
        igstPaise: 720000,          // ₹7,200.00 (18% IGST)
        totalGstPaise: 720000,
        totalAmountPaise: 4720000,   // ₹47,200.00
        paymentAccountId: bankAccountA.id,
        paymentMethod: PaymentMethod.bankTransfer,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await expenseRepo.createDraft(expense);
      final posted = await expenseRepo.postExpense(expense.id);

      expect(posted.isPosted, isTrue);
      expect(posted.expenseNumber, equals('EXP-2026-0001'));

      // Bank account deducted
      final bankAfter = await paymentRepo.getCashBankAccountById(bankAccountA.id);
      expect(bankAfter!.currentBalancePaise, equals(50000000 - 4720000));

      // Verify entries: Debit 5180 (4000000), Debit 2330 (720000), Credit 1020 (4720000)
      final db = await dbHelper.database;
      final entries = await db.rawQuery('''
        SELECT le.*, la.code as account_code
        FROM ledger_entries le
        JOIN ledger_accounts la ON le.account_id = la.id
        WHERE le.transaction_id = ?
      ''', [posted.id]);

      expect(entries.length, equals(3));
      int totalDebits = 0;
      int totalCredits = 0;
      for (final e in entries) {
        totalDebits += (e['debit_paise'] as num).toInt();
        totalCredits += (e['credit_paise'] as num).toInt();
      }
      expect(totalDebits, equals(totalCredits));
      expect(totalDebits, equals(4720000));

      final igstEntry = entries.firstWhere((e) => e['account_code'] == '2330');
      expect(igstEntry['debit_paise'], equals(720000));

      final bankEntry = entries.firstWhere((e) => e['account_code'] == '1020');
      expect(bankEntry['credit_paise'], equals(4720000));
    });

    test('Cancellation of posted expense creates reversal entries and restores cash balance', () async {
      final utilCat = categoriesA.firstWhere((c) => c.name == 'Utilities');

      final expense = Expense(
        id: 'exp-to-cancel',
        businessId: businessA.id,
        categoryId: utilCat.id,
        categoryName: utilCat.name,
        expenseDate: DateTime(2026, 3, 22),
        payee: 'MSEB Electricity',
        description: 'Power bill',
        taxableAmountPaise: 1500000, // ₹15,000.00
        cgstPaise: 0,
        sgstPaise: 0,
        igstPaise: 0,
        totalGstPaise: 0,
        totalAmountPaise: 1500000,
        paymentAccountId: cashAccountA.id,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await expenseRepo.createDraft(expense);
      final posted = await expenseRepo.postExpense(expense.id);
      expect(posted.isPosted, isTrue);

      final balanceAfterPosting = (await paymentRepo.getCashBankAccountById(cashAccountA.id))!.currentBalancePaise;
      expect(balanceAfterPosting, equals(10000000 - 1500000));

      // Now cancel the posted expense
      final cancelled = await expenseRepo.cancelExpense(
        posted.id,
        reason: 'Electricity bill was already settled by partner',
      );

      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.cancellationReason, equals('Electricity bill was already settled by partner'));
      expect(cancelled.cancelledAt, isNotNull);

      // Verify cash balance restored!
      final cashAfterCancel = await paymentRepo.getCashBankAccountById(cashAccountA.id);
      expect(cashAfterCancel!.currentBalancePaise, equals(10000000));

      // Verify reversal ledger entry
      final db = await dbHelper.database;
      final reversalEntries = await db.rawQuery('''
        SELECT le.*, la.code as account_code
        FROM ledger_entries le
        JOIN ledger_accounts la ON le.account_id = la.id
        WHERE le.transaction_type = ? AND le.transaction_id = ?
      ''', ['EXPENSE_CANCELLATION', posted.id]);

      expect(reversalEntries.length, equals(2));

      // Debit Cash (1010) to restore money
      final debitCash = reversalEntries.firstWhere((e) => e['account_code'] == '1010');
      expect(debitCash['debit_paise'], equals(1500000));
      expect(debitCash['credit_paise'], equals(0));

      // Credit Utility Expense (5120) to reverse expense
      final creditExp = reversalEntries.firstWhere((e) => (e['account_code'] as String).startsWith('51'));
      expect(creditExp['credit_paise'], equals(1500000));
      expect(creditExp['debit_paise'], equals(0));
    });

    test('Expense sequence numbering is completely isolated per business', () async {
      // Create cash account for Business B
      final cashB = await paymentRepo.createCashBankAccount(
        CashBankAccount(
          id: 'acc-cash-b',
          businessId: businessB.id,
          name: 'Bengaluru Petty Cash',
          accountType: CashBankAccountType.cash,
          openingBalancePaise: 5000000,
          currentBalancePaise: 5000000,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      final categoriesB = await expenseRepo.getCategories(businessB.id);

      final expA = Expense(
        id: 'exp-biz-a-seq',
        businessId: businessA.id,
        categoryId: categoriesA.first.id,
        categoryName: categoriesA.first.name,
        expenseDate: DateTime(2026, 3, 23),
        payee: 'Payee A',
        description: 'Office item',
        taxableAmountPaise: 100000,
        totalGstPaise: 0,
        totalAmountPaise: 100000,
        paymentAccountId: cashAccountA.id,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final expB = Expense(
        id: 'exp-biz-b-seq',
        businessId: businessB.id,
        categoryId: categoriesB.first.id,
        categoryName: categoriesB.first.name,
        expenseDate: DateTime(2026, 3, 23),
        payee: 'Payee B',
        description: 'Office item',
        taxableAmountPaise: 200000,
        totalGstPaise: 0,
        totalAmountPaise: 200000,
        paymentAccountId: cashB.id,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await expenseRepo.createDraft(expA);
      await expenseRepo.createDraft(expB);

      final postedA = await expenseRepo.postExpense(expA.id);
      final postedB = await expenseRepo.postExpense(expB.id);

      // Both should have their own isolated EXP-2026-0001 sequence
      expect(postedA.expenseNumber, equals('EXP-2026-0001'));
      expect(postedB.expenseNumber, equals('EXP-2026-0001'));
    });
  });
}
