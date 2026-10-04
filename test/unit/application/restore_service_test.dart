import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/application/backup/restore_service.dart';
import 'package:billzo/core/constants/app_constants.dart';
import 'package:billzo/domain/backup/backup_exceptions.dart';
import 'package:billzo/domain/business/business.dart';
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

class FailingIntegrityDatabaseHelper extends DatabaseHelper {
  FailingIntegrityDatabaseHelper({
    required super.pathProvider,
    required super.customDbPath,
    super.dbFactory,
  });

  @override
  Future<bool> verifyIntegrity() async {
    return false;
  }
}

void main() {
  late Directory tempDir;
  late TestPathProvider pathProvider;
  late DatabaseHelper dbHelper;
  late SqliteBackupRepository backupRepo;
  late BackupService backupService;
  late RestoreService restoreService;
  late Business activeBusiness;
  late File validBackupFile;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_restore_service_test_');
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
    restoreService = RestoreService(
      dbHelper: dbHelper,
      pathProvider: pathProvider,
      dbFactory: databaseFactoryFfi,
    );

    activeBusiness = Business(
      id: 'biz-active-99',
      name: 'Active Enterprise',
      phone: '9876543210',
      stateCode: '27',
      stateName: 'Maharashtra',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final db = await dbHelper.database;
    await db.insert('businesses', {
      'id': activeBusiness.id,
      'name': activeBusiness.name,
      'phone': activeBusiness.phone,
      'state_code': activeBusiness.stateCode,
      'state_name': activeBusiness.stateName,
      'created_at': activeBusiness.createdAt.toIso8601String(),
      'updated_at': activeBusiness.updatedAt.toIso8601String(),
    });

    // Create a valid baseline backup to test against
    validBackupFile = await backupService.createBackup(
      business: activeBusiness,
      backupType: 'MANUAL',
    );
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> createCustomArchive({
    String? manifestContent,
    List<int>? dbBytes,
    Map<String, List<int>>? extraFiles,
    String? outputFileName,
  }) async {
    final archive = Archive();
    if (manifestContent != null) {
      archive.addFile(ArchiveFile.string('manifest.json', manifestContent));
    }
    if (dbBytes != null) {
      archive.addFile(ArchiveFile('database.sqlite', dbBytes.length, dbBytes));
    }
    if (extraFiles != null) {
      for (final entry in extraFiles.entries) {
        archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
      }
    }
    final encoded = ZipEncoder().encode(archive);
    final file = File(p.join(await pathProvider.getBackupsDirectory(), outputFileName ?? 'custom_${DateTime.now().microsecondsSinceEpoch}.billzobak'));
    await file.writeAsBytes(encoded, flush: true);
    return file;
  }

  group('RestoreService Validation Protocol Tests', () {
    test('inspectAndValidateBackup successfully parses and validates a healthy package', () async {
      final manifest = await restoreService.inspectAndValidateBackup(validBackupFile.path);

      expect(manifest.formatVersion, equals(AppConstants.backupFormatVersion));
      expect(manifest.schemaVersion, equals(AppConstants.currentSchemaVersion));
      expect(manifest.businessId, equals(activeBusiness.id));
      expect(manifest.businessName, equals(activeBusiness.name));
      expect(manifest.databaseSha256, isNotEmpty);
    });

    test('Throws InvalidBackupException if backup file does not exist', () async {
      expect(
        () => restoreService.inspectAndValidateBackup('C:/non_existent_folder/missing.billzobak'),
        throwsA(isA<InvalidBackupException>()),
      );
    });

    test('Throws BackupCorruptedException if file is not a valid zip archive', () async {
      final corruptFile = File(p.join(await pathProvider.getBackupsDirectory(), 'corrupt.billzobak'));
      await corruptFile.writeAsString('NOT_A_ZIP_CONTAINER');

      expect(
        () => restoreService.inspectAndValidateBackup(corruptFile.path),
        throwsA(isA<BackupCorruptedException>()),
      );
    });

    test('Throws InvalidBackupException if package is missing manifest.json', () async {
      final file = await createCustomArchive(
        manifestContent: null,
        dbBytes: [1, 2, 3],
      );

      expect(
        () => restoreService.inspectAndValidateBackup(file.path),
        throwsA(isA<InvalidBackupException>()),
      );
    });

    test('Throws InvalidBackupException if manifest.json is malformed JSON', () async {
      final file = await createCustomArchive(
        manifestContent: '{invalid_json, missing_quotes}',
        dbBytes: [1, 2, 3],
      );

      expect(
        () => restoreService.inspectAndValidateBackup(file.path),
        throwsA(isA<InvalidBackupException>()),
      );
    });

    test('Throws UnsupportedBackupVersionException if format_version is unsupported', () async {
      final manifestMap = {
        'format_version': 99,
        'app_version': '1.0.0',
        'app_build_number': 1,
        'schema_version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'business_id': 'biz-1',
        'business_name': 'Test',
        'database_sha256': 'abc',
      };
      final file = await createCustomArchive(
        manifestContent: jsonEncode(manifestMap),
        dbBytes: [1, 2, 3],
      );

      expect(
        () => restoreService.inspectAndValidateBackup(file.path),
        throwsA(isA<UnsupportedBackupVersionException>()),
      );
    });

    test('Throws IncompatibleSchemaException if backup database schema is newer than application supports', () async {
      final manifestMap = {
        'format_version': 1,
        'app_version': '2.0.0',
        'app_build_number': 10,
        'schema_version': AppConstants.currentSchemaVersion + 5,
        'created_at': DateTime.now().toIso8601String(),
        'business_id': 'biz-1',
        'business_name': 'Future Enterprise',
        'database_sha256': 'abc',
      };
      final file = await createCustomArchive(
        manifestContent: jsonEncode(manifestMap),
        dbBytes: [1, 2, 3],
      );

      expect(
        () => restoreService.inspectAndValidateBackup(file.path),
        throwsA(isA<IncompatibleSchemaException>()),
      );
    });

    test('Throws BackupCorruptedException if SHA-256 hash does not match candidate database.sqlite', () async {
      final fakeDbBytes = [4, 5, 6, 7, 8];
      final manifestMap = {
        'format_version': 1,
        'app_version': '1.0.0',
        'app_build_number': 1,
        'schema_version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'business_id': 'biz-1',
        'business_name': 'Tampered Test',
        'database_sha256': '0000000000000000000000000000000000000000000000000000000000000000',
      };
      final file = await createCustomArchive(
        manifestContent: jsonEncode(manifestMap),
        dbBytes: fakeDbBytes,
      );

      expect(
        () => restoreService.inspectAndValidateBackup(file.path),
        throwsA(isA<BackupCorruptedException>()),
      );
    });

    test('Throws BackupCorruptedException if candidate database.sqlite fails SQLite integrity check', () async {
      final corruptDbBytes = utf8.encode('CORRUPT_BYTES_THAT_ARE_NOT_VALID_SQLITE');
      final validSha = sha256.convert(corruptDbBytes).toString();
      final manifestMap = {
        'format_version': 1,
        'app_version': '1.0.0',
        'app_build_number': 1,
        'schema_version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'business_id': 'biz-1',
        'business_name': 'Corrupt DB Test',
        'database_sha256': validSha,
      };
      final file = await createCustomArchive(
        manifestContent: jsonEncode(manifestMap),
        dbBytes: corruptDbBytes,
      );

      expect(
        () => restoreService.inspectAndValidateBackup(file.path),
        throwsA(isA<BackupCorruptedException>()),
      );
    });
  });

  group('RestoreService Atomic Execution & Rollback Tests', () {
    test('Throws CrossBusinessRestoreMismatchException when restoring different business without allowCrossBusiness flag', () async {
      // Create backup from a different business
      final otherBusiness = Business(
        id: 'biz-other-202',
        name: 'Other Company',
        phone: '1122334455',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final db = await dbHelper.database;
      await db.insert('businesses', {
        'id': otherBusiness.id,
        'name': otherBusiness.name,
        'phone': otherBusiness.phone,
        'state_code': otherBusiness.stateCode,
        'state_name': otherBusiness.stateName,
        'created_at': otherBusiness.createdAt.toIso8601String(),
        'updated_at': otherBusiness.updatedAt.toIso8601String(),
      });

      final otherBackup = await backupService.createBackup(
        business: otherBusiness,
        backupType: 'MANUAL',
      );

      expect(
        () => restoreService.executeRestore(
          backupFilePath: otherBackup.path,
          currentBusinessId: activeBusiness.id,
          allowCrossBusiness: false,
        ),
        throwsA(isA<CrossBusinessRestoreMismatchException>()),
      );
    });

    test('executeRestore creates a mandatory pre-restore safety snapshot before modifying active database', () async {
      final backupsDir = Directory(await pathProvider.getBackupsDirectory());
      final beforeSnapshots = backupsDir.listSync().where((e) => e.path.contains('pre_restore_safety_backup_')).toList();
      expect(beforeSnapshots, isEmpty);

      final result = await restoreService.executeRestore(
        backupFilePath: validBackupFile.path,
        currentBusinessId: activeBusiness.id,
      );

      expect(result.safetySnapshotPath, isNotEmpty);
      expect(File(result.safetySnapshotPath).existsSync(), isTrue);
      expect(File(result.safetySnapshotPath).lengthSync(), greaterThan(0));

      final afterSnapshots = backupsDir.listSync().where((e) => e.path.contains('pre_restore_safety_backup_')).toList();
      expect(afterSnapshots.length, equals(1));
    });

    test('executeRestore successfully restores database snapshot, media, and verifies integrity', () async {
      final result = await restoreService.executeRestore(
        backupFilePath: validBackupFile.path,
        currentBusinessId: activeBusiness.id,
      );

      expect(result.manifest.businessId, equals(activeBusiness.id));
      expect(result.restoredAt, isNotNull);

      // Verify active database is open and valid
      final db = await dbHelper.database;
      expect(db.isOpen, isTrue);

      final integrityOk = await dbHelper.verifyIntegrity();
      expect(integrityOk, isTrue);

      // Verify active business record is present
      final businesses = await db.query('businesses', where: 'id = ?', whereArgs: [activeBusiness.id]);
      expect(businesses.length, equals(1));
      expect(businesses.first['name'], equals(activeBusiness.name));
    });

    test('executeRestore safely rolls back to pre-restore safety snapshot if a critical error occurs', () async {
      final db = await dbHelper.database;
      // Mark database with a special identifier
      await db.execute("CREATE TABLE IF NOT EXISTS rollback_canary (marker TEXT);");
      await db.execute("INSERT INTO rollback_canary (marker) VALUES ('CANARY_ALIVE');");

      // Verify canary is in the active database
      final beforeCanary = await db.query('rollback_canary');
      expect(beforeCanary.first['marker'], equals('CANARY_ALIVE'));

      final activeDbPath = await dbHelper.getDatabasePath();
      final failingHelper = FailingIntegrityDatabaseHelper(
        pathProvider: pathProvider,
        customDbPath: activeDbPath,
        dbFactory: databaseFactoryFfi,
      );

      final failingRestoreService = RestoreService(
        dbHelper: failingHelper,
        pathProvider: pathProvider,
        dbFactory: databaseFactoryFfi,
      );

      try {
        await failingRestoreService.executeRestore(
          backupFilePath: validBackupFile.path,
          currentBusinessId: activeBusiness.id,
        );
        fail('Expected RestoreFailedException');
      } on RestoreFailedException catch (e) {
        expect(e.rolledBackSuccessfully, isTrue);
        expect(e.safetySnapshotPath, isNotNull);

        // Check active database after rollback: the canary table and row must still be intact!
        final reopenedDb = await dbHelper.database;
        final canaryAfter = await reopenedDb.query('rollback_canary');
        expect(canaryAfter.first['marker'], equals('CANARY_ALIVE'));
      }
    });
  });
}
