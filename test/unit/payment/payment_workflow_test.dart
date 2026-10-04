import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/domain/payment/payment.dart';
import 'package:billzo/domain/payment/payment_allocation.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/domain/payment/payment_status.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/invoice/invoice_item.dart';
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
  late SqlitePaymentRepository paymentRepo;
  late SqliteProductRepository productRepo;

  late Business business;
  late Party customer;
  late Product testProduct;
  late String taxRate0Id;
  late CashBankAccount defaultCashAcc;
  late CashBankAccount defaultBankAcc;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_payment_workflow_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );

    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    partyRepo = SqlitePartyRepository(dbHelper);
    invoiceRepo = SqliteInvoiceRepository(dbHelper);
    paymentRepo = SqlitePaymentRepository(dbHelper);
    productRepo = SqliteProductRepository(dbHelper);

    final now = DateTime.now().toUtc();

    // 1. Create Business
    business = await businessRepo.createBusiness(
      Business(
        id: 'biz-payment-test',
        name: 'Billzo Tech Pvt Ltd',
        tradeName: 'Billzo Tech',
        phone: '9876543210',
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

    // Seed service item
    testProduct = await productRepo.createProduct(
      Product(
        id: 'prod-test-svc',
        businessId: business.id,
        name: 'Consulting Service',
        itemType: ItemType.service,
        sellingPricePaise: 100000,
        purchasePricePaise: 0,
        currentStock: 0.0,
        openingStock: 0.0,
        unitId: unitPcsId,
        taxRateId: taxRate0Id,
        createdAt: now,
        updatedAt: now,
      ),
    );

    // 2. Create Customer
    customer = await partyRepo.createParty(
      Party(
        id: 'cust-payment-test',
        businessId: business.id,
        partyType: PartyType.customer,
        name: 'Nexus Corp',
        phone: '9876543210',
        billingStateCode: '27',
        billingStateName: 'Maharashtra',
        currentBalancePaise: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );

    // 3. Retrieve default holding accounts seeded by Migration 003
    final accounts = await paymentRepo.getCashBankAccounts(business.id);
    defaultCashAcc = accounts.firstWhere((a) => a.accountType == CashBankAccountType.cash);
    defaultBankAcc = accounts.firstWhere((a) => a.accountType == CashBankAccountType.bank);
  });

  tearDown(() async {
    await dbHelper.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Helper to create and finalize an invoice
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

  group('Customer Payments Workflow Tests', () {
    test('Full payment transitions invoice to PAID and zeroes customer balance', () async {
      // 1. Finalize ₹10,000 invoice (1,000,000 paise)
      final invoice = await createFinalizedInvoice(
        invoiceId: 'inv-full-1',
        amountPaise: 1000000,
      );

      // Verify customer balance debited on invoice finalization
      var cust = await partyRepo.getPartyById(customer.id);
      expect(cust!.currentBalancePaise, equals(1000000));

      // 2. Post full ₹10,000 payment in Cash
      final now = DateTime.now().toUtc();
      final payment = Payment(
        id: 'pay-full-1',
        businessId: business.id,
        customerId: customer.id,
        paymentNumber: '',
        paymentDate: now,
        paymentMethod: PaymentMethod.cash,
        amountPaise: 1000000,
        accountId: defaultCashAcc.id,
        status: PaymentStatus.posted,
        allocations: [
          PaymentAllocation(
            id: 'alloc-full-1',
            paymentId: 'pay-full-1',
            documentId: invoice.id,
            documentType: 'TAX_INVOICE',
            allocatedAmountPaise: 1000000,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      final postedPayment = await paymentRepo.postPayment(payment);

      // Verify payment attributes
      expect(postedPayment.status, equals(PaymentStatus.posted));
      expect(postedPayment.paymentNumber, contains('PAY-'));
      expect(postedPayment.amountPaise, equals(1000000));
      expect(postedPayment.isFullyAllocated, isTrue);

      // Verify invoice status updated to Paid
      final updatedInvoice = await invoiceRepo.getInvoiceById(invoice.id);
      expect(updatedInvoice!.status, equals(InvoiceStatus.paid));
      expect(updatedInvoice.paidAmountPaise, equals(1000000));
      expect(updatedInvoice.balanceAmountPaise, equals(0));

      // Verify customer outstanding balance updated to 0
      cust = await partyRepo.getPartyById(customer.id);
      expect(cust!.currentBalancePaise, equals(0));

      // Verify cash account balance increased by ₹10,000
      final updatedCashAcc = await paymentRepo.getCashBankAccountById(defaultCashAcc.id);
      expect(updatedCashAcc!.currentBalancePaise, equals(1000000));

      // Verify balanced double-entry accounting ledger entries
      final db = await dbHelper.database;
      final ledgerEntries = await db.rawQuery('''
        SELECT le.*, la.code as account_code
        FROM ledger_entries le
        JOIN ledger_accounts la ON le.account_id = la.id
        WHERE le.transaction_id = ?
      ''', [postedPayment.id]);

      expect(ledgerEntries.length, equals(2));
      int totalDebits = 0;
      int totalCredits = 0;

      for (final entry in ledgerEntries) {
        final debit = entry['debit_paise'] as int;
        final credit = entry['credit_paise'] as int;
        totalDebits += debit;
        totalCredits += credit;

        final accNumber = entry['account_code'] as String;
        if (accNumber == '1010') {
          // Cash on Hand: Debited
          expect(debit, equals(1000000));
          expect(credit, equals(0));
        } else if (accNumber == '1100') {
          // Accounts Receivable: Credited
          expect(debit, equals(0));
          expect(credit, equals(1000000));
        }
      }

      expect(totalDebits, equals(totalCredits));
      expect(totalDebits, equals(1000000));
    });

    test('Partial payments update invoice to PARTIALLY_PAID then PAID sequentially', () async {
      // 1. Finalize ₹10,000 invoice (1,000,000 paise)
      final invoice = await createFinalizedInvoice(
        invoiceId: 'inv-part-1',
        amountPaise: 1000000,
      );

      final now = DateTime.now().toUtc();

      // 2. Post first partial payment of ₹4,000 (400,000 paise)
      final payment1 = Payment(
        id: 'pay-part-1',
        businessId: business.id,
        customerId: customer.id,
        paymentNumber: '',
        paymentDate: now,
        paymentMethod: PaymentMethod.bankTransfer,
        amountPaise: 400000,
        accountId: defaultBankAcc.id,
        referenceNumber: 'UTR-100234',
        status: PaymentStatus.posted,
        allocations: [
          PaymentAllocation(
            id: 'alloc-part-1',
            paymentId: 'pay-part-1',
            documentId: invoice.id,
            documentType: 'TAX_INVOICE',
            allocatedAmountPaise: 400000,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await paymentRepo.postPayment(payment1);

      // Verify invoice status is partiallyPaid with ₹6,000 balance
      var inv = await invoiceRepo.getInvoiceById(invoice.id);
      expect(inv!.status, equals(InvoiceStatus.partiallyPaid));
      expect(inv.paidAmountPaise, equals(400000));
      expect(inv.balanceAmountPaise, equals(600000));

      // Customer balance is ₹6,000
      var cust = await partyRepo.getPartyById(customer.id);
      expect(cust!.currentBalancePaise, equals(600000));

      // Bank account balance is ₹4,000
      var bankAcc = await paymentRepo.getCashBankAccountById(defaultBankAcc.id);
      expect(bankAcc!.currentBalancePaise, equals(400000));

      // 3. Post second payment of remaining ₹6,000 (600,000 paise)
      final payment2 = Payment(
        id: 'pay-part-2',
        businessId: business.id,
        customerId: customer.id,
        paymentNumber: '',
        paymentDate: now,
        paymentMethod: PaymentMethod.upi,
        amountPaise: 600000,
        accountId: defaultBankAcc.id,
        referenceNumber: 'UPI-987654',
        status: PaymentStatus.posted,
        allocations: [
          PaymentAllocation(
            id: 'alloc-part-2',
            paymentId: 'pay-part-2',
            documentId: invoice.id,
            documentType: 'TAX_INVOICE',
            allocatedAmountPaise: 600000,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await paymentRepo.postPayment(payment2);

      // Verify invoice status is now Paid with ₹0 balance
      inv = await invoiceRepo.getInvoiceById(invoice.id);
      expect(inv!.status, equals(InvoiceStatus.paid));
      expect(inv.paidAmountPaise, equals(1000000));
      expect(inv.balanceAmountPaise, equals(0));

      // Customer balance is 0
      cust = await partyRepo.getPartyById(customer.id);
      expect(cust!.currentBalancePaise, equals(0));

      // Bank balance is now ₹10,000
      bankAcc = await paymentRepo.getCashBankAccountById(defaultBankAcc.id);
      expect(bankAcc!.currentBalancePaise, equals(1000000));
    });

    test('Single payment allocated across multiple invoices', () async {
      // Finalize 2 separate invoices for the customer:
      // Invoice A: ₹5,000 (500,000 paise)
      final invA = await createFinalizedInvoice(
        invoiceId: 'inv-multi-a',
        amountPaise: 500000,
      );
      // Invoice B: ₹7,000 (700,000 paise)
      final invB = await createFinalizedInvoice(
        invoiceId: 'inv-multi-b',
        amountPaise: 700000,
      );

      // Customer total outstanding: ₹12,000 (1,200,000 paise)
      var cust = await partyRepo.getPartyById(customer.id);
      expect(cust!.currentBalancePaise, equals(1200000));

      // Single payment of ₹12,000 covering both invoices
      final now = DateTime.now().toUtc();
      final payment = Payment(
        id: 'pay-multi-1',
        businessId: business.id,
        customerId: customer.id,
        paymentNumber: '',
        paymentDate: now,
        paymentMethod: PaymentMethod.bankTransfer,
        amountPaise: 1200000,
        accountId: defaultBankAcc.id,
        status: PaymentStatus.posted,
        allocations: [
          PaymentAllocation(
            id: 'alloc-multi-a',
            paymentId: 'pay-multi-1',
            documentId: invA.id,
            documentType: 'TAX_INVOICE',
            allocatedAmountPaise: 500000,
            createdAt: now,
            updatedAt: now,
          ),
          PaymentAllocation(
            id: 'alloc-multi-b',
            paymentId: 'pay-multi-1',
            documentId: invB.id,
            documentType: 'TAX_INVOICE',
            allocatedAmountPaise: 700000,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await paymentRepo.postPayment(payment);

      // Both invoices should now be PAID
      final updatedA = await invoiceRepo.getInvoiceById(invA.id);
      final updatedB = await invoiceRepo.getInvoiceById(invB.id);

      expect(updatedA!.status, equals(InvoiceStatus.paid));
      expect(updatedA.balanceAmountPaise, equals(0));

      expect(updatedB!.status, equals(InvoiceStatus.paid));
      expect(updatedB.balanceAmountPaise, equals(0));

      // Customer balance should be 0
      cust = await partyRepo.getPartyById(customer.id);
      expect(cust!.currentBalancePaise, equals(0));
    });

    test('Payment cancellation reverses allocations, ledger, invoice, and balances', () async {
      // 1. Create and finalize ₹10,000 invoice
      final invoice = await createFinalizedInvoice(
        invoiceId: 'inv-cancel-test',
        amountPaise: 1000000,
      );

      // 2. Post ₹4,000 partial payment
      final now = DateTime.now().toUtc();
      final payment = Payment(
        id: 'pay-to-cancel',
        businessId: business.id,
        customerId: customer.id,
        paymentNumber: '',
        paymentDate: now,
        paymentMethod: PaymentMethod.cash,
        amountPaise: 400000,
        accountId: defaultCashAcc.id,
        status: PaymentStatus.posted,
        allocations: [
          PaymentAllocation(
            id: 'alloc-to-cancel',
            paymentId: 'pay-to-cancel',
            documentId: invoice.id,
            documentType: 'TAX_INVOICE',
            allocatedAmountPaise: 400000,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      final posted = await paymentRepo.postPayment(payment);

      // Verify state before cancellation
      var inv = await invoiceRepo.getInvoiceById(invoice.id);
      expect(inv!.status, equals(InvoiceStatus.partiallyPaid));
      expect(inv.balanceAmountPaise, equals(600000));

      var cust = await partyRepo.getPartyById(customer.id);
      expect(cust!.currentBalancePaise, equals(600000));

      var cashAcc = await paymentRepo.getCashBankAccountById(defaultCashAcc.id);
      expect(cashAcc!.currentBalancePaise, equals(400000));

      // 3. Cancel the payment
      final cancelled = await paymentRepo.cancelPayment(
        posted.id,
        cancellationReason: 'Cheque bounced / payment reversed',
      );

      expect(cancelled.status, equals(PaymentStatus.cancelled));
      expect(cancelled.cancellationReason, equals('Cheque bounced / payment reversed'));
      expect(cancelled.cancelledAt, isNotNull);

      // Verify invoice balance and status restored
      inv = await invoiceRepo.getInvoiceById(invoice.id);
      expect(inv!.status, equals(InvoiceStatus.finalized));
      expect(inv.paidAmountPaise, equals(0));
      expect(inv.balanceAmountPaise, equals(1000000));

      // Verify customer balance restored to ₹10,000
      cust = await partyRepo.getPartyById(customer.id);
      expect(cust!.currentBalancePaise, equals(1000000));

      // Verify cash balance restored to 0
      cashAcc = await paymentRepo.getCashBankAccountById(defaultCashAcc.id);
      expect(cashAcc!.currentBalancePaise, equals(0));

      // Verify reversing double-entry ledger entries exist and balance
      final db = await dbHelper.database;
      final reversingEntries = await db.rawQuery('''
        SELECT le.*, la.code as account_code
        FROM ledger_entries le
        JOIN ledger_accounts la ON le.account_id = la.id
        WHERE le.transaction_id = ? AND le.transaction_type = 'PAYMENT_CANCELLATION'
      ''', [posted.id]);

      expect(reversingEntries.length, equals(2));
      int revDebits = 0;
      int revCredits = 0;

      for (final entry in reversingEntries) {
        final d = entry['debit_paise'] as int;
        final c = entry['credit_paise'] as int;
        revDebits += d;
        revCredits += c;

        final accNumber = entry['account_code'] as String;
        if (accNumber == '1100') {
          // Accounts Receivable restored (debited)
          expect(d, equals(400000));
          expect(c, equals(0));
        } else if (accNumber == '1010') {
          // Cash on Hand restored (credited)
          expect(d, equals(0));
          expect(c, equals(400000));
        }
      }

      expect(revDebits, equals(revCredits));
      expect(revDebits, equals(400000));
    });
  });
}
