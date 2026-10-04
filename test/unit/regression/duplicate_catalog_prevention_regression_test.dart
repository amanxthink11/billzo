import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_product_repository.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

class _TestPathProvider implements IAppPathProvider {
  final Directory tempDir;
  _TestPathProvider(this.tempDir);

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
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  const uuid = Uuid();

  late Directory tempDir;
  late DatabaseHelper dbHelper;
  late SqliteProductRepository productRepo;
  const businessId = 'biz-catalog-test';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_catalog_dup_test_');
    final dbPath = p.join(tempDir.path, 'test_catalog.db');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: dbPath,
      pathProvider: _TestPathProvider(tempDir),
    );
    productRepo = SqliteProductRepository(dbHelper);

    // Seed test business in SQLite database
    final db = await dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('businesses', {
      'id': businessId,
      'name': 'Catalog Test Store',
      'phone': '9876543210',
      'state_code': '27',
      'state_name': 'Maharashtra',
      'country': 'India',
      'currency_code': 'INR',
      'currency_symbol': '₹',
      'created_at': now,
      'updated_at': now,
      'sync_version': 1,
      'sync_status': 'synced',
    });
    await db.insert('units', {
      'id': 'unit-srv',
      'business_id': businessId,
      'code': 'SRV',
      'name': 'Services',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('tax_rates', {
      'id': 'tax-18',
      'business_id': businessId,
      'name': 'GST 18%',
      'rate_basis_points': 1800,
      'cgst_basis_points': 900,
      'sgst_basis_points': 900,
      'igst_basis_points': 1800,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() async {
    await dbHelper.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Catalog Duplicate Prevention Regression Tests', () {
    test('isProductNameTaken detects duplicate product/service names case-insensitively and with trimming', () async {
      // 1. Initially no product with name exists
      expect(await productRepo.isProductNameTaken(businessId, 'WhatsApp Business API Starter Plan'), isFalse);

      // 2. Create the service item
      final serviceProduct = Product(
        id: uuid.v4(),
        businessId: businessId,
        name: 'WhatsApp Business API Starter Plan',
        itemType: ItemType.service,
        unitId: 'unit-srv',
        taxRateId: 'tax-18',
        sellingPricePaise: 99900,
        purchasePricePaise: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await productRepo.createProduct(serviceProduct);

      // 3. Exact match is taken
      expect(await productRepo.isProductNameTaken(businessId, 'WhatsApp Business API Starter Plan'), isTrue);

      // 4. Case-insensitive match is taken
      expect(await productRepo.isProductNameTaken(businessId, 'whatsapp business api starter plan'), isTrue);

      // 5. Leading/trailing whitespace match is taken
      expect(await productRepo.isProductNameTaken(businessId, '   WhatsApp Business API Starter Plan   '), isTrue);

      // 6. When editing the same product, excludeProductId allows keeping the current name
      expect(
        await productRepo.isProductNameTaken(
          businessId,
          'WhatsApp Business API Starter Plan',
          excludeProductId: serviceProduct.id,
        ),
        isFalse,
      );

      // 7. But another new product cannot use that name
      expect(
        await productRepo.isProductNameTaken(
          businessId,
          'WhatsApp Business API Starter Plan',
          excludeProductId: uuid.v4(),
        ),
        isTrue,
      );
    });
  });
}
