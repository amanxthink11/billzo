import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_item.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/domain/payment/payment.dart';
import 'package:billzo/domain/payment/payment_allocation.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/domain/payment/payment_status.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_invoice_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_party_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_payment_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_product_repository.dart';
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
  late SqlitePartyRepository partyRepo;
  late SqliteInvoiceRepository invoiceRepo;
  late SqliteProductRepository productRepo;

  late Business business;
  late Party customer;
  late Product testProduct;
  late String taxRate0Id;
  late CashBankAccount defaultCashAcc;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_rollback_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );

    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    partyRepo = SqlitePartyRepository(dbHelper);
    invoiceRepo = SqliteInvoiceRepository(dbHelper);
    productRepo = SqliteProductRepository(dbHelper);

    final now = DateTime.now().toUtc();

    business = await businessRepo.createBusiness(
      Business(
        id: 'biz-rollback-test',
        name: 'Rollback Enterprises',
        tradeName: 'Rollback Ent',
        phone: '9988776655',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final db = await dbHelper.database;
    final taxRateRows = await db.query('tax_rates', where: 'business_id = ?', whereArgs: [business.id]);
    taxRate0Id = taxRateRows.firstWhere((r) => r['rate_basis_points'] == 0)['id'] as String;

    final unitRows = await db.query('units', where: 'business_id = ?', whereArgs: [business.id]);
    final unitPcsId = unitRows.firstWhere((u) => u['code'] == 'PCS')['id'] as String;

    testProduct = await productRepo.createProduct(
      Product(
        id: 'prod-rollback-svc',
        businessId: business.id,
        name: 'Annual Maintenance Service',
        itemType: ItemType.service,
        sellingPricePaise: 1000000,
        purchasePricePaise: 0,
        currentStock: 0.0,
        openingStock: 0.0,
        unitId: unitPcsId,
        taxRateId: taxRate0Id,
        createdAt: now,
        updatedAt: now,
      ),
    );

    customer = await partyRepo.createParty(
      Party(
        id: 'cust-rollback-test',
        businessId: business.id,
        partyType: PartyType.customer,
        name: 'Acme Global Ltd',
        phone: '9988776655',
        billingStateCode: '27',
        billingStateName: 'Maharashtra',
        currentBalancePaise: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final standardRepo = SqlitePaymentRepository(dbHelper);
    final accounts = await standardRepo.getCashBankAccounts(business.id);
    defaultCashAcc = accounts.firstWhere((a) => a.accountType == CashBankAccountType.cash);
  });

  tearDown(() async {
    await dbHelper.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<Invoice> createFinalizedInvoice({
    required String invoiceId,
    required int amountPaise,
  }) async {
    final now = DateTime.now().toUtc();
    final draft = Invoice(
      id: invoiceId,
      businessId: business.id,
      invoiceNumber: 'DRAFT',
      customerId: customer.id,
      customerName: customer.name,
      invoiceDate: now,
      dueDate: now.add(const Duration(days: 30)),
      placeOfSupplyStateCode: '27',
      status: InvoiceStatus.draft,
      subtotalPaise: amountPaise,
      taxableAmountPaise: amountPaise,
      totalAmountPaise: amountPaise,
      balanceAmountPaise: amountPaise,
      items: [
        InvoiceItem(
          id: 'item-$invoiceId',
          invoiceId: invoiceId,
          productId: testProduct.id,
          productName: testProduct.name,
          taxRateId: taxRate0Id,
          quantityScaled: 1000,
          unitCode: 'PCS',
          ratePaise: amountPaise,
          discountPaise: 0,
          taxableAmountPaise: amountPaise,
          cgstRateBasisPoints: 0,
          sgstRateBasisPoints: 0,
          cgstAmountPaise: 0,
          sgstAmountPaise: 0,
          totalAmountPaise: amountPaise,
          trackInventory: false,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    final savedDraft = await invoiceRepo.saveDraft(draft);
    return invoiceRepo.finalizeInvoice(savedDraft);
  }

  group('Payment Mandatory Transaction Rollback Tests', () {
    test('Simulated crash halfway through payment posting triggers 100% database rollback', () async {
      // 1. Finalize ₹10,000 invoice (1,000,000 paise)
      final invoice = await createFinalizedInvoice(
        invoiceId: 'inv-rb-1',
        amountPaise: 1000000,
      );

      // Verify baseline before payment attempt
      var custBefore = await partyRepo.getPartyById(customer.id);
      expect(custBefore!.currentBalancePaise, equals(1000000));

      final previewBefore = await SqlitePaymentRepository(dbHelper).getNextPaymentNumberPreview(business.id);

      final db = await dbHelper.database;
      final paymentsBefore = await db.query('payments');
      expect(paymentsBefore.isEmpty, isTrue);

      final allocationsBefore = await db.query('payment_allocations');
      expect(allocationsBefore.isEmpty, isTrue);

      final ledgerBefore = await db.query('ledger_entries', where: 'transaction_type = ?', whereArgs: ['PAYMENT']);
      expect(ledgerBefore.isEmpty, isTrue);

      // 2. Instantiate repository that throws right before transaction commit
      final failingRepo = SqlitePaymentRepository(
        dbHelper,
        onBeforePostCommitForTesting: (txn) async {
          throw Exception('CRASH_MIDWAY_SIMULATION: Disk I/O or power failure during payment write');
        },
      );

      final now = DateTime.now().toUtc();
      final doomedPayment = Payment(
        id: 'pay-doomed-1',
        businessId: business.id,
        customerId: customer.id,
        paymentNumber: '',
        paymentDate: now,
        paymentMethod: PaymentMethod.cash,
        amountPaise: 500000,
        accountId: defaultCashAcc.id,
        status: PaymentStatus.posted,
        allocations: [
          PaymentAllocation(
            id: 'alloc-doomed-1',
            paymentId: 'pay-doomed-1',
            documentId: invoice.id,
            documentType: 'TAX_INVOICE',
            allocatedAmountPaise: 500000,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      // 3. Execution must throw Exception
      expect(
        () async => await failingRepo.postPayment(doomedPayment),
        throwsA(isA<Exception>()),
      );

      // 4. Verify ZERO partial state after rollback
      // A. Zero partial payments created
      final paymentsAfter = await db.query('payments');
      expect(paymentsAfter.isEmpty, isTrue, reason: 'Zero payment records should exist after rollback');

      // B. No partial allocations
      final allocationsAfter = await db.query('payment_allocations');
      expect(allocationsAfter.isEmpty, isTrue, reason: 'No payment allocations should exist after rollback');

      // C. No orphan ledger entries
      final ledgerAfter = await db.query('ledger_entries', where: 'transaction_type = ?', whereArgs: ['PAYMENT']);
      expect(ledgerAfter.isEmpty, isTrue, reason: 'No orphan ledger entries should exist after rollback');

      // D. Customer balance unchanged
      final custAfter = await partyRepo.getPartyById(customer.id);
      expect(custAfter!.currentBalancePaise, equals(1000000), reason: 'Customer balance must remain 10,000');

      // E. Invoice balance and status unchanged
      final invoiceAfter = await invoiceRepo.getInvoiceById(invoice.id);
      expect(invoiceAfter!.status, equals(InvoiceStatus.finalized), reason: 'Invoice status must remain finalized');
      expect(invoiceAfter.paidAmountPaise, equals(0), reason: 'Invoice paid amount must remain 0');
      expect(invoiceAfter.balanceAmountPaise, equals(1000000), reason: 'Invoice balance must remain 10,000');

      // F. Cash account balance unchanged
      final cashAccAfter = await SqlitePaymentRepository(dbHelper).getCashBankAccountById(defaultCashAcc.id);
      expect(cashAccAfter!.currentBalancePaise, equals(0), reason: 'Cash balance must remain 0');

      // G. Sequence number unconsumed
      final previewAfter = await SqlitePaymentRepository(dbHelper).getNextPaymentNumberPreview(business.id);
      expect(previewAfter, equals(previewBefore), reason: 'Sequence number must not be consumed by failed payment');

      // 5. Verify healthy subsequent operation can use the exact unconsumed sequence
      final healthyRepo = SqlitePaymentRepository(dbHelper);
      final successfulPayment = await healthyRepo.postPayment(doomedPayment.copyWith(id: 'pay-healthy-1'));
      expect(successfulPayment.status, equals(PaymentStatus.posted));
      expect(successfulPayment.paymentNumber, equals(previewBefore));

      final updatedInvoice = await invoiceRepo.getInvoiceById(invoice.id);
      expect(updatedInvoice!.status, equals(InvoiceStatus.partiallyPaid));
      expect(updatedInvoice.balanceAmountPaise, equals(500000));
    });
  });
}
