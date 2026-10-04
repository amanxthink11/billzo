import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/application/reports/csv_export_helper.dart';
import 'package:billzo/core/money/money.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/reports/stock_valuation_report.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_product_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_report_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_tax_rate_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_unit_repository.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

class _MockPathProvider implements IAppPathProvider {
  final Directory tempDir;
  _MockPathProvider(this.tempDir);

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
  group('Phase 7 Pre-Flight Audit Regression Tests: Integer Paise & Zero Floating-Point Drift', () {
    test('CsvExportHelper.formatPaise executes 100% deterministic integer string formatting without float conversion', () {
      expect(CsvExportHelper.formatPaise(0), equals('0.00'));
      expect(CsvExportHelper.formatPaise(5), equals('0.05'));
      expect(CsvExportHelper.formatPaise(50), equals('0.50'));
      expect(CsvExportHelper.formatPaise(99), equals('0.99'));
      expect(CsvExportHelper.formatPaise(100), equals('1.00'));
      expect(CsvExportHelper.formatPaise(100000), equals('1000.00'));
      expect(CsvExportHelper.formatPaise(125075), equals('1250.75'));
      expect(CsvExportHelper.formatPaise(-4550), equals('-45.50'));
      expect(CsvExportHelper.formatPaise(-5), equals('-0.05'));

      // Very large values (> 2^31) that could suffer IEEE 754 precision drift if converted to double
      // ₹90,00,00,000.75 = 90,000,000,075 paise
      const largePaise = 90000000075;
      expect(CsvExportHelper.formatPaise(largePaise), equals('900000000.75'));
    });

    test('StockValuationItem computes exact integer paise cost and retail valuation for fractional inventory', () {
      // 1.250 Kg (scaled = 1250) of Premium Almonds @ ₹150.00/Kg cost (15000 paise), ₹200.00/Kg retail (20000 paise)
      // Expected Cost: 1.25 * 150.00 = 187.50 = 18750 paise
      // Expected Retail: 1.25 * 200.00 = 250.00 = 25000 paise
      const item = StockValuationItem(
        productId: 'prod-almonds',
        productName: 'California Almonds',
        unitCode: 'KG',
        currentStock: 1, // Whole units for display
        currentStockScaled: 1250, // 1.250 Kg internal representation
        purchasePricePaise: 15000,
        sellingPricePaise: 20000,
      );

      expect(item.costValuationPaise, equals(18750));
      expect(item.retailValuationPaise, equals(25000));
      expect(item.costValuation, equals(const Money(18750)));
      expect(item.retailValuation, equals(const Money(25000)));

      // 2.750 Meters (scaled = 2750) of Silk Fabric @ ₹333.33/Meter (33333 paise)
      // 2750 * 33333 = 91,665,750 / 1000 = 91665.75 -> rounded half-up = 91666 paise (₹916.66)
      const fabric = StockValuationItem(
        productId: 'prod-silk',
        productName: 'Raw Silk',
        unitCode: 'MTR',
        currentStock: 3,
        currentStockScaled: 2750,
        purchasePricePaise: 33333,
        sellingPricePaise: 50000,
      );

      expect(fabric.costValuationPaise, equals(91666));
      expect(fabric.retailValuationPaise, equals(137500)); // 2.750 * 500.00 = ₹1,375.00
    });

    test('StockValuationReport aggregates fractional inventory items with 100% integer paise fidelity', () {
      const item1 = StockValuationItem(
        productId: 'p1',
        productName: 'Item 1',
        unitCode: 'KG',
        currentStock: 1,
        currentStockScaled: 1500, // 1.500 Kg @ ₹100.00 = ₹150.00
        purchasePricePaise: 10000,
        sellingPricePaise: 15000,
      );

      const item2 = StockValuationItem(
        productId: 'p2',
        productName: 'Item 2',
        unitCode: 'LTR',
        currentStock: 2,
        currentStockScaled: 2500, // 2.500 Ltr @ ₹80.00 = ₹200.00
        purchasePricePaise: 8000,
        sellingPricePaise: 12000,
      );

      final report = StockValuationReport(
        businessId: 'biz-test',
        asOfDate: DateTime.now(),
        items: const [item1, item2],
        generatedAt: DateTime.now(),
      );

      // Cost: 15000 + 20000 = 35000 paise (₹350.00)
      // Retail: 22500 + 30000 = 52500 paise (₹525.00)
      expect(report.totalCostValuationPaise, equals(35000));
      expect(report.totalRetailValuationPaise, equals(52500));
      expect(report.totalCostValuation.formatted, equals('₹350.00'));
      expect(report.totalRetailValuation.formatted, equals('₹525.00'));
    });

    group('Database Integration: Fractional Stock Persistence & Valuation', () {
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
        tempDir = await Directory.systemTemp.createTemp('billzo_fp_audit_');
        dbHelper = DatabaseHelper.createForTesting(
          dbPath: inMemoryDatabasePath,
          pathProvider: _MockPathProvider(tempDir),
          dbFactory: databaseFactoryFfi,
        );

        businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
        productRepo = SqliteProductRepository(dbHelper);
        taxRepo = SqliteTaxRateRepository(dbHelper);
        unitRepo = SqliteUnitRepository(dbHelper);
        reportRepo = SqliteReportRepository(dbHelper);

        business = await businessRepo.createBusiness(
          Business(
            id: 'biz-fp-test',
            name: 'Spice Emporium',
            phone: '9822012345',
            stateCode: '27',
            stateName: 'Maharashtra',
            currencyCode: 'INR',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

        final units = await unitRepo.getUnits(business.id);
        final unitKg = units.firstWhere((u) => u.shortName == 'KG', orElse: () => units.first);
        final taxes = await taxRepo.getTaxRates(business.id);
        final tax5 = taxes.firstWhere((t) => t.rateBasisPoints == 500, orElse: () => taxes.first);

        // Product with 2.500 Kg stock @ ₹400.00/Kg cost, ₹600.00/Kg selling
        await productRepo.createProduct(
          Product(
            id: 'prod-saffron',
            businessId: business.id,
            name: 'Kashmiri Saffron',
            unitId: unitKg.id,
            taxRateId: tax5.id,
            itemType: ItemType.product,
            purchasePricePaise: 40000,
            sellingPricePaise: 60000,
            openingStock: 2.5,
            currentStock: 2.5,
            sku: 'SAFF-250',
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

      test('Report repository correctly preserves scaled stock and computes exact fractional valuation', () async {
        final report = await reportRepo.getStockValuationReport(business.id);
        expect(report.items.length, equals(1));

        final item = report.items.first;
        expect(item.productName, equals('Kashmiri Saffron'));
        expect(item.currentStockScaled, equals(2500)); // 2.500 Kg scaled
        expect(item.costValuationPaise, equals(100000)); // 2.5 * 400.00 = 1,000.00 INR = 100,000 paise
        expect(item.retailValuationPaise, equals(150000)); // 2.5 * 600.00 = 1,500.00 INR = 150,000 paise

        // Verify CSV export
        final csv = CsvExportHelper.exportStockValuation(report);
        expect(csv.contains('1000.00'), isTrue);
        expect(csv.contains('1500.00'), isTrue);
      });
    });
  });
}
