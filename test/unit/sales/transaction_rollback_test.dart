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

  late Business testBusiness;
  late Party testCustomer;
  late Product validProduct;
  late String taxRate18Id;
  late String unitPcsId;

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
    productRepo = SqliteProductRepository(dbHelper);
    invoiceRepo = SqliteInvoiceRepository(dbHelper);

    // Seed test business
    testBusiness = await businessRepo.createBusiness(
      Business(
        id: 'biz-rollback',
        name: 'Rollback Testing Labs',
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

    // Seed customer
    testCustomer = await partyRepo.createParty(
      Party(
        id: 'cust-rb-1',
        businessId: testBusiness.id,
        partyType: PartyType.customer,
        name: 'Safe Systems Inc',
        phone: '9876500000',
        currentBalancePaise: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    // Seed valid product with 20.0 stock
    validProduct = await productRepo.createProduct(
      Product(
        id: 'prod-rb-valid',
        businessId: testBusiness.id,
        name: 'Standard Keyboard',
        sku: 'SKB-001',
        itemType: ItemType.product,
        sellingPricePaise: 150000, // ₹1,500.00
        purchasePricePaise: 100000,
        currentStock: 20.0,
        openingStock: 20.0,
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

  group('Mandatory Transaction Rollback Verification', () {
    test('Intentional failure during invoice finalization triggers 100% database rollback', () async {
      final initialProduct = await productRepo.getProductById(validProduct.id);
      expect(initialProduct!.currentStock, equals(20.0));

      final initialCustomer = await partyRepo.getPartyById(testCustomer.id);
      expect(initialCustomer!.currentBalancePaise, equals(0));

      final previewBefore = await invoiceRepo.getNextInvoiceNumberPreview(testBusiness.id);

      // Create an invoice where item 1 is valid, but item 2 intentionally violates Foreign Key constraint
      // by referencing a non-existent product ID
      final malformedInvoice = Invoice(
        id: 'inv-doomed-to-fail',
        businessId: testBusiness.id,
        invoiceNumber: 'DRAFT',
        customerId: testCustomer.id,
        customerName: testCustomer.name,
        invoiceDate: DateTime.now().toUtc(),
        dueDate: DateTime.now().toUtc(),
        placeOfSupplyStateCode: '27',
        status: InvoiceStatus.draft,
        subtotalPaise: 300000,
        taxableAmountPaise: 300000,
        cgstPaise: 0,
        sgstPaise: 0,
        igstPaise: 0,
        roundOffPaise: 0,
        totalAmountPaise: 300000,
        balanceAmountPaise: 300000,
        items: [
          // Item 1: Valid goods product (5 units)
          InvoiceItem(
            id: 'item-valid-1',
            invoiceId: 'inv-doomed-to-fail',
            productId: validProduct.id,
            productName: validProduct.name,
            taxRateId: taxRate18Id,
            quantityScaled: 5000, // 5 units
            unitCode: 'PCS',
            ratePaise: 150000,
            discountPaise: 0,
            taxableAmountPaise: 150000,
            totalAmountPaise: 150000,
            trackInventory: true,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
          // Item 2: Invalid product that triggers a Foreign Key constraint violation in SQLite
          InvoiceItem(
            id: 'item-invalid-fk',
            invoiceId: 'inv-doomed-to-fail',
            productId: 'non-existent-product-id-999',
            productName: 'Ghost Item',
            taxRateId: taxRate18Id,
            quantityScaled: 1000,
            unitCode: 'PCS',
            ratePaise: 150000,
            discountPaise: 0,
            taxableAmountPaise: 150000,
            totalAmountPaise: 150000,
            trackInventory: true,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        ],
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      // Attempt finalization; this MUST throw an exception
      expect(
        () async => await invoiceRepo.finalizeInvoice(malformedInvoice),
        throwsA(isA<Exception>()),
      );

      // Verify state after aborted transaction:
      final db = await dbHelper.database;

      // 1. No invoice created or saved in the database
      final invoiceRows = await db.query(
        'invoices',
        where: 'id = ?',
        whereArgs: [malformedInvoice.id],
      );
      expect(invoiceRows.isEmpty, isTrue, reason: 'Invoice must not exist after rollback');

      // 2. No items inserted into invoice_items
      final itemRows = await db.query(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [malformedInvoice.id],
      );
      expect(itemRows.isEmpty, isTrue, reason: 'Invoice items must not exist after rollback');

      // 3. Stock of valid product was NOT deducted (must still be 20.0)
      final productAfter = await productRepo.getProductById(validProduct.id);
      expect(productAfter!.currentStock, equals(20.0), reason: 'Stock must not be deducted on failed finalization');

      // 4. No stock movements created
      final stockMovements = await db.query(
        'stock_movements',
        where: 'reference_id = ?',
        whereArgs: [malformedInvoice.id],
      );
      expect(stockMovements.isEmpty, isTrue, reason: 'Stock movements must be completely rolled back');

      // 5. No ledger entries created
      final ledgerEntries = await db.query(
        'ledger_entries',
        where: 'transaction_id = ?',
        whereArgs: [malformedInvoice.id],
      );
      expect(ledgerEntries.isEmpty, isTrue, reason: 'Ledger entries must be completely rolled back');

      // 6. Customer balance untouched
      final customerAfter = await partyRepo.getPartyById(testCustomer.id);
      expect(customerAfter!.currentBalancePaise, equals(0), reason: 'Customer balance must not change on failed finalization');

      // 7. Sequence number was not consumed or corrupted
      final previewAfter = await invoiceRepo.getNextInvoiceNumberPreview(testBusiness.id);
      expect(previewAfter, equals(previewBefore), reason: 'Invoice sequence must not be corrupted or incremented on failure');
    });
  });
}
