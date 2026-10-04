import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/application/backup/restore_service.dart';
import 'package:billzo/application/reports/accounting_integrity_service.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/expense/expense.dart';
import 'package:billzo/domain/expense/expense_status.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_item.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/invoice/invoice_type.dart';
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
import 'package:billzo/domain/recurring/recurring_invoice_item.dart';
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
import 'package:billzo/infrastructure/services/pdf/invoice_pdf_service.dart';
import 'package:billzo/infrastructure/services/printing/esc_pos_receipt_formatter.dart';
import 'package:billzo/infrastructure/services/printing/printer_service.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

class SmokeTestPathProvider implements IAppPathProvider {
  final Directory rootDir;
  SmokeTestPathProvider(this.rootDir);

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

  group('Phase 10 Release Smoke Test — Complete Production Lifecycle', () {
    late Directory tempDir;
    late SmokeTestPathProvider pathProvider;
    late String dbFilePath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('billzo_release_smoke_');
      pathProvider = SmokeTestPathProvider(tempDir);
      dbFilePath = p.join(await pathProvider.getDatabaseDirectory(), 'billzo.db');
    });

    tearDown(() async {
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('Executes full 17-step lifecycle with double-entry integrity & zero data loss', () async {
      final now = DateTime.now().toUtc();

      // -----------------------------------------------------------------------
      // STEP 1: Launch Billzo (Database creation & migration)
      // -----------------------------------------------------------------------
      var dbHelper = DatabaseHelper.createForTesting(
        dbPath: dbFilePath,
        pathProvider: pathProvider,
        dbFactory: databaseFactoryFfi,
      );
      final initialDb = await dbHelper.database;
      expect(initialDb.isOpen, isTrue);
      expect(File(dbFilePath).existsSync(), isTrue);

      // -----------------------------------------------------------------------
      // STEP 2: Create & Open Business
      // -----------------------------------------------------------------------
      var businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
      final business = await businessRepo.createBusiness(
        Business(
          id: 'biz-smoke-prod',
          name: 'Billzo Tech Solutions',
          tradeName: 'Billzo Enterprise',
          gstin: '27AABCU9603R1ZM',
          pan: 'AABCU9603R',
          phone: '9876543210',
          email: 'billing@billzo.com',
          addressLine1: 'Office 101, Tech Park',
          city: 'Mumbai',
          stateCode: '27',
          stateName: 'Maharashtra',
          pincode: '400001',
          upiId: 'billzopay@okaxis',
          bankAccountName: 'Billzo Tech Solutions',
          bankAccountNumber: '9876543210001',
          bankIfsc: 'HDFC0000123',
          bankName: 'HDFC Bank',
          bankBranch: 'Mumbai Central',
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(business.id, equals('biz-smoke-prod'));

      // Fetch seeded units and tax rates
      final taxRateRows = await initialDb.query('tax_rates', where: 'business_id = ?', whereArgs: [business.id]);
      final taxRate18Id = taxRateRows.firstWhere((r) => r['rate_basis_points'] == 1800)['id'] as String;

      final unitRows = await initialDb.query('units', where: 'business_id = ?', whereArgs: [business.id]);
      final unitPcsId = unitRows.firstWhere((u) => u['code'] == 'PCS')['id'] as String;

      // -----------------------------------------------------------------------
      // STEP 3: Add Customer
      // -----------------------------------------------------------------------
      var partyRepo = SqlitePartyRepository(dbHelper);
      final customer = await partyRepo.createParty(
        Party(
          id: 'cust-smoke-1',
          businessId: business.id,
          partyType: PartyType.customer,
          name: 'Reliance Digital Retail',
          phone: '9822011111',
          email: 'accounts@reliancedigital.com',
          gstin: '27AABCR1234M1Z1',
          billingAddressLine1: 'Plot 45, MIDC',
          billingCity: 'Pune',
          billingStateCode: '27',
          billingStateName: 'Maharashtra',
          shippingStateCode: '27',
          shippingStateName: 'Maharashtra',
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(customer.name, equals('Reliance Digital Retail'));

      // -----------------------------------------------------------------------
      // STEP 4: Add Product
      // -----------------------------------------------------------------------
      var productRepo = SqliteProductRepository(dbHelper);
      final product = await productRepo.createProduct(
        Product(
          id: 'prod-smoke-1',
          businessId: business.id,
          name: 'Thermal Receipt Rolls 80mm',
          sku: 'ROL-80MM',
          hsnSacCode: '4811',
          itemType: ItemType.product,
          sellingPricePaise: 50000, // ₹500.00
          purchasePricePaise: 30000, // ₹300.00
          currentStock: 100.0,
          openingStock: 100.0,
          unitId: unitPcsId,
          taxRateId: taxRate18Id,
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(product.sellingPricePaise, equals(50000));

      // -----------------------------------------------------------------------
      // STEP 5: Create Invoice (Draft)
      // -----------------------------------------------------------------------
      var invoiceRepo = SqliteInvoiceRepository(dbHelper);
      final draftInvoice = await invoiceRepo.saveDraft(
        Invoice(
          id: 'inv-smoke-001',
          businessId: business.id,
          customerId: customer.id,
          invoiceNumber: '',
          invoiceType: InvoiceType.taxInvoice,
          placeOfSupplyStateCode: '27',
          invoiceDate: now,
          dueDate: now.add(const Duration(days: 15)),
          status: InvoiceStatus.draft,
          subtotalPaise: 50000,
          discountPaise: 0,
          taxableAmountPaise: 50000,
          cgstPaise: 4500, // 9%
          sgstPaise: 4500, // 9%
          igstPaise: 0,
          cessPaise: 0,
          roundOffPaise: 0,
          totalAmountPaise: 59000, // ₹590.00
          paidAmountPaise: 0,
          balanceAmountPaise: 59000,
          items: [
            InvoiceItem(
              id: 'item-smoke-1',
              invoiceId: 'inv-smoke-001',
              productId: product.id,
              productName: product.name,
              unitCode: 'PCS',
              ratePaise: 50000,
              quantityScaled: 1000, // 1 unit
              taxRateId: taxRate18Id,
              discountPaise: 0,
              cgstRateBasisPoints: 900,
              sgstRateBasisPoints: 900,
              taxableAmountPaise: 50000,
              cgstAmountPaise: 4500,
              sgstAmountPaise: 4500,
              igstAmountPaise: 0,
              cessAmountPaise: 0,
              totalAmountPaise: 59000,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(draftInvoice.status, equals(InvoiceStatus.draft));

      // -----------------------------------------------------------------------
      // STEP 6: Finalize Invoice (Post to ledger)
      // -----------------------------------------------------------------------
      final finalizedInvoice = await invoiceRepo.finalizeInvoice(draftInvoice);
      expect(finalizedInvoice.status, equals(InvoiceStatus.finalized));
      expect(finalizedInvoice.balanceAmountPaise, equals(59000));

      // -----------------------------------------------------------------------
      // STEP 7: Record Payment
      // -----------------------------------------------------------------------
      var paymentRepo = SqlitePaymentRepository(dbHelper);
      final cashBankAccounts = await paymentRepo.getCashBankAccounts(business.id);
      final cashAccount = cashBankAccounts.isNotEmpty
          ? cashBankAccounts.firstWhere((a) => a.accountType == CashBankAccountType.cash)
          : await paymentRepo.createCashBankAccount(
              CashBankAccount(
                id: 'cash-smoke-001',
                businessId: business.id,
                name: 'Cash Register',
                accountType: CashBankAccountType.cash,
                isDefault: true,
                createdAt: now,
                updatedAt: now,
              ),
            );

      final payment = await paymentRepo.postPayment(
        Payment(
          id: 'pay-smoke-001',
          businessId: business.id,
          customerId: customer.id,
          paymentNumber: 'PAY-2026-001',
          paymentDate: now,
          amountPaise: 59000,
          paymentMethod: PaymentMethod.cash,
          referenceNumber: 'CASH-REC-001',
          accountId: cashAccount.id,
          status: PaymentStatus.posted,
          allocations: [
            PaymentAllocation(
              id: 'alloc-smoke-1',
              paymentId: 'pay-smoke-001',
              documentId: finalizedInvoice.id,
              allocatedAmountPaise: 59000,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(payment.amountPaise, equals(59000));

      // Check invoice is now paid
      final paidInvoice = await invoiceRepo.getInvoiceById(finalizedInvoice.id);
      expect(paidInvoice?.status, equals(InvoiceStatus.paid));
      expect(paidInvoice?.balanceAmountPaise, equals(0));

      // -----------------------------------------------------------------------
      // STEP 8: Create Purchase
      // -----------------------------------------------------------------------
      final supplier = await partyRepo.createParty(
        Party(
          id: 'supp-smoke-1',
          businessId: business.id,
          partyType: PartyType.supplier,
          name: 'Paper Mills Ltd',
          phone: '9833022222',
          billingStateCode: '27',
          billingStateName: 'Maharashtra',
          createdAt: now,
          updatedAt: now,
        ),
      );

      var purchaseRepo = SqlitePurchaseRepository(dbHelper);
      final draftPurchase = await purchaseRepo.saveDraft(
        Purchase(
          id: 'pur-smoke-001',
          businessId: business.id,
          supplierId: supplier.id,
          purchaseNumber: 'PO-2026-001',
          supplierInvoiceNumber: 'SUP-INV-889',
          purchaseDate: now,
          dueDate: now.add(const Duration(days: 30)),
          placeOfSupplyStateCode: '27',
          status: PurchaseStatus.draft,
          subtotalPaise: 30000,
          discountPaise: 0,
          taxableAmountPaise: 30000,
          cgstPaise: 2700,
          sgstPaise: 2700,
          igstPaise: 0,
          cessPaise: 0,
          roundOffPaise: 0,
          totalAmountPaise: 35400,
          paidAmountPaise: 0,
          balanceAmountPaise: 35400,
          items: [
            PurchaseItem(
              id: 'pur-item-1',
              purchaseId: 'pur-smoke-001',
              productId: product.id,
              productName: product.name,
              quantityScaled: 1000,
              unitCode: 'PCS',
              purchaseRatePaise: 30000,
              discountPaise: 0,
              taxableAmountPaise: 30000,
              taxRateId: taxRate18Id,
              cgstAmountPaise: 2700,
              sgstAmountPaise: 2700,
              igstAmountPaise: 0,
              totalAmountPaise: 35400,
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

      // -----------------------------------------------------------------------
      // STEP 9: Create Expense
      // -----------------------------------------------------------------------
      var expenseRepo = SqliteExpenseRepository(dbHelper);
      final expCats = await expenseRepo.getCategories(business.id);
      final rentCategory = expCats.firstWhere((c) => c.name.toLowerCase().contains('rent'));

      final draftExpense = await expenseRepo.createDraft(
        Expense(
          id: 'exp-smoke-001',
          businessId: business.id,
          categoryId: rentCategory.id,
          expenseDate: now,
          payee: 'Tech Park Landlords',
          description: 'Head Office Monthly Rent',
          taxableAmountPaise: 1000000, // ₹10,000.00
          cgstPaise: 0,
          sgstPaise: 0,
          igstPaise: 0,
          totalGstPaise: 0,
          totalAmountPaise: 1000000,
          paymentMethod: PaymentMethod.cash,
          paymentAccountId: cashAccount.id,
          status: ExpenseStatus.draft,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final postedExpense = await expenseRepo.postExpense(
        draftExpense.id,
        paymentAccountId: cashAccount.id,
      );
      expect(postedExpense.status, equals(ExpenseStatus.posted));

      // -----------------------------------------------------------------------
      // STEP 10: Open Reports & Audit Accounting Integrity
      // -----------------------------------------------------------------------
      final integrityService = AccountingIntegrityService(dbHelper);
      final audit = await integrityService.runIntegrityAudit(business.id);

      expect(audit.isClean, isTrue, reason: 'Accounting integrity audit must pass all 6 verification checks');
      expect(audit.journalEntriesBalanced, isTrue);
      expect(audit.trialBalanceBalanced, isTrue);
      expect(audit.cashBankReconciled, isTrue);
      expect(audit.receivablesReconciled, isTrue);
      expect(audit.payablesReconciled, isTrue);
      expect(audit.expensesReconciled, isTrue);

      // -----------------------------------------------------------------------
      // STEP 11: Create Recurring Invoice Profile
      // -----------------------------------------------------------------------
      var recurringRepo = SqliteRecurringInvoiceRepository(dbHelper);
      final recurringProfile = await recurringRepo.createProfile(
        RecurringInvoice(
          id: 'rec-smoke-001',
          businessId: business.id,
          customerId: customer.id,
          profileName: 'Monthly Retainer - Reliance',
          frequency: RecurringFrequency.monthly,
          status: RecurringInvoiceStatus.active,
          startDate: now,
          nextRunDate: now.add(const Duration(days: 30)),
          notes: 'Standard recurring monthly invoice',
          items: [
            RecurringInvoiceItem(
              id: 'rec-item-1',
              recurringInvoiceId: 'rec-smoke-001',
              productId: product.id,
              taxRateId: taxRate18Id,
              productName: product.name,
              hsnSac: '4811',
              quantity: 2,
              unitCode: 'PCS',
              ratePaise: 50000,
              discountPaise: 0,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(recurringProfile.profileName, equals('Monthly Retainer - Reliance'));

      // -----------------------------------------------------------------------
      // STEP 12: Generate & Inspect PDF
      // -----------------------------------------------------------------------
      final pdfBytes = await InvoicePdfService.generateA4InvoicePdf(
        invoice: paidInvoice!,
        business: business,
        customer: customer,
      );
      expect(pdfBytes, isNotEmpty);
      final pdfHeader = utf8.decode(pdfBytes.sublist(0, 5));
      expect(pdfHeader, equals('%PDF-'), reason: 'Generated document must be a valid PDF format');

      // -----------------------------------------------------------------------
      // STEP 13: Open Print Preview / Thermal Receipt
      // -----------------------------------------------------------------------
      final thermalBytes = EscPosReceiptFormatter.generateReceiptBytes(
        invoice: paidInvoice,
        business: business,
        customer: customer,
        format: PrintFormat.thermal80mm,
      );
      expect(thermalBytes, isNotEmpty);

      // -----------------------------------------------------------------------
      // STEP 14: Create Backup (.billzobak)
      // -----------------------------------------------------------------------
      var backupRepo = SqliteBackupRepository(dbHelper: dbHelper);
      var backupService = BackupService(
        backupRepository: backupRepo,
        pathProvider: pathProvider,
        dbHelper: dbHelper,
      );

      final backupFile = await backupService.createBackup(
        business: business,
      );
      expect(backupFile.existsSync(), isTrue);

      // -----------------------------------------------------------------------
      // STEP 15: Restore Backup in Safe Test Environment
      // -----------------------------------------------------------------------
      final restoreTempDir = await Directory.systemTemp.createTemp('billzo_restore_smoke_');
      final restorePathProvider = SmokeTestPathProvider(restoreTempDir);
      final restoreDbPath = p.join(await restorePathProvider.getDatabaseDirectory(), 'billzo_restore.db');

      var restoreDbHelper = DatabaseHelper.createForTesting(
        dbPath: restoreDbPath,
        pathProvider: restorePathProvider,
        dbFactory: databaseFactoryFfi,
      );
      // Initialize target DB
      await restoreDbHelper.database;

      var restoreService = RestoreService(
        dbHelper: restoreDbHelper,
        pathProvider: restorePathProvider,
      );

      final restoreResult = await restoreService.executeRestore(
        backupFilePath: backupFile.path,
        currentBusinessId: business.id,
      );
      expect(restoreResult.manifest.businessId, equals(business.id));
      expect(restoreResult.safetySnapshotPath, isNotEmpty);

      // Verify integrity in restored database
      final restoredAudit = await AccountingIntegrityService(restoreDbHelper).runIntegrityAudit(business.id);
      expect(restoredAudit.isClean, isTrue);
      await restoreDbHelper.close();
      await restoreTempDir.delete(recursive: true);

      // -----------------------------------------------------------------------
      // STEP 16: Restart Application (Close DB & reopen fresh DatabaseHelper)
      // -----------------------------------------------------------------------
      await dbHelper.close();

      // Create new DatabaseHelper pointing to same file
      var reopenedDbHelper = DatabaseHelper.createForTesting(
        dbPath: dbFilePath,
        pathProvider: pathProvider,
        dbFactory: databaseFactoryFfi,
      );
      final reopenedDb = await reopenedDbHelper.database;
      expect(reopenedDb.isOpen, isTrue);

      // -----------------------------------------------------------------------
      // STEP 17: Confirm Data Persists & Accounting Integrity is Maintained
      // -----------------------------------------------------------------------
      var verifyBizRepo = SqliteBusinessRepository(dbHelper: reopenedDbHelper);
      var verifyPartyRepo = SqlitePartyRepository(reopenedDbHelper);
      var verifyProductRepo = SqliteProductRepository(reopenedDbHelper);
      var verifyInvoiceRepo = SqliteInvoiceRepository(reopenedDbHelper);
      var verifyPurchaseRepo = SqlitePurchaseRepository(reopenedDbHelper);
      var verifyExpenseRepo = SqliteExpenseRepository(reopenedDbHelper);
      var verifyRecurringRepo = SqliteRecurringInvoiceRepository(reopenedDbHelper);

      final persistedBiz = await verifyBizRepo.getActiveBusiness();
      expect(persistedBiz, isNotNull);
      expect(persistedBiz?.name, equals('Billzo Tech Solutions'));

      final persistedCustomer = await verifyPartyRepo.getPartyById(customer.id);
      expect(persistedCustomer, isNotNull);

      final persistedProduct = await verifyProductRepo.getProductById(product.id);
      expect(persistedProduct, isNotNull);

      final persistedInvoice = await verifyInvoiceRepo.getInvoiceById(draftInvoice.id);
      expect(persistedInvoice, isNotNull);
      expect(persistedInvoice?.status, equals(InvoiceStatus.paid));
      expect(persistedInvoice?.totalAmountPaise, equals(59000));

      final persistedPurchases = await verifyPurchaseRepo.getPurchases(businessId: business.id);
      expect(persistedPurchases.length, equals(1));
      expect(persistedPurchases.first.totalAmountPaise, equals(35400));

      final persistedExpenses = await verifyExpenseRepo.getExpenses(businessId: business.id);
      expect(persistedExpenses.length, equals(1));

      final persistedRecurring = await verifyRecurringRepo.getProfilesByBusiness(business.id);
      expect(persistedRecurring.length, equals(1));

      // Final double-entry accounting integrity check after restart
      final postRestartAudit = await AccountingIntegrityService(reopenedDbHelper).runIntegrityAudit(business.id);
      expect(postRestartAudit.isClean, isTrue);
      expect(postRestartAudit.issues, isEmpty);

      await reopenedDbHelper.close();
    });
  });
}
