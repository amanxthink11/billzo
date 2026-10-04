import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/category.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_category_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_product_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_unit_repository.dart';
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
  late SqliteCategoryRepository categoryRepo;
  late SqliteUnitRepository unitRepo;
  late SqliteProductRepository productRepo;
  late Business testBusiness;
  late Category testCategory;
  late String testUnitId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_prod_repo_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );
    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    categoryRepo = SqliteCategoryRepository(dbHelper);
    unitRepo = SqliteUnitRepository(dbHelper);
    productRepo = SqliteProductRepository(dbHelper);

    testBusiness = await businessRepo.createBusiness(
      Business(
        id: 'biz-prod-test',
        name: 'Apex Supermart',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    testCategory = await categoryRepo.createCategory(
      Category(
        id: 'cat-electronics',
        businessId: testBusiness.id,
        name: 'Consumer Electronics',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    final units = await unitRepo.getUnits(testBusiness.id);
    testUnitId = units.first.id;
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SqliteProductRepository Infrastructure Tests', () {
    final now = DateTime.now().toUtc();

    test('Creates goods item and establishes opening stock in stock_movements ledger', () async {
      final product = await productRepo.createProduct(
        Product(
          id: 'prod-mouse-01',
          businessId: testBusiness.id,
          categoryId: testCategory.id,
          unitId: testUnitId,
          name: 'Logitech Wireless Mouse M170',
          sku: 'LOG-M170-GRY',
          hsnSacCode: '84716060',
          itemType: ItemType.product,
          purchasePricePaise: 50000, // ₹500.00
          sellingPricePaise: 79900,  // ₹799.00
          mrpPaise: 89900,           // ₹899.00
          openingStock: 50.0,
          currentStock: 50.0,
          createdAt: now,
          updatedAt: now,
        ),
        openingStockNotes: 'Initial stock intake from physical inventory',
      );

      expect(product.id, equals('prod-mouse-01'));
      expect(product.openingStock, equals(50.0));

      // Verify stock ledger entry created in stock_movements
      final ledger = await productRepo.getStockLedger('prod-mouse-01');
      expect(ledger.length, equals(1));
      expect(ledger.first.quantityChanged, equals(50.0));
      expect(ledger.first.stockAfter, equals(50.0));
      expect(ledger.first.costPerUnitPaise, equals(50000));
      expect(ledger.first.notes, contains('physical inventory'));
    });

    test('Creates Service item without physical stock tracking', () async {
      final service = await productRepo.createProduct(
        Product(
          id: 'srv-repair-01',
          businessId: testBusiness.id,
          unitId: testUnitId,
          name: 'Annual Maintenance Service',
          sku: 'SRV-AMC-YEAR',
          hsnSacCode: '998713', // 6-digit SAC
          itemType: ItemType.service,
          sellingPricePaise: 250000,
          openingStock: 0.0,
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(service.id, equals('srv-repair-01'));
      expect(service.isService, isTrue);

      final ledger = await productRepo.getStockLedger('srv-repair-01');
      expect(ledger, isEmpty);
    });

    test('Enforces SKU uniqueness within the business', () async {
      await productRepo.createProduct(
        Product(
          id: 'prod-sku-1',
          businessId: testBusiness.id,
          unitId: testUnitId,
          name: 'USB-C Cable 1m',
          sku: 'CBL-USBC-1M',
          sellingPricePaise: 29900,
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Attempting to create duplicate SKU in same business should throw StateError
      expect(
        () => productRepo.createProduct(
          Product(
            id: 'prod-sku-2',
            businessId: testBusiness.id,
            unitId: testUnitId,
            name: 'Another Brand Cable',
            sku: 'CBL-USBC-1M',
            sellingPricePaise: 19900,
            createdAt: now,
            updatedAt: now,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Search products by name, SKU, and HSN/SAC', () async {
      await productRepo.createProduct(
        Product(
          id: 'prod-s1',
          businessId: testBusiness.id,
          unitId: testUnitId,
          name: 'Dell Optical Mouse',
          sku: 'DEL-MS-116',
          hsnSacCode: '84716060',
          sellingPricePaise: 35000,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await productRepo.createProduct(
        Product(
          id: 'prod-s2',
          businessId: testBusiness.id,
          unitId: testUnitId,
          name: 'HP Keyboard 150',
          sku: 'HP-KB-150',
          hsnSacCode: '84716040',
          sellingPricePaise: 65000,
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Search by name
      final nameMatches = await productRepo.getProducts(
        businessId: testBusiness.id,
        searchQuery: 'Optical',
      );
      expect(nameMatches.length, equals(1));
      expect(nameMatches.first.name, equals('Dell Optical Mouse'));

      // Search by SKU
      final skuMatches = await productRepo.getProducts(
        businessId: testBusiness.id,
        searchQuery: 'HP-KB',
      );
      expect(skuMatches.length, equals(1));
      expect(skuMatches.first.name, equals('HP Keyboard 150'));

      // Search by HSN
      final hsnMatches = await productRepo.getProducts(
        businessId: testBusiness.id,
        searchQuery: '84716060',
      );
      expect(hsnMatches.length, equals(1));
    });

    test('Soft deletion protects historical integrity', () async {
      final product = await productRepo.createProduct(
        Product(
          id: 'prod-del-test',
          businessId: testBusiness.id,
          unitId: testUnitId,
          name: 'Temporary Item',
          sellingPricePaise: 10000,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await productRepo.softDeleteProduct(product.id);
      final fetched = await productRepo.getProductById(product.id);
      expect(fetched, isNull); // Excluded from active lookups
    });
  });

  test('Product catalog data survives application restart simulation', () async {
    final diskDbPath = '${tempDir.path}${Platform.pathSeparator}restart_prod_test.db';
    final diskHelper = DatabaseHelper.createForTesting(
      dbPath: diskDbPath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );
    final diskBusinessRepo = SqliteBusinessRepository(dbHelper: diskHelper);
    final diskProductRepo = SqliteProductRepository(diskHelper);
    final diskUnitRepo = SqliteUnitRepository(diskHelper);

    final biz = await diskBusinessRepo.createBusiness(
      Business(
        id: 'biz-disk-prod',
        name: 'Persistent Retailers',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    final units = await diskUnitRepo.getUnits(biz.id);

    await diskProductRepo.createProduct(
      Product(
        id: 'persistent-prod-1',
        businessId: biz.id,
        unitId: units.first.id,
        name: 'Samsung 24-inch Monitor',
        sku: 'SAM-MON-24',
        hsnSacCode: '85285200',
        sellingPricePaise: 899900,
        purchasePricePaise: 720000,
        openingStock: 12.0,
        currentStock: 12.0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
      openingStockNotes: 'Initial opening stock',
    );

    // Close database to simulate app termination
    await diskHelper.close();

    // Reopen database
    final reopenedHelper = DatabaseHelper.createForTesting(
      dbPath: diskDbPath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );
    final reopenedProductRepo = SqliteProductRepository(reopenedHelper);

    final restoredProduct = await reopenedProductRepo.getProductById('persistent-prod-1');
    expect(restoredProduct, isNotNull);
    expect(restoredProduct!.name, equals('Samsung 24-inch Monitor'));
    expect(restoredProduct.sellingPricePaise, equals(899900));

    final restoredLedger = await reopenedProductRepo.getStockLedger('persistent-prod-1');
    expect(restoredLedger.length, equals(1));
    expect(restoredLedger.first.quantityChanged, equals(12.0));

    await reopenedHelper.close();
  });
}
