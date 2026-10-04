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

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_cat_repo_test_');
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
        id: 'biz-cat-test',
        name: 'Apex Supermart',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
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

  group('SqliteCategoryRepository Infrastructure Tests', () {
    final now = DateTime.now().toUtc();

    test('Creates, retrieves, and updates category', () async {
      final category = await categoryRepo.createCategory(
        Category(
          id: 'cat-grocery',
          businessId: testBusiness.id,
          name: 'Grocery & Staples',
          colorHex: '#10B981',
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(category.id, equals('cat-grocery'));
      expect(category.name, equals('Grocery & Staples'));

      // Update name
      final updated = await categoryRepo.updateCategory(
        category.copyWith(name: 'Grocery & Food Essentials'),
      );
      expect(updated.name, equals('Grocery & Food Essentials'));

      final fetched = await categoryRepo.getCategoryById('cat-grocery');
      expect(fetched, isNotNull);
      expect(fetched!.name, equals('Grocery & Food Essentials'));
    });

    test('Supports parent-child hierarchy', () async {
      final parent = await categoryRepo.createCategory(
        Category(
          id: 'cat-parent',
          businessId: testBusiness.id,
          name: 'Beverages',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final child = await categoryRepo.createCategory(
        Category(
          id: 'cat-child',
          businessId: testBusiness.id,
          parentId: parent.id,
          name: 'Cold Pressed Juices',
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(child.parentId, equals('cat-parent'));

      // Deleting parent when child exists must throw
      expect(
        () => categoryRepo.softDeleteCategory(parent.id),
        throwsA(isA<StateError>()),
      );
    });

    test('Prevents destructive deletion when active products reference category', () async {
      final category = await categoryRepo.createCategory(
        Category(
          id: 'cat-stationery',
          businessId: testBusiness.id,
          name: 'Stationery',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final units = await unitRepo.getUnits(testBusiness.id);

      await productRepo.createProduct(
        Product(
          id: 'prod-pen',
          businessId: testBusiness.id,
          categoryId: category.id,
          unitId: units.first.id,
          name: 'Ballpoint Pen Blue',
          sellingPricePaise: 1000,
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Attempting to delete category must throw StateError
      expect(
        () => categoryRepo.softDeleteCategory(category.id),
        throwsA(isA<StateError>()),
      );

      // Verify canDeleteCategory reports false
      final canDelete = await categoryRepo.canDeleteCategory(category.id);
      expect(canDelete, isFalse);
    });

    test('Allows safe soft-deletion when no products or subcategories reference it', () async {
      final category = await categoryRepo.createCategory(
        Category(
          id: 'cat-unused',
          businessId: testBusiness.id,
          name: 'Unused Category',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final canDelete = await categoryRepo.canDeleteCategory(category.id);
      expect(canDelete, isTrue);

      await categoryRepo.softDeleteCategory(category.id);
      final fetched = await categoryRepo.getCategoryById(category.id);
      expect(fetched, isNull);
    });
  });
}
