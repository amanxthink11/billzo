import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/unit_of_measurement.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
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
  late SqliteUnitRepository unitRepo;
  late Business testBusiness;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_unit_repo_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );
    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    unitRepo = SqliteUnitRepository(dbHelper);

    testBusiness = await businessRepo.createBusiness(
      Business(
        id: 'biz-unit-test',
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

  group('SqliteUnitRepository Infrastructure Tests', () {
    final now = DateTime.now().toUtc();

    test('Verifies standard seeded units exist for onboarded business', () async {
      final units = await unitRepo.getUnits(testBusiness.id);
      expect(units.isNotEmpty, isTrue);

      final codes = units.map((u) => u.shortName).toSet();
      expect(codes.contains('PCS'), isTrue);
      expect(codes.contains('BOX'), isTrue);
      expect(codes.contains('KG'), isTrue);
      expect(codes.contains('LTR'), isTrue);
      expect(codes.contains('MTR'), isTrue);
      expect(codes.contains('SET'), isTrue);
    });

    test('Creates custom unit of measurement successfully', () async {
      final customUnit = await unitRepo.createUnit(
        UnitOfMeasurement(
          id: 'unit-pack',
          businessId: testBusiness.id,
          name: 'Packets',
          shortName: 'PKT',
          isDecimalAllowed: false,
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(customUnit.id, equals('unit-pack'));
      expect(customUnit.shortName, equals('PKT'));

      final fetched = await unitRepo.getUnitById('unit-pack');
      expect(fetched, isNotNull);
      expect(fetched!.name, equals('Packets'));
    });

    test('Rejects duplicate unit code in the same business', () async {
      expect(
        () => unitRepo.createUnit(
          UnitOfMeasurement(
            id: 'unit-dup',
            businessId: testBusiness.id,
            name: 'Pieces Duplicate',
            shortName: 'PCS', // Already seeded
            createdAt: now,
            updatedAt: now,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
