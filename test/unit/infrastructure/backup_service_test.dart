import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/core/constants/app_constants.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_backup_repository.dart';
import 'package:billzo/infrastructure/services/backup/backup_service.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

class TestPathProvider implements IAppPathProvider {
  final Directory baseDir;
  TestPathProvider(this.baseDir);

  @override
  Future<String> getDatabaseDirectory() async => p.join(baseDir.path, 'data');
  @override
  Future<String> getBackupsDirectory() async => p.join(baseDir.path, 'backups');
  @override
  Future<String> getMediaDirectory() async => p.join(baseDir.path, 'media');
  @override
  Future<String> getExportsDirectory() async => p.join(baseDir.path, 'exports');
}

void main() {
  late Directory tempDir;
  late TestPathProvider pathProvider;
  late DatabaseHelper dbHelper;
  late SqliteBackupRepository backupRepo;
  late BackupService backupService;
  late Business testBusiness;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_backup_service_test_');
    pathProvider = TestPathProvider(tempDir);

    final dbDir = Directory(await pathProvider.getDatabaseDirectory());
    await dbDir.create(recursive: true);
    final backupsDir = Directory(await pathProvider.getBackupsDirectory());
    await backupsDir.create(recursive: true);
    final mediaDir = Directory(await pathProvider.getMediaDirectory());
    await mediaDir.create(recursive: true);

    final dbPath = p.join(dbDir.path, AppConstants.databaseFileName);
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: dbPath,
      pathProvider: pathProvider,
      dbFactory: databaseFactoryFfi,
    );

    backupRepo = SqliteBackupRepository(dbHelper: dbHelper);
    backupService = BackupService(
      dbHelper: dbHelper,
      pathProvider: pathProvider,
      backupRepository: backupRepo,
    );

    testBusiness = Business(
      id: 'biz-test-101',
      name: 'Test Enterprise Ltd',
      legalName: 'Test Enterprise Private Limited',
      phone: '9876543210',
      stateCode: '27',
      stateName: 'Maharashtra',
      logoPath: p.join(mediaDir.path, 'logo.png'),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Initialize DB and seed records
    final db = await dbHelper.database;
    await db.insert('businesses', {
      'id': testBusiness.id,
      'name': testBusiness.name,
      'legal_name': testBusiness.legalName,
      'phone': testBusiness.phone,
      'state_code': testBusiness.stateCode,
      'state_name': testBusiness.stateName,
      'logo_path': testBusiness.logoPath,
      'created_at': testBusiness.createdAt.toIso8601String(),
      'updated_at': testBusiness.updatedAt.toIso8601String(),
    });

    // Seed test unit
    await db.insert('units', {
      'id': 'unit-1',
      'business_id': testBusiness.id,
      'code': 'PCS',
      'name': 'Pieces',
      'allow_decimal': 0,
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Seed test tax rate
    await db.insert('tax_rates', {
      'id': 'tax-1',
      'business_id': testBusiness.id,
      'name': 'GST 18%',
      'rate_basis_points': 1800,
      'cgst_basis_points': 900,
      'sgst_basis_points': 900,
      'igst_basis_points': 1800,
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Seed test customer
    await db.insert('customers', {
      'id': 'cust-1',
      'business_id': testBusiness.id,
      'name': 'Customer One',
      'phone': '9999988888',
      'billing_state_code': '27',
      'billing_state_name': 'Maharashtra',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Seed test product
    await db.insert('products', {
      'id': 'prod-1',
      'business_id': testBusiness.id,
      'unit_id': 'unit-1',
      'tax_rate_id': 'tax-1',
      'name': 'Super Widget',
      'selling_price_paise': 10000,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Seed sample media logo file
    final logoFile = File(testBusiness.logoPath!);
    await logoFile.writeAsString('FAKE_IMAGE_DATA_FOR_LOGO');
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('BackupService Creation & Validation Tests', () {
    test('createBackup creates a valid .billzobak zip archive with deterministic structure', () async {
      final backupFile = await backupService.createBackup(
        business: testBusiness,
        backupType: 'MANUAL',
      );

      expect(await backupFile.exists(), isTrue);
      expect(backupFile.path.endsWith('.billzobak'), isTrue);
      expect(await backupFile.length(), greaterThan(0));

      final archiveBytes = await backupFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(archiveBytes);

      // Verify mandatory files inside the package
      final manifestEntry = archive.findFile('manifest.json');
      expect(manifestEntry, isNotNull);
      final dbEntry = archive.findFile('database.sqlite');
      expect(dbEntry, isNotNull);
      final mediaEntry = archive.findFile('media/logo.png');
      expect(mediaEntry, isNotNull);

      // Validate manifest contents
      final manifestJson = utf8.decode(manifestEntry!.content as List<int>);
      final manifestMap = jsonDecode(manifestJson) as Map<String, dynamic>;

      expect(manifestMap['format_version'], equals(AppConstants.backupFormatVersion));
      expect(manifestMap['schema_version'], equals(AppConstants.currentSchemaVersion));
      expect(manifestMap['business_id'], equals(testBusiness.id));
      expect(manifestMap['business_name'], equals(testBusiness.name));
      expect(manifestMap['total_customers'], equals(1));
      expect(manifestMap['total_products'], equals(1));
      expect(manifestMap['total_invoices'], equals(0));
      expect(manifestMap['backup_type'], equals('MANUAL'));

      // Validate SHA-256 matches candidate database.sqlite bytes
      final dbBytes = dbEntry!.content as List<int>;
      final computedSha = sha256.convert(dbBytes).toString().toLowerCase();
      expect(manifestMap['database_sha256'], equals(computedSha));
    });

    test('createBackup catalogs an entry into backup_records table', () async {
      final backupFile = await backupService.createBackup(
        business: testBusiness,
        backupType: 'MANUAL',
      );

      final history = await backupRepo.getBackupHistory(testBusiness.id);
      expect(history.length, equals(1));

      final record = history.first;
      expect(record.businessId, equals(testBusiness.id));
      expect(record.filePath, equals(backupFile.path));
      expect(record.fileSizeBytes, equals(await backupFile.length()));
      expect(record.status, equals('VALIDATED'));
      expect(record.backupType, equals('MANUAL'));
      expect(record.databaseVersion, equals(AppConstants.currentSchemaVersion));
    });

    test('getLocalBackupFiles discovers created .billzobak files in backups directory', () async {
      await backupService.createBackup(business: testBusiness);
      final files = await backupService.getLocalBackupFiles();
      expect(files.length, equals(1));
      expect(files.first.path.endsWith('.billzobak'), isTrue);
    });

    test('checkAndRunAutoBackup respects autoBackupEnabled and interval settings', () async {
      final now = DateTime.now();
      final disabledSettings = BusinessSettings(
        id: 'settings-1',
        businessId: testBusiness.id,
        autoBackupEnabled: false,
        autoBackupIntervalDays: 1,
        createdAt: now,
        updatedAt: now,
      );

      // When disabled, no backup should be generated
      final result1 = await backupService.checkAndRunAutoBackup(
        business: testBusiness,
        settings: disabledSettings,
      );
      expect(result1, isNull);

      // When enabled and no previous backup exists, an auto backup must be created
      final enabledSettings = disabledSettings.copyWith(autoBackupEnabled: true);
      final result2 = await backupService.checkAndRunAutoBackup(
        business: testBusiness,
        settings: enabledSettings,
      );
      expect(result2, isNotNull);
      expect(result2!.path.endsWith('.billzobak'), isTrue);

      // Immediately checking again within the interval window should produce no new backup
      final result3 = await backupService.checkAndRunAutoBackup(
        business: testBusiness,
        settings: enabledSettings,
      );
      expect(result3, isNull);
    });
  });
}
