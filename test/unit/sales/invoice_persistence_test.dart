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

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_invoice_persistence_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('Invoice and line items survive complete application restart simulation', () async {
    final diskDbPath = '${tempDir.path}${Platform.pathSeparator}restart_invoice_test.db';

    // 1. Initial Launch
    final helper1 = DatabaseHelper.createForTesting(
      dbPath: diskDbPath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );
    final bizRepo1 = SqliteBusinessRepository(dbHelper: helper1);
    final partyRepo1 = SqlitePartyRepository(helper1);
    final productRepo1 = SqliteProductRepository(helper1);
    final invoiceRepo1 = SqliteInvoiceRepository(helper1);

    final biz = await bizRepo1.createBusiness(
      Business(
        id: 'biz-restart-test',
        name: 'Persistent Mega Store',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    final db = await helper1.database;
    final taxRateRows = await db.query('tax_rates', where: 'business_id = ?', whereArgs: [biz.id]);
    final taxRate18Id = taxRateRows.firstWhere((r) => r['rate_basis_points'] == 1800)['id'] as String;

    final unitRows = await db.query('units', where: 'business_id = ?', whereArgs: [biz.id]);
    final unitPcsId = unitRows.firstWhere((u) => u['code'] == 'PCS')['id'] as String;

    final customer = await partyRepo1.createParty(
      Party(
        id: 'cust-persist-1',
        businessId: biz.id,
        partyType: PartyType.customer,
        name: 'Persistent Customer Corp',
        phone: '9988776655',
        currentBalancePaise: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    final product = await productRepo1.createProduct(
      Product(
        id: 'prod-persist-1',
        businessId: biz.id,
        name: '4K Display Monitor',
        sku: 'MON-4K',
        itemType: ItemType.product,
        sellingPricePaise: 2500000, // ₹25,000.00
        purchasePricePaise: 2000000,
        currentStock: 15.0,
        openingStock: 15.0,
        unitId: unitPcsId,
        taxRateId: taxRate18Id,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    final invoice = Invoice(
      id: 'inv-persisted-1',
      businessId: biz.id,
      invoiceNumber: 'DRAFT',
      customerId: customer.id,
      customerName: customer.name,
      customerPhone: customer.phone,
      invoiceDate: DateTime.now().toUtc(),
      dueDate: DateTime.now().toUtc(),
      placeOfSupplyStateCode: '27',
      status: InvoiceStatus.draft,
      subtotalPaise: 5000000,
      taxableAmountPaise: 5000000,
      cgstPaise: 450000,
      sgstPaise: 450000,
      igstPaise: 0,
      roundOffPaise: 0,
      totalAmountPaise: 5900000,
      balanceAmountPaise: 5900000,
      notes: 'Please deliver to warehouse gate 2',
      items: [
        InvoiceItem(
          id: 'item-persisted-1',
          invoiceId: 'inv-persisted-1',
          productId: product.id,
          productName: product.name,
          taxRateId: taxRate18Id,
          quantityScaled: 2000, // 2 units
          unitCode: 'PCS',
          ratePaise: 2500000,
          discountPaise: 0,
          taxableAmountPaise: 5000000,
          cgstRateBasisPoints: 900,
          sgstRateBasisPoints: 900,
          cgstAmountPaise: 450000,
          sgstAmountPaise: 450000,
          totalAmountPaise: 5900000,
          trackInventory: true,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      ],
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );

    final finalizedInvoice = await invoiceRepo1.finalizeInvoice(invoice);
    final allocatedNumber = finalizedInvoice.invoiceNumber;
    expect(allocatedNumber, isNot('DRAFT'));

    // Verify stock deducted in session 1
    final stock1 = (await productRepo1.getProductById(product.id))!.currentStock;
    expect(stock1, equals(13.0));

    // 2. Simulate App Termination (Close DB connection)
    await helper1.close();

    // 3. Second Launch (Reopen DB connection from disk file)
    final helper2 = DatabaseHelper.createForTesting(
      dbPath: diskDbPath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );
    final invoiceRepo2 = SqliteInvoiceRepository(helper2);
    final productRepo2 = SqliteProductRepository(helper2);
    final partyRepo2 = SqlitePartyRepository(helper2);

    // Retrieve invoice and verify completeness
    final retrieved = await invoiceRepo2.getInvoiceById(finalizedInvoice.id);
    expect(retrieved, isNotNull);
    expect(retrieved!.id, equals(finalizedInvoice.id));
    expect(retrieved.invoiceNumber, equals(allocatedNumber));
    expect(retrieved.status, equals(InvoiceStatus.finalized));
    expect(retrieved.totalAmountPaise, equals(5900000));
    expect(retrieved.notes, equals('Please deliver to warehouse gate 2'));
    expect(retrieved.items.length, equals(1));
    expect(retrieved.items.first.productName, equals('4K Display Monitor'));
    expect(retrieved.items.first.quantity, equals(2.0));
    expect(retrieved.items.first.taxAmountPaise, equals(900000));

    // Verify stock remains persistent
    final stock2 = (await productRepo2.getProductById(product.id))!.currentStock;
    expect(stock2, equals(13.0));

    // Verify customer balance remains persistent
    final customer2 = await partyRepo2.getPartyById(customer.id);
    expect(customer2!.currentBalancePaise, equals(5900000));

    await helper2.close();
  });
}
