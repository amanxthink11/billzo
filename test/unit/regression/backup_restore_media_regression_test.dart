import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:billzo/application/backup/restore_service.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_backup_repository.dart';
import 'package:billzo/infrastructure/services/backup/backup_service.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

class _TestPathProvider implements IAppPathProvider {
  final Directory baseDir;
  _TestPathProvider(this.baseDir);

  @override
  Future<String> getDatabaseDirectory() async {
    final d = Directory(p.join(baseDir.path, 'data'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d.path;
  }

  @override
  Future<String> getBackupsDirectory() async {
    final d = Directory(p.join(baseDir.path, 'backups'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d.path;
  }

  @override
  Future<String> getMediaDirectory() async {
    final d = Directory(p.join(baseDir.path, 'media'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d.path;
  }

  @override
  Future<String> getExportsDirectory() async {
    final d = Directory(p.join(baseDir.path, 'exports'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d.path;
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  const uuid = Uuid();

  late Directory tempDir;
  late _TestPathProvider pathProvider;
  late DatabaseHelper dbHelper;
  late BackupService backupService;
  late RestoreService restoreService;
  late Business testBiz;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_media_backup_test_');
    pathProvider = _TestPathProvider(tempDir);
    final dbDir = await pathProvider.getDatabaseDirectory();
    final dbPath = p.join(dbDir, 'billzo.sqlite');

    dbHelper = DatabaseHelper.createForTesting(
      dbPath: dbPath,
      pathProvider: pathProvider,
    );

    final backupRepo = SqliteBackupRepository(dbHelper: dbHelper);
    backupService = BackupService(
      dbHelper: dbHelper,
      backupRepository: backupRepo,
      pathProvider: pathProvider,
    );

    restoreService = RestoreService(
      dbHelper: dbHelper,
      pathProvider: pathProvider,
      dbFactory: databaseFactoryFfi,
    );

    // Seed test business in database
    final db = await dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final bizId = uuid.v4();
    await db.insert('businesses', {
      'id': bizId,
      'name': 'Media Packaging Test Store',
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

    testBiz = Business(
      id: bizId,
      name: 'Media Packaging Test Store',
      phone: '9876543210',
      stateCode: '27',
      stateName: 'Maharashtra',
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
  });

  tearDown(() async {
    await dbHelper.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Backup & Restore Media Preservation Regression Tests', () {
    test('Offline logo and signature images are preserved through backup and restore', () async {
      // 1. Create simulated logo and signature files in application media directory
      final mediaDir = Directory(await pathProvider.getMediaDirectory());
      final logoFile = File(p.join(mediaDir.path, 'logo_${testBiz.id}.png'));
      final signatureFile = File(p.join(mediaDir.path, 'signature_${testBiz.id}.png'));

      final dummyLogoBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4, 5];
      final dummySignatureBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 10, 20, 30, 40, 50];

      await logoFile.writeAsBytes(dummyLogoBytes, flush: true);
      await signatureFile.writeAsBytes(dummySignatureBytes, flush: true);

      expect(logoFile.existsSync(), isTrue);
      expect(signatureFile.existsSync(), isTrue);

      // 2. Create full .billzobak backup
      final backupFile = await backupService.createBackup(
        business: testBiz,
        backupType: 'MANUAL',
      );

      expect(backupFile.existsSync(), isTrue);
      expect(backupFile.lengthSync(), greaterThan(0));

      // 3. Simulate disaster: delete local media files
      await logoFile.delete();
      await signatureFile.delete();
      expect(logoFile.existsSync(), isFalse);
      expect(signatureFile.existsSync(), isFalse);

      // 4. Restore from backup
      final result = await restoreService.executeRestore(
        backupFilePath: backupFile.path,
        currentBusinessId: testBiz.id,
      );

      expect(result.restoredMediaFilesCount, equals(2));

      // 5. Verify restored logo and signature files physically exist with identical bytes
      final restoredLogo = File(p.join(mediaDir.path, 'logo_${testBiz.id}.png'));
      final restoredSignature = File(p.join(mediaDir.path, 'signature_${testBiz.id}.png'));

      expect(restoredLogo.existsSync(), isTrue);
      expect(restoredSignature.existsSync(), isTrue);

      expect(await restoredLogo.readAsBytes(), equals(dummyLogoBytes));
      expect(await restoredSignature.readAsBytes(), equals(dummySignatureBytes));
    });
  });
}
