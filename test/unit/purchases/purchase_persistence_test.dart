import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/domain/payment/payment.dart';
import 'package:billzo/domain/payment/payment_allocation.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/domain/payment/payment_status.dart';
import 'package:billzo/domain/purchase/itc_eligibility.dart';
import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_item.dart';
import 'package:billzo/domain/purchase/purchase_return.dart';
import 'package:billzo/domain/purchase/purchase_return_item.dart';
import 'package:billzo/domain/purchase/purchase_status.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_party_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_payment_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_product_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_purchase_repository.dart';
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
    tempDir = await Directory.systemTemp.createTemp('billzo_purchase_persistence_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('Purchases, items, supplier payments, and debit notes survive DB close & reopen', () async {
    final diskDbPath = '${tempDir.path}${Platform.pathSeparator}restart_purchase_test.db';
    final now = DateTime.now().toUtc();

    // 1. Initial Launch
    final helper1 = DatabaseHelper.createForTesting(
      dbPath: diskDbPath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );
    final bizRepo1 = SqliteBusinessRepository(dbHelper: helper1);
    final partyRepo1 = SqlitePartyRepository(helper1);
    final productRepo1 = SqliteProductRepository(helper1);
    final purchaseRepo1 = SqlitePurchaseRepository(helper1);
    final paymentRepo1 = SqlitePaymentRepository(helper1);

    final biz = await bizRepo1.createBusiness(
      Business(
        id: 'biz-persist-pur',
        name: 'Industrial Spares Corp',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final db1 = await helper1.database;
    final taxRateRows = await db1.query('tax_rates', where: 'business_id = ?', whereArgs: [biz.id]);
    final taxRate18Id = taxRateRows.firstWhere((r) => r['rate_basis_points'] == 1800)['id'] as String;

    final unitRows = await db1.query('units', where: 'business_id = ?', whereArgs: [biz.id]);
    final unitPcsId = unitRows.firstWhere((u) => u['code'] == 'PCS')['id'] as String;

    final supplier = await partyRepo1.createParty(
      Party(
        id: 'supp-persist-1',
        businessId: biz.id,
        partyType: PartyType.supplier,
        name: 'Bharat Heavy Bearings',
        phone: '9811223344',
        billingStateCode: '27',
        billingStateName: 'Maharashtra',
        currentBalancePaise: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final product = await productRepo1.createProduct(
      Product(
        id: 'prod-persist-bearing',
        businessId: biz.id,
        name: 'Roller Bearing 6205',
        sku: 'BRG-6205',
        itemType: ItemType.product,
        sellingPricePaise: 200000,
        purchasePricePaise: 100000, // ₹1,000.00
        currentStock: 10.0,
        openingStock: 10.0,
        unitId: unitPcsId,
        taxRateId: taxRate18Id,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final bankAcc = await paymentRepo1.createCashBankAccount(
      CashBankAccount(
        id: 'acc-persist-bank',
        businessId: biz.id,
        name: 'State Bank Current A/C',
        accountType: CashBankAccountType.bank,
        openingBalancePaise: 5000000, // ₹50,000.00
        currentBalancePaise: 5000000,
        isDefault: true,
        createdAt: now,
        updatedAt: now,
      ),
    );

    // Finalize Purchase Bill: 20 Bearings @ ₹1,000 = ₹20,000 + 18% GST (₹3,600) = ₹23,600 (2,360,000 paise)
    final purchaseItem = PurchaseItem(
      id: 'item-persist-p1',
      purchaseId: '',
      productId: product.id,
      productName: product.name,
      unitCode: 'PCS',
      quantityScaled: 20000, // 20 units
      purchaseRatePaise: 100000,
      taxableAmountPaise: 2000000,
      taxRateId: taxRate18Id,
      rateBasisPoints: 1800,
      cgstRateBasisPoints: 900,
      cgstAmountPaise: 180000,
      sgstRateBasisPoints: 900,
      sgstAmountPaise: 180000,
      totalAmountPaise: 2360000,
      isItcEligible: true,
      trackInventory: true,
      createdAt: now,
      updatedAt: now,
    );

    final purchase = await purchaseRepo1.finalizePurchase(
      Purchase(
        id: 'pur-persist-1',
        businessId: biz.id,
        supplierId: supplier.id,
        purchaseNumber: '',
        supplierInvoiceNumber: 'BHB-2026-88',
        supplierInvoiceDate: now,
        purchaseDate: now,
        dueDate: now.add(const Duration(days: 30)),
        placeOfSupplyStateCode: '27',
        status: PurchaseStatus.draft,
        subtotalPaise: 2000000,
        taxableAmountPaise: 2000000,
        cgstPaise: 180000,
        sgstPaise: 180000,
        totalAmountPaise: 2360000,
        balanceAmountPaise: 2360000,
        itcEligibility: ItcEligibility.eligible,
        inputCgstPaise: 180000,
        inputSgstPaise: 180000,
        items: [purchaseItem],
        createdAt: now,
        updatedAt: now,
      ),
    );

    // Initial stock: 10 + 20 = 30.0
    expect((await productRepo1.getProductById(product.id))!.currentStock, equals(30.0));
    // Supplier balance: 2,360,000 paise
    expect((await partyRepo1.getPartyById(supplier.id))!.currentBalancePaise, equals(2360000));

    // Post Supplier Payment: ₹10,000.00 (1,000,000 paise)
    final payment = await paymentRepo1.postPayment(
      Payment(
        id: 'pay-persist-1',
        businessId: biz.id,
        partyType: PartyType.supplier,
        customerId: supplier.id,
        paymentNumber: 'DRAFT',
        paymentDate: now,
        paymentMethod: PaymentMethod.bankTransfer,
        amountPaise: 1000000,
        accountId: bankAcc.id,
        status: PaymentStatus.posted,
        allocations: [
          PaymentAllocation(
            id: 'alloc-persist-1',
            paymentId: 'pay-persist-1',
            documentId: purchase.id,
            documentType: 'PURCHASE',
            allocatedAmountPaise: 1000000,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect(payment.paymentNumber, contains('PAY-'));

    // Create Purchase Return / Debit Note: return 2 bearings @ ₹1,000 + GST = ₹2,360 (236,000 paise)
    final returnItem = PurchaseReturnItem(
      id: '',
      purchaseReturnId: '',
      purchaseItemId: purchase.items.first.id,
      productId: product.id,
      productName: product.name,
      unitCode: 'PCS',
      quantityScaled: 2000, // 2 units returned
      ratePaise: 100000,
      taxableAmountPaise: 200000,
      cgstAmountPaise: 18000,
      sgstAmountPaise: 18000,
      totalAmountPaise: 236000,
      taxRateBasisPoints: 1800,
      trackInventory: true,
      createdAt: now,
      updatedAt: now,
    );

    final debitNote = await purchaseRepo1.createReturn(
      PurchaseReturn(
        id: 'ret-persist-1',
        businessId: biz.id,
        originalPurchaseId: purchase.id,
        supplierId: supplier.id,
        returnNumber: 'DRAFT',
        returnDate: now,
        taxableAmountPaise: 200000,
        cgstPaise: 18000,
        sgstPaise: 18000,
        totalAmountPaise: 236000,
        reason: 'Incorrect bore size',
        items: [returnItem],
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect(debitNote.returnNumber, contains('DN-'));

    // 2. Simulate Application Termination / DB Close
    await helper1.close();

    // 3. Second Launch - Reconnect to identical disk database
    final helper2 = DatabaseHelper.createForTesting(
      dbPath: diskDbPath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );
    final purchaseRepo2 = SqlitePurchaseRepository(helper2);
    final paymentRepo2 = SqlitePaymentRepository(helper2);
    final productRepo2 = SqliteProductRepository(helper2);
    final partyRepo2 = SqlitePartyRepository(helper2);

    // Verify Purchase Bill persisted
    final reloadedPur = await purchaseRepo2.getPurchaseById(purchase.id);
    expect(reloadedPur, isNotNull);
    expect(reloadedPur!.purchaseNumber, equals(purchase.purchaseNumber));
    expect(reloadedPur.supplierInvoiceNumber, equals('BHB-2026-88'));
    expect(reloadedPur.totalAmountPaise, equals(2360000));
    expect(reloadedPur.paidAmountPaise, equals(1000000));
    // Balance was 2,360,000 - 1,000,000 payment - 236,000 return = 1,124,000 paise
    expect(reloadedPur.balanceAmountPaise, equals(1124000));
    expect(reloadedPur.status, equals(PurchaseStatus.partiallyPaid));
    expect(reloadedPur.items.length, equals(1));
    expect(reloadedPur.items.first.productName, equals('Roller Bearing 6205'));
    expect(reloadedPur.items.first.quantity, equals(20.0));

    // Verify Supplier Payment persisted
    final reloadedPay = await paymentRepo2.getPaymentById(payment.id);
    expect(reloadedPay, isNotNull);
    expect(reloadedPay!.amountPaise, equals(1000000));
    expect(reloadedPay.allocations.length, equals(1));
    expect(reloadedPay.allocations.first.documentId, equals(purchase.id));
    expect(reloadedPay.allocations.first.allocatedAmountPaise, equals(1000000));

    // Verify Debit Note persisted
    final reloadedReturn = await purchaseRepo2.getReturnById(debitNote.id);
    expect(reloadedReturn, isNotNull);
    expect(reloadedReturn!.returnNumber, equals(debitNote.returnNumber));
    expect(reloadedReturn.totalAmountPaise, equals(236000));
    expect(reloadedReturn.reason, equals('Incorrect bore size'));
    expect(reloadedReturn.items.length, equals(1));
    expect(reloadedReturn.items.first.quantity, equals(2.0));

    // Verify Stock survived: 10 opening + 20 purchase - 2 return = 28.0
    final reloadedProduct = await productRepo2.getProductById(product.id);
    expect(reloadedProduct!.currentStock, equals(28.0));

    // Verify Bank Balance survived: 5,000,000 opening - 1,000,000 payment = 4,000,000 paise
    final reloadedBank = await paymentRepo2.getCashBankAccountById(bankAcc.id);
    expect(reloadedBank!.currentBalancePaise, equals(4000000));

    // Verify Supplier AP Balance survived: 2,360,000 purchase - 1,000,000 paid - 236,000 returned = 1,124,000 paise
    final reloadedSupplier = await partyRepo2.getPartyById(supplier.id);
    expect(reloadedSupplier!.currentBalancePaise, equals(1124000));

    await helper2.close();
  });
}
