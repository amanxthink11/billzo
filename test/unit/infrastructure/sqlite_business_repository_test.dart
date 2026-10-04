import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

class TestPathProvider implements IAppPathProvider {
  final Directory tempDir;
  TestPathProvider(this.tempDir);

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
  late String dbFilePath;
  const uuid = Uuid();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_business_repo_test_');
    dbFilePath = p.join(tempDir.path, 'test_billzo.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SqliteBusinessRepository Tests', () {
    test('Empty database reports no configured business', () async {
      final helper = DatabaseHelper.createForTesting(
        dbPath: dbFilePath,
        pathProvider: TestPathProvider(tempDir),
      );
      final repo = SqliteBusinessRepository(dbHelper: helper);

      expect(await repo.hasConfiguredBusiness(), isFalse);
      expect(await repo.getActiveBusiness(), isNull);
      await helper.close();
    });

    test('Creates business, seeds defaults, and activates profile in atomic transaction', () async {
      final helper = DatabaseHelper.createForTesting(
        dbPath: dbFilePath,
        pathProvider: TestPathProvider(tempDir),
      );
      final repo = SqliteBusinessRepository(dbHelper: helper);

      final business = Business(
        id: uuid.v4(),
        name: 'Metro Retail Mart',
        tradeName: 'Metro Store',
        phone: '9820098200',
        email: 'billing@metroretail.com',
        stateCode: '27',
        stateName: 'Maharashtra',
        city: 'Mumbai',
        pincode: '400001',
        gstin: '27AAAAA0000A1Z5',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      final created = await repo.createBusiness(business);
      expect(created.id, equals(business.id));
      expect(created.name, equals('Metro Retail Mart'));

      // Check hasConfiguredBusiness is now true
      expect(await repo.hasConfiguredBusiness(), isTrue);

      // Check getActiveBusiness returns the created record
      final active = await repo.getActiveBusiness();
      expect(active, isNotNull);
      expect(active!.id, equals(business.id));
      expect(active.name, equals('Metro Retail Mart'));
      expect(active.gstin, equals('27AAAAA0000A1Z5'));

      // Verify default tax rates were seeded
      final db = await helper.database;
      final rates = await db.query('tax_rates', where: 'business_id = ?', whereArgs: [business.id]);
      expect(rates.length, equals(5)); // 0%, 5%, 12%, 18%, 28%

      // Verify default units were seeded (6 goods units + 7 standard service units)
      final units = await db.query('units', where: 'business_id = ?', whereArgs: [business.id]);
      expect(units.length, equals(13));

      // Verify default sequences were seeded
      final sequences = await db.query('invoice_sequences', where: 'business_id = ?', whereArgs: [business.id]);
      expect(sequences.length, equals(5)); // INVOICE, ESTIMATE, PURCHASE, CN, DN

      await helper.close();
    });

    test('Rejects invalid business data at domain boundary', () async {
      final helper = DatabaseHelper.createForTesting(
        dbPath: dbFilePath,
        pathProvider: TestPathProvider(tempDir),
      );
      final repo = SqliteBusinessRepository(dbHelper: helper);

      final invalidBusiness = Business(
        id: uuid.v4(),
        name: '', // Empty name!
        phone: '9820098200',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      expect(
        () async => await repo.createBusiness(invalidBusiness),
        throwsA(isA<ArgumentError>()),
      );

      await helper.close();
    });

    test('Updates business profile details successfully', () async {
      final helper = DatabaseHelper.createForTesting(
        dbPath: dbFilePath,
        pathProvider: TestPathProvider(tempDir),
      );
      final repo = SqliteBusinessRepository(dbHelper: helper);

      final business = Business(
        id: uuid.v4(),
        name: 'Initial Shop',
        phone: '9820098200',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      await repo.createBusiness(business);

      // Update name and phone
      final modified = business.copyWith(
        name: 'Updated Shop Name',
        phone: '9811198111',
      );

      final updated = await repo.updateBusiness(modified);
      expect(updated.name, equals('Updated Shop Name'));
      expect(updated.phone, equals('9811198111'));

      final retrieved = await repo.getActiveBusiness();
      expect(retrieved!.name, equals('Updated Shop Name'));
      expect(retrieved.phone, equals('9811198111'));

      await helper.close();
    });

    test('Data survives database close and application restart simulation', () async {
      // Session 1: Create business and close DB
      final helper1 = DatabaseHelper.createForTesting(
        dbPath: dbFilePath,
        pathProvider: TestPathProvider(tempDir),
      );
      final repo1 = SqliteBusinessRepository(dbHelper: helper1);

      final business = Business(
        id: uuid.v4(),
        name: 'Surviving Enterprise',
        phone: '9899998999',
        stateCode: '07',
        stateName: 'Delhi',
        city: 'New Delhi',
        pincode: '110001',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      await repo1.createBusiness(business);
      await helper1.close();

      // Session 2: Reopen a fresh DatabaseHelper on the same file path
      final helper2 = DatabaseHelper.createForTesting(
        dbPath: dbFilePath,
        pathProvider: TestPathProvider(tempDir),
      );
      final repo2 = SqliteBusinessRepository(dbHelper: helper2);

      expect(await repo2.hasConfiguredBusiness(), isTrue);
      final reloaded = await repo2.getActiveBusiness();
      expect(reloaded, isNotNull);
      expect(reloaded!.id, equals(business.id));
      expect(reloaded.name, equals('Surviving Enterprise'));
      expect(reloaded.city, equals('New Delhi'));
      expect(reloaded.pincode, equals('110001'));

      await helper2.close();
    });
  });
}
