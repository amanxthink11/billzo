import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_item.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_invoice_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_party_repository.dart';
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
  late SqliteProductRepository productRepo;
  late SqliteInvoiceRepository invoiceRepo;

  late Business businessA;
  late Business businessB;
  late Party customerA;
  late Product goodsProduct;
  late Product serviceProduct;
  late String taxRate18Id;
  late String unitPcsId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_invoice_workflow_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );

    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    partyRepo = SqlitePartyRepository(dbHelper);
    productRepo = SqliteProductRepository(dbHelper);
    invoiceRepo = SqliteInvoiceRepository(dbHelper);

    // Seed Business A (Maharashtra, 27)
    businessA = await businessRepo.createBusiness(
      Business(
        id: 'biz-a',
        name: 'Apex Traders',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    // Seed Business B (Karnataka, 29) for business isolation test
    businessB = await businessRepo.createBusiness(
      Business(
        id: 'biz-b',
        name: 'Bliss Tech',
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

    // Seed customer under Business A
    customerA = await partyRepo.createParty(
      Party(
        id: 'cust-1',
        businessId: businessA.id,
        partyType: PartyType.customer,
        name: 'Acme Corporation',
        phone: '9123456780',
        billingStateCode: '27',
        billingStateName: 'Maharashtra',
        currentBalancePaise: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    // Seed goods product with 10 units initial stock
    goodsProduct = await productRepo.createProduct(
      Product(
        id: 'prod-goods',
        businessId: businessA.id,
        name: 'Wireless Mouse',
        sku: 'WM-001',
        itemType: ItemType.product,
        sellingPricePaise: 50000, // ₹500.00
        purchasePricePaise: 35000,
        currentStock: 10.0,
        openingStock: 10.0,
        unitId: unitPcsId,
        taxRateId: taxRate18Id,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    // Seed service item
    serviceProduct = await productRepo.createProduct(
      Product(
        id: 'prod-service',
        businessId: businessA.id,
        name: 'Hardware Setup',
        itemType: ItemType.service,
        sellingPricePaise: 100000, // ₹1,000.00
        purchasePricePaise: 0,
        currentStock: 0.0,
        openingStock: 0.0,
        unitId: unitPcsId,
        taxRateId: taxRate18Id,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  });

  tearDown(() async {
    await dbHelper.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Invoice Sequence and Numbering Tests', () {
    test('Sequential invoice number generation and padding', () async {
      final nextNumber1 = await invoiceRepo.getNextInvoiceNumberPreview(businessA.id);
      expect(nextNumber1, contains('INV-'));

      // Create and finalize first invoice
      final inv1 = Invoice(
        id: 'inv-seq-1',
        businessId: businessA.id,
        invoiceNumber: 'DRAFT',
        customerId: customerA.id,
        customerName: customerA.name,
        invoiceDate: DateTime.now().toUtc(),
        dueDate: DateTime.now().toUtc(),
        placeOfSupplyStateCode: '27',
        status: InvoiceStatus.draft,
        subtotalPaise: 50000,
        taxableAmountPaise: 50000,
        cgstPaise: 4500,
        sgstPaise: 4500,
        igstPaise: 0,
        roundOffPaise: 0,
        totalAmountPaise: 59000,
        balanceAmountPaise: 59000,
        items: [
          InvoiceItem(
            id: 'item-1',
            invoiceId: 'inv-seq-1',
            productId: goodsProduct.id,
            productName: goodsProduct.name,
            taxRateId: taxRate18Id,
            quantityScaled: 1000, // 1 unit
            unitCode: 'PCS',
            ratePaise: 50000,
            discountPaise: 0,
            taxableAmountPaise: 50000,
            cgstRateBasisPoints: 900,
            sgstRateBasisPoints: 900,
            cgstAmountPaise: 4500,
            sgstAmountPaise: 4500,
            totalAmountPaise: 59000,
            trackInventory: true,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        ],
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      final savedDraft = await invoiceRepo.saveDraft(inv1);
      expect(savedDraft.status, equals(InvoiceStatus.draft));
      expect(savedDraft.invoiceNumber, equals('DRAFT'));

      final finalized1 = await invoiceRepo.finalizeInvoice(savedDraft);
      expect(finalized1.status, equals(InvoiceStatus.finalized));
      expect(finalized1.invoiceNumber, isNot('DRAFT'));

      // Check second invoice number sequence increment
      final nextNumber2 = await invoiceRepo.getNextInvoiceNumberPreview(businessA.id);
      expect(nextNumber2, isNot(equals(finalized1.invoiceNumber)));
    });

    test('Business sequence isolation: sequences are isolated per business', () async {
      final prevA = await invoiceRepo.getNextInvoiceNumberPreview(businessA.id);
      final prevB = await invoiceRepo.getNextInvoiceNumberPreview(businessB.id);

      expect(prevA, equals(prevB)); // Both start at 1 for their respective businesses
    });
  });

  group('Draft vs Finalized Lifecycle & Stock Movement Tests', () {
    test('Draft invoice does NOT deduct stock or post accounting entries', () async {
      final initialStock = (await productRepo.getProductById(goodsProduct.id))!.currentStock;
      expect(initialStock, equals(10.0));

      final draft = Invoice(
        id: 'inv-draft-stock-test',
        businessId: businessA.id,
        invoiceNumber: 'DRAFT',
        customerId: customerA.id,
        customerName: customerA.name,
        invoiceDate: DateTime.now().toUtc(),
        dueDate: DateTime.now().toUtc(),
        placeOfSupplyStateCode: '27',
        status: InvoiceStatus.draft,
        subtotalPaise: 100000,
        taxableAmountPaise: 100000,
        cgstPaise: 0,
        sgstPaise: 0,
        igstPaise: 0,
        roundOffPaise: 0,
        totalAmountPaise: 100000,
        balanceAmountPaise: 100000,
        items: [
          InvoiceItem(
            id: 'item-draft-1',
            invoiceId: 'inv-draft-stock-test',
            productId: goodsProduct.id,
            productName: goodsProduct.name,
            taxRateId: taxRate18Id,
            quantityScaled: 2000, // 2 units
            unitCode: 'PCS',
            ratePaise: 50000,
            discountPaise: 0,
            taxableAmountPaise: 100000,
            cgstRateBasisPoints: 0,
            sgstRateBasisPoints: 0,
            totalAmountPaise: 100000,
            trackInventory: true,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        ],
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      await invoiceRepo.saveDraft(draft);

      // Verify product stock is completely unchanged
      final stockAfterDraft = (await productRepo.getProductById(goodsProduct.id))!.currentStock;
      expect(stockAfterDraft, equals(10.0));

      // Verify no stock movements recorded for this invoice
      final db = await dbHelper.database;
      final stockRows = await db.query(
        'stock_movements',
        where: 'reference_id = ?',
        whereArgs: [draft.id],
      );
      expect(stockRows.isEmpty, isTrue);

      // Verify customer balance unchanged
      final custAfterDraft = await partyRepo.getPartyById(customerA.id);
      expect(custAfterDraft!.currentBalancePaise, equals(0));
    });

    test('Finalizing invoice deducts stock for goods, skips services, and posts accounting', () async {
      final invoice = Invoice(
        id: 'inv-finalized-test',
        businessId: businessA.id,
        invoiceNumber: 'DRAFT',
        customerId: customerA.id,
        customerName: customerA.name,
        invoiceDate: DateTime.now().toUtc(),
        dueDate: DateTime.now().toUtc(),
        placeOfSupplyStateCode: '27',
        status: InvoiceStatus.draft,
        subtotalPaise: 200000,
        taxableAmountPaise: 200000,
        cgstPaise: 18000,
        sgstPaise: 18000,
        igstPaise: 0,
        roundOffPaise: 0,
        totalAmountPaise: 236000, // ₹2,360.00
        balanceAmountPaise: 236000,
        items: [
          // 3 units of goods (stock: 10 -> 7)
          InvoiceItem(
            id: 'item-goods-1',
            invoiceId: 'inv-finalized-test',
            productId: goodsProduct.id,
            productName: goodsProduct.name,
            taxRateId: taxRate18Id,
            quantityScaled: 3000, // 3 units
            unitCode: 'PCS',
            ratePaise: 50000,
            discountPaise: 0,
            taxableAmountPaise: 150000,
            cgstRateBasisPoints: 900,
            sgstRateBasisPoints: 900,
            cgstAmountPaise: 13500,
            sgstAmountPaise: 13500,
            totalAmountPaise: 177000,
            trackInventory: true,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
          // 1 unit of service (no stock deduction)
          InvoiceItem(
            id: 'item-serv-1',
            invoiceId: 'inv-finalized-test',
            productId: serviceProduct.id,
            productName: serviceProduct.name,
            taxRateId: taxRate18Id,
            quantityScaled: 1000, // 1 unit
            unitCode: 'PCS',
            ratePaise: 50000,
            discountPaise: 0,
            taxableAmountPaise: 50000,
            cgstRateBasisPoints: 900,
            sgstRateBasisPoints: 900,
            cgstAmountPaise: 4500,
            sgstAmountPaise: 4500,
            totalAmountPaise: 59000,
            trackInventory: false,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        ],
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      final finalized = await invoiceRepo.finalizeInvoice(invoice);

      expect(finalized.status, equals(InvoiceStatus.finalized));
      expect(finalized.invoiceNumber, isNot('DRAFT'));

      // 1. Stock check: goods deducted by exactly 3.0 units (10.0 -> 7.0)
      final goodsAfter = await productRepo.getProductById(goodsProduct.id);
      expect(goodsAfter!.currentStock, equals(7.0));

      // Service item stock remains 0.0 (non-inventory)
      final servAfter = await productRepo.getProductById(serviceProduct.id);
      expect(servAfter!.currentStock, equals(0.0));

      // Verify stock_movement record created
      final db = await dbHelper.database;
      final stockRows = await db.query(
        'stock_movements',
        where: 'reference_id = ?',
        whereArgs: [finalized.id],
      );
      expect(stockRows.length, equals(1));
      expect(stockRows.first['reference_type'], equals('SALE'));
      expect(stockRows.first['quantity_delta'], equals(-3000));

      // 2. Customer balance check: debited for grand total ₹2,360.00 (236000 paise)
      final customerAfter = await partyRepo.getPartyById(customerA.id);
      expect(customerAfter!.currentBalancePaise, equals(236000));

      // 3. Balanced Accounting check: sum of debits == sum of credits
      final ledgerRows = await db.query(
        'ledger_entries',
        where: 'transaction_id = ?',
        whereArgs: [finalized.id],
      );
      expect(ledgerRows.isNotEmpty, isTrue);

      int totalDebit = 0;
      int totalCredit = 0;
      for (final row in ledgerRows) {
        final debit = row['debit_paise'] as int? ?? 0;
        final credit = row['credit_paise'] as int? ?? 0;
        totalDebit += debit;
        totalCredit += credit;
      }
      expect(totalDebit, equals(totalCredit));
      expect(totalDebit, equals(finalized.totalAmountPaise)); // ₹2,360.00
    });

    test('Cancellation restores stock and reverses accounting entries', () async {
      final invoice = Invoice(
        id: 'inv-to-cancel',
        businessId: businessA.id,
        invoiceNumber: 'DRAFT',
        customerId: customerA.id,
        customerName: customerA.name,
        invoiceDate: DateTime.now().toUtc(),
        dueDate: DateTime.now().toUtc(),
        placeOfSupplyStateCode: '27',
        status: InvoiceStatus.draft,
        subtotalPaise: 50000,
        taxableAmountPaise: 50000,
        cgstPaise: 4500,
        sgstPaise: 4500,
        igstPaise: 0,
        roundOffPaise: 0,
        totalAmountPaise: 59000, // ₹590.00
        balanceAmountPaise: 59000,
        items: [
          InvoiceItem(
            id: 'item-cancel-1',
            invoiceId: 'inv-to-cancel',
            productId: goodsProduct.id,
            productName: goodsProduct.name,
            taxRateId: taxRate18Id,
            quantityScaled: 2000, // 2 units
            unitCode: 'PCS',
            ratePaise: 25000,
            discountPaise: 0,
            taxableAmountPaise: 50000,
            cgstRateBasisPoints: 900,
            sgstRateBasisPoints: 900,
            cgstAmountPaise: 4500,
            sgstAmountPaise: 4500,
            totalAmountPaise: 59000,
            trackInventory: true,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        ],
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      final finalized = await invoiceRepo.finalizeInvoice(invoice);

      // Stock was 10.0, 2 deducted -> 8.0
      final stockAfterFinalize = (await productRepo.getProductById(goodsProduct.id))!.currentStock;
      expect(stockAfterFinalize, equals(8.0));

      final custBalAfterFinalize = (await partyRepo.getPartyById(customerA.id))!.currentBalancePaise;
      expect(custBalAfterFinalize, equals(59000));

      // Now cancel the invoice
      final cancelled = await invoiceRepo.cancelInvoice(
        finalized.id,
        cancellationReason: 'Order cancelled by customer',
      );

      expect(cancelled.status, equals(InvoiceStatus.cancelled));
      expect(cancelled.cancellationReason, equals('Order cancelled by customer'));

      // Stock must be restored to 10.0
      final stockAfterCancel = (await productRepo.getProductById(goodsProduct.id))!.currentStock;
      expect(stockAfterCancel, equals(10.0));

      // Customer balance must be reversed to 0
      final custBalAfterCancel = (await partyRepo.getPartyById(customerA.id))!.currentBalancePaise;
      expect(custBalAfterCancel, equals(0));

      // Stock movement must show SALE_RETURN
      final db = await dbHelper.database;
      final returnMovement = await db.query(
        'stock_movements',
        where: 'reference_id = ? AND reference_type = ?',
        whereArgs: [finalized.id, 'SALE_RETURN'],
      );
      expect(returnMovement.length, equals(1));
      expect(returnMovement.first['quantity_delta'], equals(2000)); // +2 units restored
    });
  });
}
