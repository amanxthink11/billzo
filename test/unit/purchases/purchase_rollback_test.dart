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
  late DatabaseHelper dbHelper;
  late SqliteBusinessRepository businessRepo;
  late SqlitePartyRepository partyRepo;
  late SqliteProductRepository productRepo;
  late SqlitePurchaseRepository purchaseRepo;
  late SqlitePaymentRepository paymentRepo;

  late Business testBusiness;
  late Party testSupplier;
  late Product testProduct;
  late String taxRate18Id;
  late String unitPcsId;
  late CashBankAccount testBankAcc;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_purchase_rollback_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );

    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    partyRepo = SqlitePartyRepository(dbHelper);
    productRepo = SqliteProductRepository(dbHelper);
    purchaseRepo = SqlitePurchaseRepository(dbHelper);
    paymentRepo = SqlitePaymentRepository(dbHelper);

    final now = DateTime.now().toUtc();
    testBusiness = await businessRepo.createBusiness(
      Business(
        id: 'biz-pr-rb',
        name: 'Rollback Purchases Ltd',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final db = await dbHelper.database;
    final taxRateRows = await db.query('tax_rates', where: 'business_id = ?', whereArgs: [testBusiness.id]);
    taxRate18Id = taxRateRows.firstWhere((r) => r['rate_basis_points'] == 1800)['id'] as String;

    final unitRows = await db.query('units', where: 'business_id = ?', whereArgs: [testBusiness.id]);
    unitPcsId = unitRows.firstWhere((u) => u['code'] == 'PCS')['id'] as String;

    testSupplier = await partyRepo.createParty(
      Party(
        id: 'supp-pr-rb-1',
        businessId: testBusiness.id,
        partyType: PartyType.supplier,
        name: 'Apex Components',
        phone: '9876511111',
        billingStateCode: '27',
        currentBalancePaise: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );

    testProduct = await productRepo.createProduct(
      Product(
        id: 'prod-pr-rb-1',
        businessId: testBusiness.id,
        name: 'Capacitor 100uF',
        sku: 'CAP-100',
        itemType: ItemType.product,
        sellingPricePaise: 10000,
        purchasePricePaise: 5000,
        currentStock: 10.0,
        openingStock: 10.0,
        unitId: unitPcsId,
        taxRateId: taxRate18Id,
        createdAt: now,
        updatedAt: now,
      ),
    );

    testBankAcc = await paymentRepo.createCashBankAccount(
      CashBankAccount(
        id: 'acc-pr-rb-bank',
        businessId: testBusiness.id,
        name: 'HDFC Corporate Account',
        accountType: CashBankAccountType.bank,
        openingBalancePaise: 10000000,
        currentBalancePaise: 10000000, // ₹100,000.00
        isDefault: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await dbHelper.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Purchase Mandatory Transaction Rollback Verification', () {
    test('Simulated crash during purchase finalization triggers 100% rollback', () async {
      final now = DateTime.now().toUtc();
      final previewBefore = await purchaseRepo.getNextPurchaseNumberPreview(testBusiness.id);

      final failingRepo = SqlitePurchaseRepository(
        dbHelper,
        onBeforePostCommitForTesting: (txn) async {
          throw Exception('SIMULATED_CRASH: Power failure before finalize commit');
        },
      );

      final draft = Purchase(
        id: 'pur-rb-fail',
        businessId: testBusiness.id,
        supplierId: testSupplier.id,
        purchaseNumber: 'DRAFT',
        supplierInvoiceNumber: 'INV-APEX-999',
        supplierInvoiceDate: now,
        purchaseDate: now,
        dueDate: now.add(const Duration(days: 30)),
        placeOfSupplyStateCode: '27',
        subtotalPaise: 100000,
        taxableAmountPaise: 100000,
        cgstPaise: 9000,
        sgstPaise: 9000,
        igstPaise: 0,
        roundOffPaise: 0,
        totalAmountPaise: 118000,
        balanceAmountPaise: 118000,
        items: [
          PurchaseItem(
            id: 'item-pr-fail',
            purchaseId: 'pur-rb-fail',
            productId: testProduct.id,
            productName: testProduct.name,
            taxRateId: taxRate18Id,
            quantityScaled: 20000, // 20 units
            unitCode: 'PCS',
            purchaseRatePaise: 5000,
            taxableAmountPaise: 100000,
            cgstRateBasisPoints: 900,
            sgstRateBasisPoints: 900,
            cgstAmountPaise: 9000,
            sgstAmountPaise: 9000,
            totalAmountPaise: 118000,
            isItcEligible: true,
            trackInventory: true,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      // Attempt finalization; must fail
      expect(
        () async => await failingRepo.finalizePurchase(draft),
        throwsA(isA<Exception>()),
      );

      final db = await dbHelper.database;

      // 1. Purchase record not created or finalized
      final purRows = await db.query('purchases', where: 'id = ?', whereArgs: [draft.id]);
      expect(purRows.isEmpty, isTrue, reason: 'Purchase record must not exist');

      // 2. Items not persisted
      final itemRows = await db.query('purchase_items', where: 'purchase_id = ?', whereArgs: [draft.id]);
      expect(itemRows.isEmpty, isTrue, reason: 'Purchase items must not exist');

      // 3. Stock not increased (still 10.0)
      final prodAfter = await productRepo.getProductById(testProduct.id);
      expect(prodAfter!.currentStock, equals(10.0), reason: 'Stock must remain 10.0');

      // 4. No stock movements created
      final stockMovs = await db.query('stock_movements', where: 'reference_id = ?', whereArgs: [draft.id]);
      expect(stockMovs.isEmpty, isTrue, reason: 'No stock movements created');

      // 5. No ledger entries created
      final ledgerEntries = await db.query('ledger_entries', where: 'transaction_id = ?', whereArgs: [draft.id]);
      expect(ledgerEntries.isEmpty, isTrue, reason: 'No ledger entries created');

      // 6. Supplier balance unchanged (0)
      final suppAfter = await partyRepo.getPartyById(testSupplier.id);
      expect(suppAfter!.currentBalancePaise, equals(0), reason: 'Supplier AP balance unchanged');

      // 7. Purchase sequence unchanged
      final previewAfter = await purchaseRepo.getNextPurchaseNumberPreview(testBusiness.id);
      expect(previewAfter, equals(previewBefore), reason: 'Sequence preview unchanged');
    });

    test('Simulated crash during purchase cancellation triggers 100% rollback', () async {
      final now = DateTime.now().toUtc();

      // First finalize a valid purchase
      final draft = Purchase(
        id: 'pur-rb-cancel-test',
        businessId: testBusiness.id,
        supplierId: testSupplier.id,
        purchaseNumber: 'DRAFT',
        supplierInvoiceNumber: 'INV-APEX-101',
        supplierInvoiceDate: now,
        purchaseDate: now,
        dueDate: now.add(const Duration(days: 30)),
        placeOfSupplyStateCode: '27',
        subtotalPaise: 50000,
        taxableAmountPaise: 50000,
        cgstPaise: 4500,
        sgstPaise: 4500,
        igstPaise: 0,
        roundOffPaise: 0,
        totalAmountPaise: 59000,
        balanceAmountPaise: 59000,
        items: [
          PurchaseItem(
            id: 'item-pr-cancel',
            purchaseId: 'pur-rb-cancel-test',
            productId: testProduct.id,
            productName: testProduct.name,
            taxRateId: taxRate18Id,
            quantityScaled: 10000, // 10 units
            unitCode: 'PCS',
            purchaseRatePaise: 5000,
            taxableAmountPaise: 50000,
            cgstRateBasisPoints: 900,
            sgstRateBasisPoints: 900,
            cgstAmountPaise: 4500,
            sgstAmountPaise: 4500,
            totalAmountPaise: 59000,
            isItcEligible: true,
            trackInventory: true,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      final finalized = await purchaseRepo.finalizePurchase(draft);
      expect(finalized.status, equals(PurchaseStatus.finalized));

      // Stock was 10.0 + 10.0 = 20.0
      var prod = await productRepo.getProductById(testProduct.id);
      expect(prod!.currentStock, equals(20.0));

      // Supplier AP is 59000 paise
      var supp = await partyRepo.getPartyById(testSupplier.id);
      expect(supp!.currentBalancePaise, equals(59000));

      // Instantiate repository that fails right before cancellation commit
      final failingRepo = SqlitePurchaseRepository(
        dbHelper,
        onBeforePostCommitForTesting: (txn) async {
          throw Exception('SIMULATED_CRASH: DB error during cancellation');
        },
      );

      expect(
        () async => await failingRepo.cancelPurchase(
          finalized.id,
          cancellationReason: 'Vendor cancelled order',
        ),
        throwsA(isA<Exception>()),
      );

      // Verify that cancellation did not happen
      final purAfter = await purchaseRepo.getPurchaseById(finalized.id);
      expect(purAfter!.status, equals(PurchaseStatus.finalized), reason: 'Purchase must remain finalized');
      expect(purAfter.cancelledAt, isNull);

      // Stock must remain 20.0 (not rolled back)
      prod = await productRepo.getProductById(testProduct.id);
      expect(prod!.currentStock, equals(20.0));

      // Supplier balance must remain 59000
      supp = await partyRepo.getPartyById(testSupplier.id);
      expect(supp!.currentBalancePaise, equals(59000));

      // No PURCHASE_CANCEL stock movements
      final db = await dbHelper.database;
      final cancelMovs = await db.query(
        'stock_movements',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['PURCHASE_CANCEL', finalized.id],
      );
      expect(cancelMovs.isEmpty, isTrue);
    });

    test('Simulated crash during purchase return / debit note triggers 100% rollback', () async {
      final now = DateTime.now().toUtc();

      // Finalize a purchase with 10 units
      final purchase = await purchaseRepo.finalizePurchase(
        Purchase(
          id: 'pur-rb-return-test',
          businessId: testBusiness.id,
          supplierId: testSupplier.id,
          purchaseNumber: 'DRAFT',
          supplierInvoiceNumber: 'INV-APEX-RET',
          supplierInvoiceDate: now,
          purchaseDate: now,
          dueDate: now.add(const Duration(days: 30)),
          placeOfSupplyStateCode: '27',
          subtotalPaise: 50000,
          taxableAmountPaise: 50000,
          cgstPaise: 4500,
          sgstPaise: 4500,
          igstPaise: 0,
          roundOffPaise: 0,
          totalAmountPaise: 59000,
          balanceAmountPaise: 59000,
          items: [
            PurchaseItem(
              id: 'item-pr-ret',
              purchaseId: 'pur-rb-return-test',
              productId: testProduct.id,
              productName: testProduct.name,
              taxRateId: taxRate18Id,
              quantityScaled: 10000,
              unitCode: 'PCS',
              purchaseRatePaise: 5000,
              taxableAmountPaise: 50000,
              cgstRateBasisPoints: 900,
              sgstRateBasisPoints: 900,
              cgstAmountPaise: 4500,
              sgstAmountPaise: 4500,
              totalAmountPaise: 59000,
              isItcEligible: true,
              trackInventory: true,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );

      final failingRepo = SqlitePurchaseRepository(
        dbHelper,
        onBeforePostCommitForTesting: (txn) async {
          throw Exception('SIMULATED_CRASH: Failure while saving debit note');
        },
      );

      final debitNote = PurchaseReturn(
        id: 'dn-fail-rb',
        businessId: testBusiness.id,
        originalPurchaseId: purchase.id,
        supplierId: testSupplier.id,
        returnNumber: 'DRAFT',
        returnDate: now,
        reason: 'Damaged packaging',
        taxableAmountPaise: 25000,
        cgstPaise: 2250,
        sgstPaise: 2250,
        igstPaise: 0,
        totalAmountPaise: 29500,
        items: [
          PurchaseReturnItem(
            id: 'dn-item-fail',
            purchaseReturnId: 'dn-fail-rb',
            purchaseItemId: purchase.items.first.id,
            productId: testProduct.id,
            productName: testProduct.name,
            quantityScaled: 5000,
            unitCode: 'PCS',
            ratePaise: 5000,
            taxRateBasisPoints: 1800,
            taxableAmountPaise: 25000,
            cgstAmountPaise: 2250,
            sgstAmountPaise: 2250,
            totalAmountPaise: 29500,
            trackInventory: true,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      expect(
        () async => await failingRepo.createReturn(debitNote),
        throwsA(isA<Exception>()),
      );

      // Verify no debit note saved
      final db = await dbHelper.database;
      final retRows = await db.query('purchase_returns', where: 'id = ?', whereArgs: [debitNote.id]);
      expect(retRows.isEmpty, isTrue, reason: 'Purchase return must not exist');

      // Purchase balance intact
      final purchaseAfter = await purchaseRepo.getPurchaseById(purchase.id);
      expect(purchaseAfter!.balanceAmountPaise, equals(59000));

      // Supplier balance intact
      final suppAfter = await partyRepo.getPartyById(testSupplier.id);
      expect(suppAfter!.currentBalancePaise, equals(59000));
    });

    test('Simulated crash during supplier payment posting triggers 100% rollback', () async {
      final now = DateTime.now().toUtc();

      // Finalize a purchase bill for ₹10,000 (1,000,000 paise)
      final purchase = await purchaseRepo.finalizePurchase(
        Purchase(
          id: 'pur-rb-pay-test',
          businessId: testBusiness.id,
          supplierId: testSupplier.id,
          purchaseNumber: 'DRAFT',
          supplierInvoiceNumber: 'INV-APEX-PAY',
          supplierInvoiceDate: now,
          purchaseDate: now,
          dueDate: now.add(const Duration(days: 30)),
          placeOfSupplyStateCode: '27',
          subtotalPaise: 1000000,
          taxableAmountPaise: 1000000,
          cgstPaise: 0,
          sgstPaise: 0,
          igstPaise: 0,
          roundOffPaise: 0,
          totalAmountPaise: 1000000,
          balanceAmountPaise: 1000000,
          items: [
            PurchaseItem(
              id: 'item-pr-pay',
              purchaseId: 'pur-rb-pay-test',
              productId: testProduct.id,
              productName: testProduct.name,
              taxRateId: taxRate18Id,
              quantityScaled: 1000,
              unitCode: 'PCS',
              purchaseRatePaise: 1000000,
              taxableAmountPaise: 1000000,
              cgstRateBasisPoints: 0,
              sgstRateBasisPoints: 0,
              cgstAmountPaise: 0,
              sgstAmountPaise: 0,
              totalAmountPaise: 1000000,
              isItcEligible: true,
              trackInventory: false,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );

      final failingPaymentRepo = SqlitePaymentRepository(
        dbHelper,
        onBeforePostCommitForTesting: (txn) async {
          throw Exception('SIMULATED_CRASH: Bank network failure during posting');
        },
      );

      final doomedPayment = Payment(
        id: 'pay-pr-fail-1',
        businessId: testBusiness.id,
        partyType: PartyType.supplier,
        customerId: testSupplier.id,
        paymentNumber: 'DRAFT',
        paymentDate: now,
        paymentMethod: PaymentMethod.bankTransfer,
        amountPaise: 600000,
        accountId: testBankAcc.id,
        status: PaymentStatus.posted,
        allocations: [
          PaymentAllocation(
            id: 'alloc-pr-fail-1',
            paymentId: 'pay-pr-fail-1',
            documentId: purchase.id,
            documentType: 'PURCHASE',
            allocatedAmountPaise: 600000,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      expect(
        () async => await failingPaymentRepo.postPayment(doomedPayment),
        throwsA(isA<Exception>()),
      );

      final db = await dbHelper.database;

      // 1. Payment not created
      final payRows = await db.query('payments', where: 'id = ?', whereArgs: [doomedPayment.id]);
      expect(payRows.isEmpty, isTrue);

      // 2. Allocations not created
      final allocRows = await db.query('payment_allocations', where: 'payment_id = ?', whereArgs: [doomedPayment.id]);
      expect(allocRows.isEmpty, isTrue);

      // 3. Bank balance unchanged (10000000 paise)
      final accAfter = await paymentRepo.getCashBankAccountById(testBankAcc.id);
      expect(accAfter!.currentBalancePaise, equals(10000000));

      // 4. Supplier balance unchanged (1000000 paise)
      final suppAfter = await partyRepo.getPartyById(testSupplier.id);
      expect(suppAfter!.currentBalancePaise, equals(1000000));

      // 5. Purchase outstanding balance unchanged (1000000 paise)
      final purAfter = await purchaseRepo.getPurchaseById(purchase.id);
      expect(purAfter!.balanceAmountPaise, equals(1000000));
      expect(purAfter.paidAmountPaise, equals(0));
    });
  });
}
