import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/purchase/itc_eligibility.dart';
import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_item.dart';
import 'package:billzo/domain/purchase/purchase_return.dart';
import 'package:billzo/domain/purchase/purchase_return_item.dart';
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

  late Business testBusiness;
  late Party testSupplier;
  late Product testProduct;
  late String taxRate18Id;
  late String unitPcsId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_returns_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );

    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    partyRepo = SqlitePartyRepository(dbHelper);
    productRepo = SqliteProductRepository(dbHelper);
    purchaseRepo = SqlitePurchaseRepository(dbHelper);

    testBusiness = await businessRepo.createBusiness(
      Business(
        id: 'biz-ret',
        name: 'Returns Testing Store',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    final db = await dbHelper.database;
    final taxRateRows = await db.query('tax_rates', where: 'business_id = ?', whereArgs: [testBusiness.id]);
    taxRate18Id = taxRateRows.firstWhere((r) => r['rate_basis_points'] == 1800)['id'] as String;

    final unitRows = await db.query('units', where: 'business_id = ?', whereArgs: [testBusiness.id]);
    unitPcsId = unitRows.firstWhere((u) => u['code'] == 'PCS')['id'] as String;

    testSupplier = await partyRepo.createParty(
      Party(
        id: 'supp-ret',
        businessId: testBusiness.id,
        name: 'Prime Component Corp',
        phone: '9822334455',
        partyType: PartyType.supplier,
        gstin: '27AABCP5678F1Z2',
        billingStateCode: '27',
        billingStateName: 'Maharashtra',
        currentBalancePaise: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    testProduct = await productRepo.createProduct(
      Product(
        id: 'prod-ret-1',
        businessId: testBusiness.id,
        name: 'Precision Gear 10mm',
        sku: 'PGR-010',
        unitId: unitPcsId,
        taxRateId: taxRate18Id,
        purchasePricePaise: 100000, // ₹1,000.00
        sellingPricePaise: 140000,
        currentStock: 0.0,
        openingStock: 0.0,
        itemType: ItemType.product,
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

  group('Purchase Return / Debit Note Tests', () {
    test('Partial purchase return decreases stock, reduces supplier payable, and reverses accounting', () async {
      final now = DateTime.now().toUtc();

      // 1. Create and finalize original purchase of 10 gears @ ₹1,000 each = ₹10,000 + 18% GST (₹1,800) = ₹11,800
      final purchaseItem = PurchaseItem(
        id: 'item-orig',
        purchaseId: '',
        productId: testProduct.id,
        productName: testProduct.name,
        unitCode: 'PCS',
        quantityScaled: 10000, // 10 units
        purchaseRatePaise: 100000,
        taxableAmountPaise: 1000000,
        taxRateId: taxRate18Id,
        rateBasisPoints: 1800,
        cgstRateBasisPoints: 900,
        cgstAmountPaise: 90000,
        sgstRateBasisPoints: 900,
        sgstAmountPaise: 90000,
        totalAmountPaise: 1180000,
        isItcEligible: true,
        trackInventory: true,
        createdAt: now,
        updatedAt: now,
      );

      final originalPurchase = await purchaseRepo.finalizePurchase(
        Purchase(
          id: 'pur-orig-1',
          businessId: testBusiness.id,
          supplierId: testSupplier.id,
          purchaseNumber: '',
          supplierInvoiceNumber: 'INV-ORIG-01',
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
          items: [purchaseItem],
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Verify initial state: stock = 10.0, supplier balance = ₹11,800
      final productBeforeReturn = await productRepo.getProductById(testProduct.id);
      expect(productBeforeReturn!.currentStock, 10.0);

      final supplierBeforeReturn = await partyRepo.getPartyById(testSupplier.id);
      expect(supplierBeforeReturn!.currentBalancePaise, 1180000);

      // 2. Perform partial return of 3 gears @ ₹1,000 each = ₹3,000 taxable + ₹540 GST = ₹3,540 return
      final returnItem = PurchaseReturnItem(
        id: '',
        purchaseReturnId: '',
        purchaseItemId: originalPurchase.items.first.id,
        productId: testProduct.id,
        productName: testProduct.name,
        unitCode: 'PCS',
        quantityScaled: 3000, // 3 units returned
        ratePaise: 100000,
        taxableAmountPaise: 300000,
        cgstAmountPaise: 27000, // ₹270
        sgstAmountPaise: 27000, // ₹270
        totalAmountPaise: 354000, // ₹3,540
        taxRateBasisPoints: 1800,
        trackInventory: true,
        createdAt: now,
        updatedAt: now,
      );

      final purchaseReturn = PurchaseReturn(
        id: 'ret-1',
        businessId: testBusiness.id,
        supplierId: testSupplier.id,
        originalPurchaseId: originalPurchase.id,
        returnNumber: '',
        returnDate: now,
        taxableAmountPaise: 300000,
        cgstPaise: 27000,
        sgstPaise: 27000,
        totalAmountPaise: 354000,
        reason: 'Defective packaging on 3 units',
        items: [returnItem],
        createdAt: now,
        updatedAt: now,
      );

      final createdReturn = await purchaseRepo.createReturn(purchaseReturn);
      expect(createdReturn.returnNumber, isNotEmpty);
      expect(createdReturn.returnNumber, contains('DN-'));

      // 3. Verify stock decreased by 3 to 7.0
      final productAfterReturn = await productRepo.getProductById(testProduct.id);
      expect(productAfterReturn!.currentStock, 7.0);

      // 4. Verify negative stock movement recorded
      final db = await dbHelper.database;
      final stockMoves = await db.query(
        'stock_movements',
        where: 'reference_id = ? AND reference_type = ?',
        whereArgs: [createdReturn.id, 'PURCHASE_RETURN'],
      );
      expect(stockMoves.length, 1);
      expect(stockMoves.first['quantity_delta'], -3000);

      // 5. Verify Supplier Payable reduced by ₹3,540 (₹11,800 - ₹3,540 = ₹8,260)
      final supplierAfterReturn = await partyRepo.getPartyById(testSupplier.id);
      expect(supplierAfterReturn!.currentBalancePaise, 1180000 - 354000);

      // 6. Verify Original Purchase balance updated
      final updatedOrig = await purchaseRepo.getPurchaseById(originalPurchase.id);
      expect(updatedOrig!.balanceAmountPaise, 1180000 - 354000);

      // 7. Verify balanced accounting entries for debit note
      final returnLedger = await db.query(
        'ledger_entries',
        where: 'transaction_id = ?',
        whereArgs: [createdReturn.id],
      );
      expect(returnLedger.isNotEmpty, isTrue);

      int debitSum = 0;
      int creditSum = 0;
      for (final e in returnLedger) {
        debitSum += e['debit_paise'] as int;
        creditSum += e['credit_paise'] as int;
      }
      expect(debitSum, 354000);
      expect(creditSum, 354000);
    });

    test('Rejects return exceeding remaining available quantity on purchase', () async {
      final now = DateTime.now().toUtc();

      // Original purchase of 4 units
      final purchaseItem = PurchaseItem(
        id: 'item-small',
        purchaseId: '',
        productId: testProduct.id,
        productName: testProduct.name,
        unitCode: 'PCS',
        quantityScaled: 4000, // 4 units
        purchaseRatePaise: 100000,
        taxableAmountPaise: 400000,
        taxRateId: taxRate18Id,
        rateBasisPoints: 1800,
        cgstRateBasisPoints: 900,
        cgstAmountPaise: 36000,
        sgstRateBasisPoints: 900,
        sgstAmountPaise: 36000,
        totalAmountPaise: 472000,
        isItcEligible: true,
        trackInventory: true,
        createdAt: now,
        updatedAt: now,
      );

      final originalPurchase = await purchaseRepo.finalizePurchase(
        Purchase(
          id: 'pur-small-1',
          businessId: testBusiness.id,
          supplierId: testSupplier.id,
          purchaseNumber: '',
          supplierInvoiceNumber: 'INV-SMALL-01',
          supplierInvoiceDate: now,
          purchaseDate: now,
          dueDate: now.add(const Duration(days: 30)),
          placeOfSupplyStateCode: '27',
          status: PurchaseStatus.draft,
          subtotalPaise: 400000,
          taxableAmountPaise: 400000,
          cgstPaise: 36000,
          sgstPaise: 36000,
          totalAmountPaise: 472000,
          balanceAmountPaise: 472000,
          itcEligibility: ItcEligibility.eligible,
          inputCgstPaise: 36000,
          inputSgstPaise: 36000,
          items: [purchaseItem],
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Return 3 units first
      final return1 = PurchaseReturn(
        id: 'ret-first',
        businessId: testBusiness.id,
        supplierId: testSupplier.id,
        originalPurchaseId: originalPurchase.id,
        returnNumber: '',
        returnDate: now,
        taxableAmountPaise: 300000,
        totalAmountPaise: 354000,
        items: [
          PurchaseReturnItem(
            id: '',
            purchaseReturnId: '',
            purchaseItemId: originalPurchase.items.first.id,
            productId: testProduct.id,
            productName: testProduct.name,
            unitCode: 'PCS',
            quantityScaled: 3000, // 3 units
            ratePaise: 100000,
            taxableAmountPaise: 300000,
            totalAmountPaise: 354000,
            trackInventory: true,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await purchaseRepo.createReturn(return1);

      // Now attempting to return 2 more units should fail because only 1 unit is remaining!
      final overReturn = PurchaseReturn(
        id: 'ret-second',
        businessId: testBusiness.id,
        supplierId: testSupplier.id,
        originalPurchaseId: originalPurchase.id,
        returnNumber: '',
        returnDate: now,
        taxableAmountPaise: 200000,
        totalAmountPaise: 236000,
        items: [
          PurchaseReturnItem(
            id: '',
            purchaseReturnId: '',
            purchaseItemId: originalPurchase.items.first.id,
            productId: testProduct.id,
            productName: testProduct.name,
            unitCode: 'PCS',
            quantityScaled: 2000, // 2 units (exceeds remaining 1 unit)
            ratePaise: 100000,
            taxableAmountPaise: 200000,
            totalAmountPaise: 236000,
            trackInventory: true,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      expect(
        () async => await purchaseRepo.createReturn(overReturn),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('Maximum returnable'))),
      );
    });
  });
}
