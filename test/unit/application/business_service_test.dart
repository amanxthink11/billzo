import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/application/business/business_service.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
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
  late SqliteBusinessRepository repo;
  late BusinessService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_service_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
    );
    repo = SqliteBusinessRepository(dbHelper: dbHelper);
    service = BusinessService(repo);
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('BusinessService Application Tests', () {
    test('isFirstRun detects unconfigured state and transitions after setup', () async {
      expect(await service.isFirstRun(), isTrue);

      final business = await service.setupInitialBusiness(
        name: 'Apex Supermarket',
        phone: '9820011223',
        stateCode: '27',
        stateName: 'Maharashtra',
        city: 'Pune',
        pincode: '411001',
        gstin: '27ABCDE1234F1Z5',
      );

      expect(business.id, isNotEmpty);
      expect(business.name, equals('Apex Supermarket'));
      expect(business.gstin, equals('27ABCDE1234F1Z5'));

      // First run is now false
      expect(await service.isFirstRun(), isFalse);

      final active = await service.getActiveBusiness();
      expect(active, isNotNull);
      expect(active!.id, equals(business.id));
    });

    test('setupInitialBusiness handles optional fields cleanly', () async {
      final business = await service.setupInitialBusiness(
        name: 'Simple Kirana',
        phone: '9819819819',
        stateCode: '07',
        stateName: 'Delhi',
      );

      expect(business.name, equals('Simple Kirana'));
      expect(business.gstin, isNull);
      expect(business.pan, isNull);
      expect(business.email, isNull);
      expect(business.addressLine1, isNull);
    });
  });
}
