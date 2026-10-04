import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/expense/expense.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/domain/reports/gst_summary_report.dart';
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
    tempDir = await Directory.systemTemp.createTemp('billzo_gst_test_');
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
        id: 'biz-gst',
        name: 'GST Traders',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    cashAccount = await paymentRepo.createCashBankAccount(
      CashBankAccount(
        id: 'acc-gst-cash',
        businessId: testBusiness.id,
        name: 'Main Cash',
        accountType: CashBankAccountType.cash,
        openingBalancePaise: 50000000,
        currentBalancePaise: 50000000,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    final db = await dbHelper.database;
    final nowStr = DateTime.now().toUtc().toIso8601String();
    await db.insert('customers', {
      'id': 'cust-1',
      'business_id': testBusiness.id,
      'name': 'GST Test Customer',
      'billing_state_code': '27',
      'billing_state_name': 'Maharashtra',
      'created_at': nowStr,
      'updated_at': nowStr,
    });
    await db.insert('suppliers', {
      'id': 'supp-1',
      'business_id': testBusiness.id,
      'name': 'GST Test Supplier',
      'state_code': '27',
      'state_name': 'Maharashtra',
      'created_at': nowStr,
      'updated_at': nowStr,
    });
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('GST Summary / Management Report Tests', () {
    test('Empty period reports zero outward, inward, expense tax and is nil', () async {
      final gst = await reportRepo.getGstSummary(
        testBusiness.id,
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2026, 4, 30, 23, 59, 59),
      );

      expect(gst.outwardSupply.taxableAmountPaise, equals(0));
      expect(gst.outwardSupply.totalTaxPaise, equals(0));
      expect(gst.eligiblePurchaseItc.totalTaxPaise, equals(0));
      expect(gst.eligibleExpenseItc.totalTaxPaise, equals(0));
      expect(gst.totalOutputGstPaise, equals(0));
      expect(gst.totalInputGstPaise, equals(0));
      expect(gst.netGstLiabilityPaise, equals(0));
      expect(gst.isNil, isTrue);
      expect(gst.isPayable, isFalse);
      expect(gst.hasExcessCredit, isFalse);
      expect(GstSummaryReport.reportTitle, equals('GST Summary / Management Report'));
      expect(GstSummaryReport.disclaimer, contains('Not an official statutory GST return'));
    });

    test('Aggregates Outward Sales Tax, Inward Purchase ITC, and Expense ITC accurately', () async {
      final db = await dbHelper.database;
      final apr15Str = DateTime(2026, 4, 15).toIso8601String();

      // 1. Seed Finalized Sales Invoice: Taxable ₹100,000 (10,000,000 paise), CGST ₹9,000, SGST ₹9,000
      await db.insert('invoices', {
        'id': 'inv-gst-1',
        'business_id': testBusiness.id,
        'customer_id': 'cust-1',
        'invoice_number': 'INV-2026-001',
        'invoice_date': apr15Str,
        'due_date': apr15Str,
        'place_of_supply_state_code': '27',
        'status': 'FINALIZED',
        'subtotal_paise': 10000000,
        'taxable_amount_paise': 10000000,
        'cgst_paise': 900000,
        'sgst_paise': 900000,
        'igst_paise': 0,
        'total_amount_paise': 11800000,
        'paid_amount_paise': 0,
        'balance_amount_paise': 11800000,
        'created_at': apr15Str,
        'updated_at': apr15Str,
      });

      // 2. Seed Finalized Purchase with Eligible ITC: Taxable ₹50,000, CGST ₹4,500, SGST ₹4,500
      await db.insert('purchases', {
        'id': 'pur-gst-1',
        'business_id': testBusiness.id,
        'supplier_id': 'supp-1',
        'purchase_number': 'PUR-2026-001',
        'purchase_date': apr15Str,
        'due_date': apr15Str,
        'status': 'FINALIZED',
        'subtotal_paise': 5000000,
        'taxable_amount_paise': 5000000,
        'input_cgst_paise': 450000,
        'input_sgst_paise': 450000,
        'input_igst_paise': 0,
        'cgst_paise': 450000,
        'sgst_paise': 450000,
        'igst_paise': 0,
        'total_amount_paise': 5900000,
        'paid_amount_paise': 0,
        'balance_amount_paise': 5900000,
        'itc_eligibility': 'ELIGIBLE',
        'created_at': apr15Str,
        'updated_at': apr15Str,
      });

      // 3. Seed Purchase Return: Taxable ₹5,000, CGST ₹450, SGST ₹450
      await db.insert('purchase_returns', {
        'id': 'pret-gst-1',
        'business_id': testBusiness.id,
        'original_purchase_id': 'pur-gst-1',
        'supplier_id': 'supp-1',
        'return_number': 'PRET-2026-001',
        'return_date': apr15Str,
        'status': 'FINALIZED',
        'taxable_amount_paise': 500000,
        'cgst_paise': 45000,
        'sgst_paise': 45000,
        'igst_paise': 0,
        'total_amount_paise': 590000,
        'created_at': apr15Str,
        'updated_at': apr15Str,
      });

      // 4. Create and Post an Expense with GST (Office supplies: ₹10,000 taxable + 9% CGST (₹900) + 9% SGST (₹900))
      final categories = await expenseRepo.getCategories(testBusiness.id);
      final officeCat = categories.firstWhere((c) => c.name == 'Office Supplies');
      final advCat = categories.firstWhere((c) => c.name.contains('Advertising'));

      final expenseDraft = Expense(
        id: 'exp-gst-posted',
        businessId: testBusiness.id,
        categoryId: officeCat.id,
        categoryName: officeCat.name,
        expenseDate: DateTime(2026, 4, 15),
        payee: 'Stationery World',
        description: 'Printer ink and reams',
        taxableAmountPaise: 1000000, // ₹10,000
        cgstPaise: 90000, // ₹900
        sgstPaise: 90000, // ₹900
        igstPaise: 0,
        totalGstPaise: 180000, // ₹1,800
        totalAmountPaise: 1180000, // ₹11,800
        paymentAccountId: cashAccount.id,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await expenseRepo.createDraft(expenseDraft);
      await expenseRepo.postExpense(expenseDraft.id);

      // 5. Create a DRAFT expense — should NOT be included in ITC
      final draftExpense = Expense(
        id: 'exp-gst-draft',
        businessId: testBusiness.id,
        categoryId: advCat.id,
        categoryName: advCat.name,
        expenseDate: DateTime(2026, 4, 16),
        payee: 'Ad Agency',
        description: 'Pending banner ads',
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
      await expenseRepo.createDraft(draftExpense);

      // Run GST Summary for April 2026
      final gst = await reportRepo.getGstSummary(
        testBusiness.id,
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2026, 4, 30, 23, 59, 59),
      );

      // Verify Outward Supply
      expect(gst.outwardSupply.taxableAmountPaise, equals(10000000));
      expect(gst.outwardSupply.cgstPaise, equals(900000));
      expect(gst.outwardSupply.sgstPaise, equals(900000));
      expect(gst.outwardSupply.igstPaise, equals(0));
      expect(gst.totalOutputGstPaise, equals(1800000)); // ₹18,000

      // Verify Inward Purchase ITC (Purchase ₹4,500 each - Return ₹450 each = ₹4,050 each = 405000 paise)
      expect(gst.eligiblePurchaseItc.taxableAmountPaise, equals(4500000)); // ₹50k - ₹5k = ₹45k
      expect(gst.eligiblePurchaseItc.cgstPaise, equals(405000));
      expect(gst.eligiblePurchaseItc.sgstPaise, equals(405000));
      expect(gst.eligiblePurchaseItc.totalTaxPaise, equals(810000)); // ₹8,100

      // Verify Expense Input Tax (from posted expense only, draft ignored)
      expect(gst.eligibleExpenseItc.taxableAmountPaise, equals(1000000));
      expect(gst.eligibleExpenseItc.cgstPaise, equals(90000));
      expect(gst.eligibleExpenseItc.sgstPaise, equals(90000));
      expect(gst.eligibleExpenseItc.totalTaxPaise, equals(180000)); // ₹1,800

      // Total Input GST = Purchase ITC (₹8,100) + Expense ITC (₹1,800) = ₹9,900 = 990000 paise
      expect(gst.totalInputGstPaise, equals(990000));

      // Net GST Liability = Output GST (₹18,000) - Total Input GST (₹9,900) = ₹8,100 (810000 paise)
      expect(gst.netGstLiabilityPaise, equals(810000));
      expect(gst.isPayable, isTrue);
      expect(gst.hasExcessCredit, isFalse);
    });

    test('Excess ITC results in net credit carried forward', () async {
      final db = await dbHelper.database;
      final apr15Str = DateTime(2026, 4, 15).toIso8601String();

      // Large purchase: Taxable ₹200,000, CGST ₹18,000, SGST ₹18,000 (Total ITC: ₹36,000)
      await db.insert('purchases', {
        'id': 'pur-gst-big',
        'business_id': testBusiness.id,
        'supplier_id': 'supp-1',
        'purchase_number': 'PUR-2026-BIG',
        'purchase_date': apr15Str,
        'due_date': apr15Str,
        'status': 'FINALIZED',
        'subtotal_paise': 20000000,
        'taxable_amount_paise': 20000000,
        'input_cgst_paise': 1800000,
        'input_sgst_paise': 1800000,
        'input_igst_paise': 0,
        'cgst_paise': 1800000,
        'sgst_paise': 1800000,
        'igst_paise': 0,
        'total_amount_paise': 23600000,
        'paid_amount_paise': 0,
        'balance_amount_paise': 23600000,
        'itc_eligibility': 'ELIGIBLE',
        'created_at': apr15Str,
        'updated_at': apr15Str,
      });

      // Small sales: Taxable ₹50,000, CGST ₹4,500, SGST ₹4,500 (Total Output: ₹9,000)
      await db.insert('invoices', {
        'id': 'inv-gst-small',
        'business_id': testBusiness.id,
        'customer_id': 'cust-1',
        'invoice_number': 'INV-2026-SMALL',
        'invoice_date': apr15Str,
        'due_date': apr15Str,
        'place_of_supply_state_code': '27',
        'status': 'FINALIZED',
        'subtotal_paise': 5000000,
        'taxable_amount_paise': 5000000,
        'cgst_paise': 450000,
        'sgst_paise': 450000,
        'igst_paise': 0,
        'total_amount_paise': 5900000,
        'paid_amount_paise': 0,
        'balance_amount_paise': 5900000,
        'created_at': apr15Str,
        'updated_at': apr15Str,
      });

      final gst = await reportRepo.getGstSummary(
        testBusiness.id,
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2026, 4, 30, 23, 59, 59),
      );

      // Output ₹9,000 - Input ₹36,000 = -₹27,000 (-2700000 paise)
      expect(gst.totalOutputGstPaise, equals(900000));
      expect(gst.totalInputGstPaise, equals(3600000));
      expect(gst.netGstLiabilityPaise, equals(-2700000));
      expect(gst.hasExcessCredit, isTrue);
      expect(gst.isPayable, isFalse);
      expect(gst.netGstLiability.paise, equals(2700000));
    });
  });
}
