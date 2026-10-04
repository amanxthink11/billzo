import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/application/reports/csv_export_helper.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_product_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_report_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_tax_rate_repository.dart';
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
  late SqliteProductRepository productRepo;
  late SqliteTaxRateRepository taxRepo;
  late SqliteUnitRepository unitRepo;
  late SqliteReportRepository reportRepo;

  late Business business;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_stock_val_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );

    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    productRepo = SqliteProductRepository(dbHelper);
    taxRepo = SqliteTaxRateRepository(dbHelper);
    unitRepo = SqliteUnitRepository(dbHelper);
    reportRepo = SqliteReportRepository(dbHelper);

    business = await businessRepo.createBusiness(
      Business(
        id: 'biz-stock-val',
        name: 'Nexus Electronics',
        phone: '9888812345',
        stateCode: '27',
        stateName: 'Maharashtra',
        currencyCode: 'INR',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final units = await unitRepo.getUnits(business.id);
    final unit = units.firstWhere((u) => u.shortName == 'BOX', orElse: () => units.first);

    final taxes = await taxRepo.getTaxRates(business.id);
    final tax18 = taxes.firstWhere((t) => t.rateBasisPoints == 1800, orElse: () => taxes.first);

    // Product 1: 10 units in stock @ 600 cost, 1000 selling
    await productRepo.createProduct(
      Product(
        id: 'prod-item-1',
        businessId: business.id,
        name: 'Router AC1200',
        unitId: unit.id,
        taxRateId: tax18.id,
        itemType: ItemType.product,
        purchasePricePaise: 60000,
        sellingPricePaise: 100000,
        openingStock: 10.0,
        currentStock: 10.0,
        sku: 'RTR-1200',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // Product 2: 5 units in stock @ 2000 cost, 3000 selling
    await productRepo.createProduct(
      Product(
        id: 'prod-item-2',
        businessId: business.id,
        name: 'Switch Gigabit 24-Port',
        unitId: unit.id,
        taxRateId: tax18.id,
        itemType: ItemType.product,
        purchasePricePaise: 200000,
        sellingPricePaise: 300000,
        openingStock: 5.0,
        currentStock: 5.0,
        sku: 'SW-24G',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Stock Valuation Report Tests', () {
    test('Calculates valuation at cost, valuation at retail, and potential profit in integer paise', () async {
      final report = await reportRepo.getStockValuationReport(business.id);

      expect(report.items.length, equals(2));

      // Product 1: 10 * 60000 = 600000 paise (6,000 INR); Retail = 10 * 100000 = 1000000 paise (10,000 INR)
      final p1 = report.items.firstWhere((i) => i.productName == 'Router AC1200');
      expect(p1.currentStock, equals(10));
      expect(p1.costValuationPaise, equals(600000));
      expect(p1.retailValuationPaise, equals(1000000));
      expect(p1.retailValuationPaise - p1.costValuationPaise, equals(400000)); // 4,000 INR

      // Product 2: 5 * 200000 = 1000000 paise (10,000 INR); Retail = 5 * 300000 = 1500000 paise (15,000 INR)
      final p2 = report.items.firstWhere((i) => i.productName == 'Switch Gigabit 24-Port');
      expect(p2.currentStock, equals(5));
      expect(p2.costValuationPaise, equals(1000000));
      expect(p2.retailValuationPaise, equals(1500000));
      expect(p2.retailValuationPaise - p2.costValuationPaise, equals(500000));

      // Grand Totals: Cost = 16,000 INR (1600000 paise), Retail = 25,000 INR (2500000 paise), Profit = 9,000 INR (900000 paise)
      expect(report.totalCostValuationPaise, equals(1600000));
      expect(report.totalRetailValuationPaise, equals(2500000));
      expect(report.totalRetailValuationPaise - report.totalCostValuationPaise, equals(900000));

      // Test CSV Export
      final csv = CsvExportHelper.exportStockValuation(report);
      expect(csv.contains('Router AC1200'), isTrue);
      expect(csv.contains('RTR-1200'), isTrue);
      expect(csv.contains('6000.00'), isTrue);
      expect(csv.contains('10000.00'), isTrue);
    });
  });
}
