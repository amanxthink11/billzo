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
  late CashBankAccount bankAccount;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_trial_balance_test_');
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
        id: 'biz-tb',
        name: 'Equilibrium Enterprises',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    cashAccount = await paymentRepo.createCashBankAccount(
      CashBankAccount(
        id: 'acc-tb-cash',
        businessId: testBusiness.id,
        name: 'Main Cash',
        accountType: CashBankAccountType.cash,
        openingBalancePaise: 20000000, // ₹200,000.00
        currentBalancePaise: 20000000,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    bankAccount = await paymentRepo.createCashBankAccount(
      CashBankAccount(
        id: 'acc-tb-bank',
        businessId: testBusiness.id,
        name: 'Corporate Current Account',
        accountType: CashBankAccountType.bank,
        openingBalancePaise: 80000000, // ₹800,000.00
        currentBalancePaise: 80000000,
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

  group('Trial Balance Verification Tests', () {
    test('Empty ledger before postings reports zero debits and zero credits and is balanced', () async {
      final tb = await reportRepo.getTrialBalance(testBusiness.id);

      expect(tb.isBalanced, isTrue);
      expect(tb.totalDebitsPaise, equals(0));
      expect(tb.totalCreditsPaise, equals(0));
      expect(tb.entries, isEmpty);
    });

    test('Multi-transaction workflow generates balanced Trial Balance with exact account totals', () async {
      final categories = await expenseRepo.getCategories(testBusiness.id);
      final rentCat = categories.firstWhere((c) => c.name == 'Rent');
      final utilCat = categories.firstWhere((c) => c.name == 'Utilities');

      // Expense 1: Rent paid via Bank with 18% GST (Taxable: ₹20,000, CGST: ₹1,800, SGST: ₹1,800, Total: ₹23,600)
      final exp1 = Expense(
        id: 'exp-tb-1',
        businessId: testBusiness.id,
        categoryId: rentCat.id,
        categoryName: rentCat.name,
        expenseDate: DateTime(2026, 3, 10),
        payee: 'Commercial Landlord',
        description: 'Rent',
        taxableAmountPaise: 2000000,
        cgstPaise: 180000,
        sgstPaise: 180000,
        igstPaise: 0,
        totalGstPaise: 360000,
        totalAmountPaise: 2360000,
        paymentAccountId: bankAccount.id,
        paymentMethod: PaymentMethod.bankTransfer,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await expenseRepo.createDraft(exp1);
      await expenseRepo.postExpense(exp1.id);

      // Expense 2: Utilities paid in Cash without GST (Total: ₹5,000)
      final exp2 = Expense(
        id: 'exp-tb-2',
        businessId: testBusiness.id,
        categoryId: utilCat.id,
        categoryName: utilCat.name,
        expenseDate: DateTime(2026, 3, 15),
        payee: 'Power Board',
        description: 'Electricity',
        taxableAmountPaise: 500000,
        cgstPaise: 0,
        sgstPaise: 0,
        igstPaise: 0,
        totalGstPaise: 0,
        totalAmountPaise: 500000,
        paymentAccountId: cashAccount.id,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await expenseRepo.createDraft(exp2);
      await expenseRepo.postExpense(exp2.id);

      // Fetch Trial Balance
      final tb = await reportRepo.getTrialBalance(testBusiness.id);

      // 1. Mandatory Invariant Check
      expect(tb.isBalanced, isTrue, reason: 'Trial Balance must satisfy Total Debits == Total Credits');
      expect(tb.differencePaise, equals(0));
      expect(tb.totalDebitsPaise, equals(2860000)); // 2360000 + 500000
      expect(tb.totalCreditsPaise, equals(2860000));

      // 2. Inspect individual account ledger lines
      final rentEntry = tb.entries.firstWhere((e) => e.accountCode == '5110');
      expect(rentEntry.accountName, contains('Rent'));
      expect(rentEntry.netDebitPaise, equals(2000000));
      expect(rentEntry.netCreditPaise, equals(0));

      final utilEntry = tb.entries.firstWhere((e) => e.accountCode == '5120');
      expect(utilEntry.accountName, contains('Utilities'));
      expect(utilEntry.netDebitPaise, equals(500000));

      final cgstEntry = tb.entries.firstWhere((e) => e.accountCode == '2310');
      expect(cgstEntry.netDebitPaise, equals(180000));

      final sgstEntry = tb.entries.firstWhere((e) => e.accountCode == '2320');
      expect(sgstEntry.netDebitPaise, equals(180000));

      final bankEntry = tb.entries.firstWhere((e) => e.accountCode == '1020');
      expect(bankEntry.netCreditPaise, equals(2360000));

      final cashEntry = tb.entries.firstWhere((e) => e.accountCode == '1010');
      expect(cashEntry.netCreditPaise, equals(500000));
    });

    test('Date filtering restricts Trial Balance to specified time window', () async {
      final categories = await expenseRepo.getCategories(testBusiness.id);
      final rentCat = categories.firstWhere((c) => c.name == 'Rent');

      // Expense in January
      final janExp = Expense(
        id: 'exp-jan',
        businessId: testBusiness.id,
        categoryId: rentCat.id,
        categoryName: rentCat.name,
        expenseDate: DateTime(2026, 1, 15),
        payee: 'Landlord',
        description: 'Jan Rent',
        taxableAmountPaise: 1000000,
        totalGstPaise: 0,
        totalAmountPaise: 1000000,
        paymentAccountId: cashAccount.id,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await expenseRepo.createDraft(janExp);
      await expenseRepo.postExpense(janExp.id);

      // Expense in February
      final febExp = Expense(
        id: 'exp-feb',
        businessId: testBusiness.id,
        categoryId: rentCat.id,
        categoryName: rentCat.name,
        expenseDate: DateTime(2026, 2, 15),
        payee: 'Landlord',
        description: 'Feb Rent',
        taxableAmountPaise: 1000000,
        totalGstPaise: 0,
        totalAmountPaise: 1000000,
        paymentAccountId: cashAccount.id,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await expenseRepo.createDraft(febExp);
      await expenseRepo.postExpense(febExp.id);

      // As of Jan 31: only Jan expense included
      final tbJan = await reportRepo.getTrialBalance(
        testBusiness.id,
        asOfDate: DateTime(2026, 1, 31, 23, 59, 59),
      );
      expect(tbJan.isBalanced, isTrue);
      expect(tbJan.totalDebitsPaise, equals(1000000));

      // As of Feb 28: both expenses included
      final tbFeb = await reportRepo.getTrialBalance(
        testBusiness.id,
        asOfDate: DateTime(2026, 2, 28, 23, 59, 59),
      );
      expect(tbFeb.isBalanced, isTrue);
      expect(tbFeb.totalDebitsPaise, equals(2000000));
    });
  });
}
