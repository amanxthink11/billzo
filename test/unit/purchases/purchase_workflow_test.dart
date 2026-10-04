import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/purchase/itc_eligibility.dart';
import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_item.dart';
import 'package:billzo/domain/purchase/purchase_status.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_party_repository.dart';
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

  late Business businessA;
  late Business businessB;
  late Party supplierA;
  late Product goodsProduct;
  late Product serviceProduct;
  late String taxRate18Id;
  late String unitPcsId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_purchase_workflow_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );

    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    partyRepo = SqlitePartyRepository(dbHelper);
    productRepo = SqliteProductRepository(dbHelper);
    purchaseRepo = SqlitePurchaseRepository(dbHelper);

    // Seed Business A (Maharashtra, 27)
    businessA = await businessRepo.createBusiness(
      Business(
        id: 'biz-a',
        name: 'Alpha Wholesalers',
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
        name: 'Beta Distributors',
        phone: '9876543211',
        stateCode: '29',
        stateName: 'Karnataka',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    final db = await dbHelper.database;
    final taxRateRows = await db.query('tax_rates', where: 'business_id = ?', whereArgs: [businessA.id]);
    taxRate18Id = taxRateRows.firstWhere((r) => r['rate_basis_points'] == 1800)['id'] as String;

    final unitRows = await db.query('units', where: 'business_id = ?', whereArgs: [businessA.id]);
    unitPcsId = unitRows.firstWhere((u) => u['code'] == 'PCS')['id'] as String;

    // Seed supplier under Business A
    supplierA = await partyRepo.createParty(
      Party(
        id: 'supp-a',
        businessId: businessA.id,
        name: 'Metro Suppliers Ltd',
        phone: '9811223344',
        partyType: PartyType.supplier,
        gstin: '27AABCM1234A1Z5',
        billingStateCode: '27',
        billingStateName: 'Maharashtra',
        currentBalancePaise: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    // Seed physical goods product (initial stock: 0)
    goodsProduct = await productRepo.createProduct(
      Product(
        id: 'prod-goods',
        businessId: businessA.id,
        name: 'Industrial Widget A',
        sku: 'WGT-001',
        unitId: unitPcsId,
        taxRateId: taxRate18Id,
        purchasePricePaise: 100000, // ₹1,000.00
        sellingPricePaise: 150000, // ₹1,500.00
        currentStock: 0.0,
        openingStock: 0.0,
        itemType: ItemType.product,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    // Seed service item (trackInventory: false)
    serviceProduct = await productRepo.createProduct(
      Product(
        id: 'prod-service',
        businessId: businessA.id,
        name: 'Machinery Maintenance Service',
        unitId: unitPcsId,
        taxRateId: taxRate18Id,
        purchasePricePaise: 50000, // ₹500.00
        sellingPricePaise: 80000,
        currentStock: 0.0,
        openingStock: 0.0,
        itemType: ItemType.service,
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

  group('Purchase Workflow Tests', () {
    test('Draft purchase does not affect stock, supplier balance, or post accounting', () async {
      final now = DateTime.now().toUtc();
      final draftItem = PurchaseItem(
        id: 'p-item-draft',
        purchaseId: '',
        productId: goodsProduct.id,
        productName: goodsProduct.name,
        unitCode: 'PCS',
        quantityScaled: 10000, // 10 units
        purchaseRatePaise: 100000, // ₹1,000
        taxableAmountPaise: 1000000, // ₹10,000
        taxRateId: taxRate18Id,
        rateBasisPoints: 1800,
        cgstRateBasisPoints: 900,
        cgstAmountPaise: 90000, // ₹900
        sgstRateBasisPoints: 900,
        sgstAmountPaise: 90000, // ₹900
        totalAmountPaise: 1180000, // ₹11,800
        isItcEligible: true,
        trackInventory: true,
        createdAt: now,
        updatedAt: now,
      );

      final draftPurchase = Purchase(
        id: 'pur-draft-1',
        businessId: businessA.id,
        supplierId: supplierA.id,
        purchaseNumber: '',
        supplierInvoiceNumber: 'INV-TEMP-1',
        supplierInvoiceDate: now,
        purchaseDate: now,
        dueDate: now.add(const Duration(days: 30)),
        placeOfSupplyStateCode: '27',
        status: PurchaseStatus.draft,
        subtotalPaise: 1000000,
        taxableAmountPaise: 1000000,
        cgstPaise: 90000,
        sgstPaise: 90000,
        totalAmountPaise: 1180000,
        balanceAmountPaise: 1180000,
        itcEligibility: ItcEligibility.eligible,
        inputCgstPaise: 90000,
        inputSgstPaise: 90000,
        items: [draftItem],
        createdAt: now,
        updatedAt: now,
      );

      final saved = await purchaseRepo.saveDraft(draftPurchase);
      expect(saved.isDraft, isTrue);

      final db = await dbHelper.database;

      // 1. Verify stock movements table has NO entries
      final stockMoves = await db.query(
        'stock_movements',
        where: 'reference_id = ?',
        whereArgs: [saved.id],
      );
      expect(stockMoves.isEmpty, isTrue);

      // 2. Verify product current stock remains 0
      final updatedProduct = await productRepo.getProductById(goodsProduct.id);
      expect(updatedProduct!.currentStock, 0.0);

      // 3. Verify ledger entries table has NO entries
      final ledgerEntries = await db.query(
        'ledger_entries',
        where: 'transaction_id = ?',
        whereArgs: [saved.id],
      );
      expect(ledgerEntries.isEmpty, isTrue);

      // 4. Verify supplier balance remains unchanged
      final updatedSupplier = await partyRepo.getPartyById(supplierA.id);
      expect(updatedSupplier!.currentBalancePaise, 0);
    });

    test('Finalizing purchase increases stock for goods, skips services, and posts balanced accounting', () async {
      final now = DateTime.now().toUtc();
      final goodsItem = PurchaseItem(
        id: 'p-item-goods',
        purchaseId: '',
        productId: goodsProduct.id,
        productName: goodsProduct.name,
        unitCode: 'PCS',
        quantityScaled: 15000, // 15 units
        purchaseRatePaise: 100000, // ₹1,000
        taxableAmountPaise: 1500000, // ₹15,000
        taxRateId: taxRate18Id,
        rateBasisPoints: 1800,
        cgstRateBasisPoints: 900,
        cgstAmountPaise: 135000, // ₹1,350
        sgstRateBasisPoints: 900,
        sgstAmountPaise: 135000, // ₹1,350
        totalAmountPaise: 1770000, // ₹17,700
        isItcEligible: true,
        trackInventory: true,
        createdAt: now,
        updatedAt: now,
      );

      final serviceItem = PurchaseItem(
        id: 'p-item-serv',
        purchaseId: '',
        productId: serviceProduct.id,
        productName: serviceProduct.name,
        unitCode: 'PCS',
        quantityScaled: 1000, // 1 unit
        purchaseRatePaise: 50000, // ₹500
        taxableAmountPaise: 50000, // ₹500
        taxRateId: taxRate18Id,
        rateBasisPoints: 1800,
        cgstRateBasisPoints: 900,
        cgstAmountPaise: 4500, // ₹45
        sgstRateBasisPoints: 900,
        sgstAmountPaise: 4500, // ₹45
        totalAmountPaise: 59000, // ₹590
        isItcEligible: true,
        trackInventory: false,
        createdAt: now,
        updatedAt: now,
      );

      final totalTaxable = 1500000 + 50000; // ₹15,500 = 1550000 paise
      final totalCgst = 135000 + 4500; // ₹1,395 = 139500 paise
      final totalSgst = 135000 + 4500; // ₹1,395 = 139500 paise
      final grandTotal = 1770000 + 59000; // ₹18,290 = 1829000 paise

      final purchaseToFinalize = Purchase(
        id: 'pur-fin-1',
        businessId: businessA.id,
        supplierId: supplierA.id,
        purchaseNumber: '',
        supplierInvoiceNumber: 'SUPP-INV-2026-A1',
        supplierInvoiceDate: now,
        purchaseDate: now,
        dueDate: now.add(const Duration(days: 30)),
        placeOfSupplyStateCode: '27',
        status: PurchaseStatus.draft,
        subtotalPaise: totalTaxable,
        taxableAmountPaise: totalTaxable,
        cgstPaise: totalCgst,
        sgstPaise: totalSgst,
        totalAmountPaise: grandTotal,
        balanceAmountPaise: grandTotal,
        itcEligibility: ItcEligibility.eligible,
        inputCgstPaise: totalCgst,
        inputSgstPaise: totalSgst,
        items: [goodsItem, serviceItem],
        createdAt: now,
        updatedAt: now,
      );

      final finalized = await purchaseRepo.finalizePurchase(purchaseToFinalize);
      expect(finalized.isFinalized, isTrue);
      expect(finalized.purchaseNumber, isNotEmpty);
      expect(finalized.finalizedAt, isNotNull);

      final db = await dbHelper.database;

      // 1. Verify Stock Movements: Goods increased by 15.000, Service has NO movement
      final stockMoves = await db.query(
        'stock_movements',
        where: 'reference_id = ?',
        whereArgs: [finalized.id],
      );
      expect(stockMoves.length, 1);
      expect(stockMoves.first['product_id'], goodsProduct.id);
      expect(stockMoves.first['quantity_delta'], 15000);
      expect(stockMoves.first['reference_type'], 'PURCHASE');

      final updatedGoods = await productRepo.getProductById(goodsProduct.id);
      expect(updatedGoods!.currentStock, 15.0);

      final updatedService = await productRepo.getProductById(serviceProduct.id);
      expect(updatedService!.currentStock, 0.0);

      // 2. Verify Supplier Accounts Payable increased
      final updatedSupplier = await partyRepo.getPartyById(supplierA.id);
      expect(updatedSupplier!.currentBalancePaise, grandTotal);

      // 3. Verify Double-Entry Accounting balances exactly
      final journalEntries = await db.query(
        'ledger_entries',
        where: 'transaction_id = ?',
        whereArgs: [finalized.id],
      );
      expect(journalEntries.isNotEmpty, isTrue);

      int totalDebit = 0;
      int totalCredit = 0;
      for (final entry in journalEntries) {
        totalDebit += entry['debit_paise'] as int;
        totalCredit += entry['credit_paise'] as int;
      }

      // Exact balanced journal entry
      expect(totalDebit, grandTotal);
      expect(totalCredit, grandTotal);
      expect(totalDebit == totalCredit, isTrue);
    });

    test('Purchase cancellation restores stock, reverses supplier balance, and reverses accounting', () async {
      final now = DateTime.now().toUtc();
      final item = PurchaseItem(
        id: 'p-item-cancel',
        purchaseId: '',
        productId: goodsProduct.id,
        productName: goodsProduct.name,
        unitCode: 'PCS',
        quantityScaled: 5000, // 5 units
        purchaseRatePaise: 100000,
        taxableAmountPaise: 500000,
        taxRateId: taxRate18Id,
        rateBasisPoints: 1800,
        cgstRateBasisPoints: 900,
        cgstAmountPaise: 45000,
        sgstRateBasisPoints: 900,
        sgstAmountPaise: 45000,
        totalAmountPaise: 590000,
        isItcEligible: true,
        trackInventory: true,
        createdAt: now,
        updatedAt: now,
      );

      final purchase = Purchase(
        id: 'pur-to-cancel',
        businessId: businessA.id,
        supplierId: supplierA.id,
        purchaseNumber: '',
        supplierInvoiceNumber: 'INV-TO-CANCEL',
        supplierInvoiceDate: now,
        purchaseDate: now,
        dueDate: now.add(const Duration(days: 30)),
        placeOfSupplyStateCode: '27',
        status: PurchaseStatus.draft,
        subtotalPaise: 500000,
        taxableAmountPaise: 500000,
        cgstPaise: 45000,
        sgstPaise: 45000,
        totalAmountPaise: 590000,
        balanceAmountPaise: 590000,
        itcEligibility: ItcEligibility.eligible,
        inputCgstPaise: 45000,
        inputSgstPaise: 45000,
        items: [item],
        createdAt: now,
        updatedAt: now,
      );

      final finalized = await purchaseRepo.finalizePurchase(purchase);

      // Verify stock was 5000 before cancellation
      final goodsBeforeCancel = await productRepo.getProductById(goodsProduct.id);
      expect(goodsBeforeCancel!.currentStock, 5.0);

      // Cancel the purchase
      final cancelled = await purchaseRepo.cancelPurchase(
        finalized.id,
        cancellationReason: 'Order cancelled by supplier due to quality rejection',
      );
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.cancelledAt, isNotNull);
      expect(cancelled.cancellationReason, contains('quality rejection'));

      // 1. Stock restored to 0
      final goodsAfterCancel = await productRepo.getProductById(goodsProduct.id);
      expect(goodsAfterCancel!.currentStock, 0.0);

      // 2. Supplier balance restored to 0
      final supplierAfterCancel = await partyRepo.getPartyById(supplierA.id);
      expect(supplierAfterCancel!.currentBalancePaise, 0);

      // 3. Reversing stock movement exists
      final db = await dbHelper.database;
      final cancelMoves = await db.query(
        'stock_movements',
        where: 'reference_id = ? AND reference_type = ?',
        whereArgs: [finalized.id, 'PURCHASE_CANCEL'],
      );
      expect(cancelMoves.isNotEmpty, isTrue);
      expect(cancelMoves.first['quantity_delta'], -5000);

      // 4. Accounting ledger has balanced reversal
      final reversalLedger = await db.query(
        'ledger_entries',
        where: 'transaction_id = ?',
        whereArgs: [finalized.id],
      );
      int sumDebit = 0;
      int sumCredit = 0;
      for (final e in reversalLedger) {
        sumDebit += e['debit_paise'] as int;
        sumCredit += e['credit_paise'] as int;
      }
      expect(sumDebit, sumCredit);
    });

    test('Purchase sequence is isolated per business', () async {
      final now = DateTime.now().toUtc();

      // Seed supplier in Business B
      final supplierB = await partyRepo.createParty(
        Party(
          id: 'supp-b',
          businessId: businessB.id,
          name: 'South Traders',
          phone: '9844112233',
          partyType: PartyType.supplier,
          billingStateCode: '29',
          billingStateName: 'Karnataka',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final db = await dbHelper.database;
      final taxRateB = await db.query('tax_rates', where: 'business_id = ?', whereArgs: [businessB.id]);
      final tax18B = taxRateB.firstWhere((r) => r['rate_basis_points'] == 1800)['id'] as String;
      final unitB = await db.query('units', where: 'business_id = ?', whereArgs: [businessB.id]);
      final unitPcsB = unitB.firstWhere((u) => u['code'] == 'PCS')['id'] as String;

      final prodB = await productRepo.createProduct(
        Product(
          id: 'prod-b',
          businessId: businessB.id,
          name: 'Karnataka Spice Mix',
          unitId: unitPcsB,
          taxRateId: tax18B,
          purchasePricePaise: 20000,
          sellingPricePaise: 30000,
          currentStock: 0.0,
          openingStock: 0.0,
          itemType: ItemType.product,
          createdAt: now,
          updatedAt: now,
        ),
      );

      Purchase createP(String bizId, String suppId, String pId, String unitCode, String taxId) {
        return Purchase(
          id: '',
          businessId: bizId,
          supplierId: suppId,
          purchaseNumber: '',
          supplierInvoiceNumber: 'INV-$bizId',
          supplierInvoiceDate: now,
          purchaseDate: now,
          dueDate: now.add(const Duration(days: 30)),
          placeOfSupplyStateCode: '27',
          status: PurchaseStatus.draft,
          subtotalPaise: 20000,
          taxableAmountPaise: 20000,
          cgstPaise: 1800,
          sgstPaise: 1800,
          totalAmountPaise: 23600,
          balanceAmountPaise: 23600,
          itcEligibility: ItcEligibility.eligible,
          inputCgstPaise: 1800,
          inputSgstPaise: 1800,
          items: [
            PurchaseItem(
              id: '',
              purchaseId: '',
              productId: pId,
              productName: 'Item',
              unitCode: unitCode,
              quantityScaled: 1000,
              purchaseRatePaise: 20000,
              taxableAmountPaise: 20000,
              taxRateId: taxId,
              rateBasisPoints: 1800,
              cgstRateBasisPoints: 900,
              cgstAmountPaise: 1800,
              sgstRateBasisPoints: 900,
              sgstAmountPaise: 1800,
              totalAmountPaise: 23600,
              trackInventory: true,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        );
      }

      final pA1 = await purchaseRepo.finalizePurchase(
        createP(businessA.id, supplierA.id, goodsProduct.id, 'PCS', taxRate18Id),
      );
      final pB1 = await purchaseRepo.finalizePurchase(
        createP(businessB.id, supplierB.id, prodB.id, 'PCS', tax18B),
      );

      // Both should start at sequence 1 for their respective business
      expect(pA1.purchaseNumber, contains('0001'));
      expect(pB1.purchaseNumber, contains('0001'));
      expect(pA1.businessId, isNot(equals(pB1.businessId)));
    });
  });
}
