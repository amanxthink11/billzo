import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/application/backup/restore_service.dart';
import 'package:billzo/application/reports/accounting_integrity_service.dart';
import 'package:billzo/domain/backup/backup_exceptions.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/expense/expense.dart';
import 'package:billzo/domain/expense/expense_status.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_item.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/domain/payment/payment.dart';
import 'package:billzo/domain/payment/payment_allocation.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/domain/payment/payment_status.dart';
import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_item.dart';
import 'package:billzo/domain/purchase/purchase_status.dart';
import 'package:billzo/domain/recurring/recurring_frequency.dart';
import 'package:billzo/domain/recurring/recurring_invoice.dart';
import 'package:billzo/domain/recurring/recurring_invoice_status.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_backup_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_expense_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_invoice_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_party_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_payment_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_product_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_purchase_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_recurring_invoice_repository.dart';
import 'package:billzo/infrastructure/services/backup/backup_service.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

class ReleaseValidationPathProvider implements IAppPathProvider {
  final Directory rootDir;
  ReleaseValidationPathProvider(this.rootDir);

  @override
  Future<String> getDatabaseDirectory() async {
    final d = Directory(p.join(rootDir.path, 'data'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d.path;
  }

  @override
  Future<String> getBackupsDirectory() async {
    final d = Directory(p.join(rootDir.path, 'backups'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d.path;
  }

  @override
  Future<String> getMediaDirectory() async {
    final d = Directory(p.join(rootDir.path, 'media'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d.path;
  }

  @override
  Future<String> getExportsDirectory() async {
    final d = Directory(p.join(rootDir.path, 'exports'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d.path;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Deep-Dive Release Validation & QA Audit', () {
    late Directory tempDir;
    late ReleaseValidationPathProvider pathProvider;
    late String dbFilePath;
    late DatabaseHelper dbHelper;
    late Business testBusiness;
    late String taxRate18Id;
    late String unitPcsId;
    late CashBankAccount cashAccount;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('billzo_val_deep_');
      pathProvider = ReleaseValidationPathProvider(tempDir);
      dbFilePath = p.join(await pathProvider.getDatabaseDirectory(), 'billzo_val.db');

      dbHelper = DatabaseHelper.createForTesting(
        dbPath: dbFilePath,
        pathProvider: pathProvider,
        dbFactory: databaseFactoryFfi,
      );

      final db = await dbHelper.database;
      final now = DateTime.now().toUtc();

      // Create Business
      final bizRepo = SqliteBusinessRepository(dbHelper: dbHelper);
      testBusiness = await bizRepo.createBusiness(
        Business(
          id: 'biz-val-001',
          name: 'Apex Industrial Corp',
          tradeName: 'Apex Tools',
          gstin: '27AABCU9603R1ZM',
          pan: 'AABCU9603R',
          phone: '9876543210',
          email: 'sales@apextools.com',
          addressLine1: 'Plot 10, MIDC',
          city: 'Pune',
          stateCode: '27',
          stateName: 'Maharashtra',
          pincode: '411019',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final taxRows = await db.query('tax_rates', where: 'business_id = ?', whereArgs: [testBusiness.id]);
      taxRate18Id = taxRows.firstWhere((r) => r['rate_basis_points'] == 1800)['id'] as String;

      final unitRows = await db.query('units', where: 'business_id = ?', whereArgs: [testBusiness.id]);
      unitPcsId = unitRows.firstWhere((u) => u['code'] == 'PCS')['id'] as String;

      final payRepo = SqlitePaymentRepository(dbHelper);
      cashAccount = await payRepo.createCashBankAccount(
        CashBankAccount(
          id: 'cash-val-001',
          businessId: testBusiness.id,
          name: 'Main Cash Register',
          accountType: CashBankAccountType.cash,
          openingBalancePaise: 10000000, // ₹1,00,000.00
          currentBalancePaise: 10000000,
          isDefault: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
    });

    tearDown(() async {
      await dbHelper.close();
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('1. Intra-State and Inter-State GST Calculation & Partial-to-Full Payments', () async {
      final now = DateTime.now().toUtc();
      final partyRepo = SqlitePartyRepository(dbHelper);
      final productRepo = SqliteProductRepository(dbHelper);
      final invoiceRepo = SqliteInvoiceRepository(dbHelper);
      final paymentRepo = SqlitePaymentRepository(dbHelper);

      // Create Intra-state customer (Maharashtra 27)
      final intraCustomer = await partyRepo.createParty(
        Party(
          id: 'cust-intra-001',
          businessId: testBusiness.id,
          partyType: PartyType.customer,
          name: 'Maharashtra Steels',
          billingStateCode: '27',
          billingStateName: 'Maharashtra',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Create Inter-state customer (Karnataka 29)
      final interCustomer = await partyRepo.createParty(
        Party(
          id: 'cust-inter-001',
          businessId: testBusiness.id,
          partyType: PartyType.customer,
          name: 'Bengaluru Tech Gears',
          billingStateCode: '29',
          billingStateName: 'Karnataka',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Create Product
      final product = await productRepo.createProduct(
        Product(
          id: 'prod-drill-001',
          businessId: testBusiness.id,
          name: 'Heavy Duty Drill Machine',
          sku: 'DRILL-HD-01',
          unitId: unitPcsId,
          taxRateId: taxRate18Id,
          sellingPricePaise: 1000000, // ₹10,000.00
          currentStock: 50.0,
          openingStock: 50.0,
          createdAt: now,
          updatedAt: now,
        ),
      );

      // A) Intra-State Invoice: ₹10,000 + 9% CGST (₹900) + 9% SGST (₹900) = ₹11,800
      final intraDraft = await invoiceRepo.saveDraft(
        Invoice(
          id: 'inv-intra-001',
          businessId: testBusiness.id,
          customerId: intraCustomer.id,
          invoiceNumber: '',
          placeOfSupplyStateCode: '27',
          invoiceDate: now,
          dueDate: now.add(const Duration(days: 30)),
          subtotalPaise: 1000000,
          discountPaise: 0,
          taxableAmountPaise: 1000000,
          cgstPaise: 90000,
          sgstPaise: 90000,
          igstPaise: 0,
          totalAmountPaise: 1180000,
          balanceAmountPaise: 1180000,
          items: [
            InvoiceItem(
              id: 'item-1',
              invoiceId: 'inv-intra-001',
              productId: product.id,
              productName: product.name,
              unitCode: 'PCS',
              ratePaise: 1000000,
              quantityScaled: 1000,
              taxRateId: taxRate18Id,
              cgstRateBasisPoints: 900,
              sgstRateBasisPoints: 900,
              taxableAmountPaise: 1000000,
              cgstAmountPaise: 90000,
              sgstAmountPaise: 90000,
              totalAmountPaise: 1180000,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );
      final finalizedIntra = await invoiceRepo.finalizeInvoice(intraDraft);
      expect(finalizedIntra.status, equals(InvoiceStatus.finalized));
      expect(finalizedIntra.cgstPaise, equals(90000));
      expect(finalizedIntra.sgstPaise, equals(90000));
      expect(finalizedIntra.igstPaise, equals(0));

      // Stock deducted from 50 to 49
      final prodAfterIntra = await productRepo.getProductById(product.id);
      expect(prodAfterIntra?.currentStock, equals(49.0));

      // Partial Payment: Pay ₹5,000.00
      final partialPay = await paymentRepo.postPayment(
        Payment(
          id: 'pay-part-001',
          businessId: testBusiness.id,
          customerId: intraCustomer.id,
          paymentNumber: 'PAY-P1',
          paymentDate: now,
          paymentMethod: PaymentMethod.cash,
          amountPaise: 500000,
          accountId: cashAccount.id,
          allocations: [
            PaymentAllocation(
              id: 'alloc-p1',
              paymentId: 'pay-part-001',
              documentId: finalizedIntra.id,
              allocatedAmountPaise: 500000,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(partialPay.status, equals(PaymentStatus.posted));

      // Verify invoice status is now PARTIAL with balance ₹6,800.00
      final invoiceAfterPartial = await invoiceRepo.getInvoiceById(finalizedIntra.id);
      expect(invoiceAfterPartial?.status, equals(InvoiceStatus.partiallyPaid));
      expect(invoiceAfterPartial?.paidAmountPaise, equals(500000));
      expect(invoiceAfterPartial?.balanceAmountPaise, equals(680000));

      // Remaining Payment: Pay ₹6,800.00
      await paymentRepo.postPayment(
        Payment(
          id: 'pay-full-002',
          businessId: testBusiness.id,
          customerId: intraCustomer.id,
          paymentNumber: 'PAY-P2',
          paymentDate: now,
          paymentMethod: PaymentMethod.cash,
          amountPaise: 680000,
          accountId: cashAccount.id,
          allocations: [
            PaymentAllocation(
              id: 'alloc-p2',
              paymentId: 'pay-full-002',
              documentId: finalizedIntra.id,
              allocatedAmountPaise: 680000,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Verify invoice status is now PAID with balance ₹0
      final invoiceAfterFull = await invoiceRepo.getInvoiceById(finalizedIntra.id);
      expect(invoiceAfterFull?.status, equals(InvoiceStatus.paid));
      expect(invoiceAfterFull?.balanceAmountPaise, equals(0));

      // B) Inter-State Invoice: ₹10,000 + 18% IGST (₹1,800) = ₹11,800
      final interDraft = await invoiceRepo.saveDraft(
        Invoice(
          id: 'inv-inter-001',
          businessId: testBusiness.id,
          customerId: interCustomer.id,
          invoiceNumber: '',
          placeOfSupplyStateCode: '29',
          invoiceDate: now,
          dueDate: now.add(const Duration(days: 30)),
          subtotalPaise: 1000000,
          discountPaise: 0,
          taxableAmountPaise: 1000000,
          cgstPaise: 0,
          sgstPaise: 0,
          igstPaise: 180000,
          totalAmountPaise: 1180000,
          balanceAmountPaise: 1180000,
          items: [
            InvoiceItem(
              id: 'item-inter-1',
              invoiceId: 'inv-inter-001',
              productId: product.id,
              productName: product.name,
              unitCode: 'PCS',
              ratePaise: 1000000,
              quantityScaled: 1000,
              taxRateId: taxRate18Id,
              igstRateBasisPoints: 1800,
              taxableAmountPaise: 1000000,
              igstAmountPaise: 180000,
              totalAmountPaise: 1180000,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );
      final finalizedInter = await invoiceRepo.finalizeInvoice(interDraft);
      expect(finalizedInter.status, equals(InvoiceStatus.finalized));
      expect(finalizedInter.igstPaise, equals(180000));
      expect(finalizedInter.cgstPaise, equals(0));
      expect(finalizedInter.sgstPaise, equals(0));

      // Verify double-entry integrity
      final audit = await AccountingIntegrityService(dbHelper).runIntegrityAudit(testBusiness.id);
      expect(audit.isClean, isTrue);
    });

    test('2. Purchase & Supplier Payment Lifecycle with Stock & Balance Reconciliation', () async {
      final now = DateTime.now().toUtc();
      final partyRepo = SqlitePartyRepository(dbHelper);
      final productRepo = SqliteProductRepository(dbHelper);
      final purchaseRepo = SqlitePurchaseRepository(dbHelper);

      // Create Supplier
      final supplier = await partyRepo.createParty(
        Party(
          id: 'supp-val-001',
          businessId: testBusiness.id,
          partyType: PartyType.supplier,
          name: 'Steel Raw Materials Corp',
          billingStateCode: '27',
          billingStateName: 'Maharashtra',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Product with initial stock 10
      final product = await productRepo.createProduct(
        Product(
          id: 'prod-steel-bar',
          businessId: testBusiness.id,
          name: 'Steel Bars 12mm',
          unitId: unitPcsId,
          taxRateId: taxRate18Id,
          sellingPricePaise: 50000,
          purchasePricePaise: 30000, // ₹300.00
          currentStock: 10.0,
          openingStock: 10.0,
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Purchase 20 units @ ₹300 = ₹6,000 + 18% GST (₹1,080) = ₹7,080
      final draftPurchase = await purchaseRepo.saveDraft(
        Purchase(
          id: 'pur-val-001',
          businessId: testBusiness.id,
          supplierId: supplier.id,
          purchaseNumber: 'PO-VAL-001',
          purchaseDate: now,
          dueDate: now.add(const Duration(days: 30)),
          placeOfSupplyStateCode: '27',
          subtotalPaise: 600000,
          taxableAmountPaise: 600000,
          cgstPaise: 54000,
          sgstPaise: 54000,
          totalAmountPaise: 708000,
          balanceAmountPaise: 708000,
          items: [
            PurchaseItem(
              id: 'p-item-1',
              purchaseId: 'pur-val-001',
              productId: product.id,
              productName: product.name,
              quantityScaled: 20000, // 20 units
              unitCode: 'PCS',
              purchaseRatePaise: 30000,
              taxableAmountPaise: 600000,
              taxRateId: taxRate18Id,
              cgstAmountPaise: 54000,
              sgstAmountPaise: 54000,
              totalAmountPaise: 708000,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );

      final finalizedPurchase = await purchaseRepo.finalizePurchase(draftPurchase);
      expect(finalizedPurchase.status, equals(PurchaseStatus.finalized));

      // Stock should have increased from 10 to 30
      final updatedProduct = await productRepo.getProductById(product.id);
      expect(updatedProduct?.currentStock, equals(30.0));

      // Verify Accounting Integrity
      final audit = await AccountingIntegrityService(dbHelper).runIntegrityAudit(testBusiness.id);
      expect(audit.isClean, isTrue);
      expect(audit.payablesReconciled, isTrue);
    });

    test('3. Expense Posting, Ledger Reconciliation & Cancellation Reversals', () async {
      final now = DateTime.now().toUtc();
      final expenseRepo = SqliteExpenseRepository(dbHelper);
      final categories = await expenseRepo.getCategories(testBusiness.id);
      final utilityCat = categories.firstWhere((c) => c.name.toLowerCase().contains('util') || c.name.toLowerCase().contains('elect'));

      final draftExp = await expenseRepo.createDraft(
        Expense(
          id: 'exp-util-001',
          businessId: testBusiness.id,
          categoryId: utilityCat.id,
          expenseDate: now,
          payee: 'Electricity Board',
          description: 'Factory Power Bill',
          taxableAmountPaise: 250000, // ₹2,500.00
          totalGstPaise: 0,
          totalAmountPaise: 250000,
          paymentAccountId: cashAccount.id,
          status: ExpenseStatus.draft,
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Post expense
      final postedExp = await expenseRepo.postExpense(draftExp.id, paymentAccountId: cashAccount.id);
      expect(postedExp.status, equals(ExpenseStatus.posted));

      // Verify audit passed
      var audit = await AccountingIntegrityService(dbHelper).runIntegrityAudit(testBusiness.id);
      expect(audit.isClean, isTrue);
      expect(audit.expensesReconciled, isTrue);

      // Cancel expense and verify reversal
      final cancelledExp = await expenseRepo.cancelExpense(postedExp.id, reason: 'Duplicate billing voucher');
      expect(cancelledExp.status, equals(ExpenseStatus.cancelled));

      audit = await AccountingIntegrityService(dbHelper).runIntegrityAudit(testBusiness.id);
      expect(audit.isClean, isTrue);
    });

    test('4. Recurring Invoices: Profile Creation, Next-Run Date, & Idempotency', () async {
      final now = DateTime.now().toUtc();
      final partyRepo = SqlitePartyRepository(dbHelper);
      final recurringRepo = SqliteRecurringInvoiceRepository(dbHelper);

      final client = await partyRepo.createParty(
        Party(
          id: 'cust-rec-001',
          businessId: testBusiness.id,
          partyType: PartyType.customer,
          name: 'Annual Maintenance Client',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final nextMonth = DateTime.utc(now.year, now.month + 1, now.day);
      final profile = await recurringRepo.createProfile(
        RecurringInvoice(
          id: 'rec-prof-001',
          businessId: testBusiness.id,
          customerId: client.id,
          profileName: 'Monthly AMC Support',
          frequency: RecurringFrequency.monthly,
          status: RecurringInvoiceStatus.active,
          startDate: now,
          nextRunDate: nextMonth,
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(profile.frequency, equals(RecurringFrequency.monthly));
      expect(profile.status, equals(RecurringInvoiceStatus.active));
      expect(profile.nextRunDate.isAfter(now), isTrue);

      // Fetch active profiles
      final activeProfiles = await recurringRepo.getProfilesByBusiness(testBusiness.id);
      expect(activeProfiles.any((p) => p.id == 'rec-prof-001'), isTrue);
    });

    test('5. Backup & Restore Negative Safety: Tampered files & Business Mismatch Protection', () async {
      final backupRepo = SqliteBackupRepository(dbHelper: dbHelper);
      final backupService = BackupService(
        backupRepository: backupRepo,
        pathProvider: pathProvider,
        dbHelper: dbHelper,
      );

      final validBackupFile = await backupService.createBackup(business: testBusiness);
      expect(validBackupFile.existsSync(), isTrue);

      final restoreService = RestoreService(
        dbHelper: dbHelper,
        pathProvider: pathProvider,
      );

      // A) Corrupted / Tampered file validation
      final corruptedFile = File(p.join(await pathProvider.getBackupsDirectory(), 'corrupted.billzobak'));
      await corruptedFile.writeAsBytes([0x50, 0x4B, 0x03, 0x04, 0x00, 0xFF, 0xEE]); // Invalid truncated ZIP

      expect(
        () async => await restoreService.inspectAndValidateBackup(corruptedFile.path),
        throwsA(isA<BackupCorruptedException>()),
      );

      // B) Multi-Business Isolation Protection (Restore to wrong business ID blocked)
      expect(
        () async => await restoreService.executeRestore(
          backupFilePath: validBackupFile.path,
          currentBusinessId: 'DIFFERENT_BUSINESS_ID_999',
        ),
        throwsA(isA<CrossBusinessRestoreMismatchException>()),
      );
    });

    test('6. Database Performance & Rapid Batch Inserts under SQLite WAL Mode', () async {
      final now = DateTime.now().toUtc();
      final partyRepo = SqlitePartyRepository(dbHelper);
      final productRepo = SqliteProductRepository(dbHelper);

      final stopwatch = Stopwatch()..start();

      // Insert 25 customers
      for (int i = 0; i < 25; i++) {
        await partyRepo.createParty(
          Party(
            id: 'perf-cust-$i',
            businessId: testBusiness.id,
            partyType: PartyType.customer,
            name: 'Bulk Customer #$i',
            phone: '98123456${i.toString().padLeft(2, '0')}',
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      // Insert 25 products
      for (int i = 0; i < 25; i++) {
        await productRepo.createProduct(
          Product(
            id: 'perf-prod-$i',
            businessId: testBusiness.id,
            name: 'Catalog Item #$i',
            unitId: unitPcsId,
            taxRateId: taxRate18Id,
            sellingPricePaise: 10000 + i * 500,
            currentStock: 100.0,
            openingStock: 100.0,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      stopwatch.stop();

      // Query verification
      final customers = await partyRepo.getParties(businessId: testBusiness.id);
      final products = await productRepo.getProducts(businessId: testBusiness.id);

      expect(customers.length, greaterThanOrEqualTo(25));
      expect(products.length, greaterThanOrEqualTo(25));
      expect(stopwatch.elapsedMilliseconds, lessThan(10000), reason: 'Batch insertion of 50 records must execute smoothly in WAL mode');
    });
  });
}
