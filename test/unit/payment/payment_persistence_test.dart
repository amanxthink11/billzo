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

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_payment_persist_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('Payments, allocations, and holding accounts survive complete application restart simulation', () async {
    final diskDbPath = '${tempDir.path}${Platform.pathSeparator}restart_payment_test.db';

    // ==========================================
    // SESSION 1: Initial Setup and First Payment
    // ==========================================
    final helper1 = DatabaseHelper.createForTesting(
      dbPath: diskDbPath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );
    final bizRepo1 = SqliteBusinessRepository(dbHelper: helper1);
    final partyRepo1 = SqlitePartyRepository(helper1);
    final productRepo1 = SqliteProductRepository(helper1);
    final invoiceRepo1 = SqliteInvoiceRepository(helper1);
    final paymentRepo1 = SqlitePaymentRepository(helper1);

    final biz = await bizRepo1.createBusiness(
      Business(
        id: 'biz-persist-test',
        name: 'Persistent Dynamics Ltd',
        tradeName: 'Persistent Dyn',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    final db1 = await helper1.database;
    final taxRateRows = await db1.query('tax_rates', where: 'business_id = ?', whereArgs: [biz.id]);
    final taxRate0Id = taxRateRows.firstWhere((r) => r['rate_basis_points'] == 0)['id'] as String;

    final unitRows = await db1.query('units', where: 'business_id = ?', whereArgs: [biz.id]);
    final unitPcsId = unitRows.firstWhere((u) => u['code'] == 'PCS')['id'] as String;

    final customer = await partyRepo1.createParty(
      Party(
        id: 'cust-persist-1',
        businessId: biz.id,
        partyType: PartyType.customer,
        name: 'Acme Heavy Industries',
        phone: '9888877777',
        billingStateCode: '27',
        billingStateName: 'Maharashtra',
        currentBalancePaise: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    final service = await productRepo1.createProduct(
      Product(
        id: 'prod-persist-1',
        businessId: biz.id,
        name: 'Enterprise Maintenance SLA',
        itemType: ItemType.service,
        sellingPricePaise: 1000000, // ₹10,000.00
        purchasePricePaise: 0,
        currentStock: 0.0,
        openingStock: 0.0,
        unitId: unitPcsId,
        taxRateId: taxRate0Id,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    final invoice = Invoice(
      id: 'inv-persist-1',
      businessId: biz.id,
      invoiceNumber: 'DRAFT',
      customerId: customer.id,
      customerName: customer.name,
      invoiceDate: DateTime.now().toUtc(),
      dueDate: DateTime.now().toUtc().add(const Duration(days: 30)),
      placeOfSupplyStateCode: '27',
      status: InvoiceStatus.draft,
      subtotalPaise: 1000000,
      taxableAmountPaise: 1000000,
      totalAmountPaise: 1000000,
      balanceAmountPaise: 1000000,
      items: [
        InvoiceItem(
          id: 'item-persist-1',
          invoiceId: 'inv-persist-1',
          productId: service.id,
          productName: service.name,
          taxRateId: taxRate0Id,
          quantityScaled: 1000,
          unitCode: 'PCS',
          ratePaise: 1000000,
          discountPaise: 0,
          taxableAmountPaise: 1000000,
          cgstRateBasisPoints: 0,
          sgstRateBasisPoints: 0,
          cgstAmountPaise: 0,
          sgstAmountPaise: 0,
          totalAmountPaise: 1000000,
          trackInventory: false,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      ],
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );

    final savedDraft = await invoiceRepo1.saveDraft(invoice);
    final finalizedInvoice = await invoiceRepo1.finalizeInvoice(savedDraft);
    expect(finalizedInvoice.status, equals(InvoiceStatus.finalized));

    final accounts1 = await paymentRepo1.getCashBankAccounts(biz.id);
    final bankAcc1 = accounts1.firstWhere((a) => a.accountType == CashBankAccountType.bank);
    final cashAcc1 = accounts1.firstWhere((a) => a.accountType == CashBankAccountType.cash);

    final now1 = DateTime.now().toUtc();
    final payment1 = Payment(
      id: 'pay-persist-1',
      businessId: biz.id,
      customerId: customer.id,
      paymentNumber: '',
      paymentDate: now1,
      paymentMethod: PaymentMethod.bankTransfer,
      amountPaise: 600000, // ₹6,000.00
      accountId: bankAcc1.id,
      referenceNumber: 'NEFT-PERSIST-101',
      notes: 'First milestone tranche',
      status: PaymentStatus.posted,
      allocations: [
        PaymentAllocation(
          id: 'alloc-persist-1',
          paymentId: 'pay-persist-1',
          documentId: finalizedInvoice.id,
          documentType: 'TAX_INVOICE',
          allocatedAmountPaise: 600000,
          createdAt: now1,
          updatedAt: now1,
        ),
      ],
      createdAt: now1,
      updatedAt: now1,
    );

    final posted1 = await paymentRepo1.postPayment(payment1);
    expect(posted1.paymentNumber, contains('PAY-'));
    final payNumber1 = posted1.paymentNumber;

    // Verify Session 1 in-flight state
    var cust1 = await partyRepo1.getPartyById(customer.id);
    expect(cust1!.currentBalancePaise, equals(400000));

    // Terminate Session 1
    await helper1.close();

    // ==========================================
    // SESSION 2: Reopen from disk, verify and post 2nd payment
    // ==========================================
    final helper2 = DatabaseHelper.createForTesting(
      dbPath: diskDbPath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );
    final partyRepo2 = SqlitePartyRepository(helper2);
    final invoiceRepo2 = SqliteInvoiceRepository(helper2);
    final paymentRepo2 = SqlitePaymentRepository(helper2);

    // 1. Verify Payment 1 persisted
    final retrievedPay1 = await paymentRepo2.getPaymentById(posted1.id);
    expect(retrievedPay1, isNotNull);
    expect(retrievedPay1!.paymentNumber, equals(payNumber1));
    expect(retrievedPay1.amountPaise, equals(600000));
    expect(retrievedPay1.referenceNumber, equals('NEFT-PERSIST-101'));
    expect(retrievedPay1.status, equals(PaymentStatus.posted));
    expect(retrievedPay1.allocations.length, equals(1));
    expect(retrievedPay1.allocations.first.allocatedAmountPaise, equals(600000));

    // 2. Verify Invoice state persisted
    final inv2 = await invoiceRepo2.getInvoiceById(finalizedInvoice.id);
    expect(inv2!.status, equals(InvoiceStatus.partiallyPaid));
    expect(inv2.paidAmountPaise, equals(600000));
    expect(inv2.balanceAmountPaise, equals(400000));

    // 3. Verify Customer balance persisted
    final cust2 = await partyRepo2.getPartyById(customer.id);
    expect(cust2!.currentBalancePaise, equals(400000));

    // 4. Verify Bank Account balance persisted
    final bank2 = await paymentRepo2.getCashBankAccountById(bankAcc1.id);
    expect(bank2!.currentBalancePaise, equals(600000));

    // 5. Post second payment of remaining ₹4,000 in cash during Session 2
    final now2 = DateTime.now().toUtc();
    final payment2 = Payment(
      id: 'pay-persist-2',
      businessId: biz.id,
      customerId: customer.id,
      paymentNumber: '',
      paymentDate: now2,
      paymentMethod: PaymentMethod.cash,
      amountPaise: 400000,
      accountId: cashAcc1.id,
      status: PaymentStatus.posted,
      allocations: [
        PaymentAllocation(
          id: 'alloc-persist-2',
          paymentId: 'pay-persist-2',
          documentId: finalizedInvoice.id,
          documentType: 'TAX_INVOICE',
          allocatedAmountPaise: 400000,
          createdAt: now2,
          updatedAt: now2,
        ),
      ],
      createdAt: now2,
      updatedAt: now2,
    );

    final posted2 = await paymentRepo2.postPayment(payment2);
    expect(posted2.paymentNumber, contains('PAY-'));
    final payNumber2 = posted2.paymentNumber;
    expect(payNumber2, isNot(equals(payNumber1)));

    // Terminate Session 2
    await helper2.close();

    // ==========================================
    // SESSION 3: Reopen again, verify full integrity
    // ==========================================
    final helper3 = DatabaseHelper.createForTesting(
      dbPath: diskDbPath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );
    final partyRepo3 = SqlitePartyRepository(helper3);
    final invoiceRepo3 = SqliteInvoiceRepository(helper3);
    final paymentRepo3 = SqlitePaymentRepository(helper3);

    // Verify Invoice is now fully PAID with 0 balance
    final inv3 = await invoiceRepo3.getInvoiceById(finalizedInvoice.id);
    expect(inv3!.status, equals(InvoiceStatus.paid));
    expect(inv3.paidAmountPaise, equals(1000000));
    expect(inv3.balanceAmountPaise, equals(0));

    // Verify Customer balance is 0
    final cust3 = await partyRepo3.getPartyById(customer.id);
    expect(cust3!.currentBalancePaise, equals(0));

    // Verify Accounts
    final bank3 = await paymentRepo3.getCashBankAccountById(bankAcc1.id);
    expect(bank3!.currentBalancePaise, equals(600000));

    final cash3 = await paymentRepo3.getCashBankAccountById(cashAcc1.id);
    expect(cash3!.currentBalancePaise, equals(400000));

    // Verify both payments present in listing
    final allPayments = await paymentRepo3.getPayments(businessId: biz.id);
    expect(allPayments.length, equals(2));

    await helper3.close();
  });
}
