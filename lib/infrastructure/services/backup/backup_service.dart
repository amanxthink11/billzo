import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:billzo/core/constants/app_constants.dart';
import 'package:billzo/domain/backup/backup_exceptions.dart';
import 'package:billzo/domain/backup/backup_manifest.dart';
import 'package:billzo/domain/backup/backup_record.dart';
import 'package:billzo/domain/backup/backup_repository.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

/// Abstract service contract for local `.billzobak` backup creation.
abstract class IBackupService {
  /// Creates a complete, consistent `.billzobak` archive containing the SQLite database
  /// snapshot, media assets, and cryptographic SHA-256 manifest.
  Future<File> createBackup({
    required Business business,
    String? customDestinationPath,
    String backupType = 'MANUAL',
  });

  /// Evaluates business auto-backup settings and triggers an automatic backup if overdue.
  Future<File?> checkAndRunAutoBackup({
    required Business business,
    required BusinessSettings settings,
  });

  /// Lists all locally discovered `.billzobak` files in the standard backups directory.
  Future<List<File>> getLocalBackupFiles();
}

/// Production implementation of [IBackupService].
class BackupService implements IBackupService {
  final DatabaseHelper _dbHelper;
  final IAppPathProvider _pathProvider;
  final IBackupRepository _backupRepository;
  final Uuid _uuid;

  BackupService({
    DatabaseHelper? dbHelper,
    IAppPathProvider? pathProvider,
    required this._backupRepository,
    Uuid? uuid,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.getInstance(),
        _pathProvider = pathProvider ?? ProductionAppPathProvider(),
        _uuid = uuid ?? const Uuid();

  @override
  Future<File> createBackup({
    required Business business,
    String? customDestinationPath,
    String backupType = 'MANUAL',
  }) async {
    final db = await _dbHelper.database;

    // 1. Gather entity statistics for the manifest
    final invoiceRes = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM invoices WHERE business_id = ?;',
      [business.id],
    );
    final invoiceCount = (invoiceRes.first['cnt'] as num?)?.toInt() ?? 0;

    final customerRes = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM customers WHERE business_id = ? AND deleted_at IS NULL;',
      [business.id],
    );
    final customerCount = (customerRes.first['cnt'] as num?)?.toInt() ?? 0;

    final productRes = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM products WHERE business_id = ? AND deleted_at IS NULL;',
      [business.id],
    );
    final productCount = (productRes.first['cnt'] as num?)?.toInt() ?? 0;

    // 2. Resolve destination file path
    final String targetFilePath;
    if (customDestinationPath != null && customDestinationPath.isNotEmpty) {
      targetFilePath = customDestinationPath.endsWith('.billzobak')
          ? customDestinationPath
          : '$customDestinationPath.billzobak';
    } else {
      final backupsDir = await _pathProvider.getBackupsDirectory();
      final safeBusinessName = (business.tradeName ?? business.name)
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
      targetFilePath = p.join(backupsDir, 'billzo_backup_${safeBusinessName}_$timestamp.billzobak');
    }

    // 3. Create temporary staging area for consistent database snapshot
    final stagingDir = await Directory.systemTemp.createTemp('billzo_backup_staging_');
    final snapshotPath = p.join(stagingDir.path, 'database.sqlite');

    try {
      // 4. Consistent Snapshotting via SQLite VACUUM INTO
      try {
        if (File(snapshotPath).existsSync()) {
          await File(snapshotPath).delete();
        }
        await db.execute("VACUUM INTO '${snapshotPath.replaceAll("'", "''")}';");
      } catch (e) {
        // Fallback: WAL checkpoint then direct copy
        await db.execute('PRAGMA wal_checkpoint(TRUNCATE);');
        final activeDbPath = await _dbHelper.getDatabasePath();
        final activeFile = File(activeDbPath);
        if (activeFile.existsSync()) {
          await activeFile.copy(snapshotPath);
        } else {
          throw BackupException('Failed to create database snapshot for backup', e);
        }
      }

      final snapshotFile = File(snapshotPath);
      if (!snapshotFile.existsSync() || snapshotFile.lengthSync() == 0) {
        throw const BackupException('Snapshot file was not produced or is zero bytes');
      }

      // 5. Compute cryptographic SHA-256 hash of the snapshot database
      final dbBytes = await snapshotFile.readAsBytes();
      final dbSha256 = sha256.convert(dbBytes).toString().toLowerCase();

      // 6. Assemble Manifest
      final manifest = BackupManifest(
        formatVersion: 1,
        appVersion: AppConstants.appVersion,
        appBuildNumber: AppConstants.appBuildNumber,
        schemaVersion: AppConstants.currentSchemaVersion,
        createdAt: DateTime.now().toUtc(),
        businessId: business.id,
        businessName: business.tradeName != null && business.tradeName!.isNotEmpty
            ? business.tradeName!
            : business.name,
        databaseSha256: dbSha256,
        totalInvoices: invoiceCount,
        totalCustomers: customerCount,
        totalProducts: productCount,
        backupType: backupType,
      );

      // 7. Package ZIP archive (.billzobak)
      final archive = Archive();

      // Add manifest.json
      final manifestBytes = utf8.encode(manifest.toJson());
      archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

      // Add database.sqlite
      archive.addFile(ArchiveFile('database.sqlite', dbBytes.length, dbBytes));

      // Add media files if present
      final mediaDir = Directory(await _pathProvider.getMediaDirectory());
      if (mediaDir.existsSync()) {
        final mediaFiles = mediaDir.listSync(recursive: true).whereType<File>();
        for (final file in mediaFiles) {
          final relPath = p.relative(file.path, from: mediaDir.path).replaceAll('\\', '/');
          final fileBytes = await file.readAsBytes();
          archive.addFile(ArchiveFile('media/$relPath', fileBytes.length, fileBytes));
        }
      }

      // Compress and write to final destination
      final zipEncoder = ZipEncoder();
      final compressedBytes = zipEncoder.encode(archive);
      final destinationFile = File(targetFilePath);
      await destinationFile.parent.create(recursive: true);
      await destinationFile.writeAsBytes(compressedBytes, flush: true);

      // 8. Catalog record in database
      final record = BackupRecord(
        id: _uuid.v4(),
        businessId: business.id,
        filePath: destinationFile.path,
        fileSizeBytes: await destinationFile.length(),
        sha256Checksum: dbSha256,
        backupType: backupType,
        databaseVersion: AppConstants.currentSchemaVersion,
        createdAt: manifest.createdAt,
        status: 'VALIDATED',
      );
      await _backupRepository.recordBackup(record);

      return destinationFile;
    } finally {
      if (stagingDir.existsSync()) {
        try {
          await stagingDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  @override
  Future<File?> checkAndRunAutoBackup({
    required Business business,
    required BusinessSettings settings,
  }) async {
    if (!settings.autoBackupEnabled) return null;

    final latest = await _backupRepository.getLatestBackup(business.id);
    if (latest != null) {
      final elapsed = DateTime.now().toUtc().difference(latest.createdAt);
      if (elapsed.inDays < settings.autoBackupIntervalDays) {
        return null; // Not due yet
      }
    }

    final targetDir = settings.backupDirectoryPath != null && settings.backupDirectoryPath!.isNotEmpty
        ? settings.backupDirectoryPath!
        : await _pathProvider.getBackupsDirectory();

    final safeName = (business.tradeName ?? business.name).replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final autoBackupPath = p.join(targetDir, 'billzo_auto_backup_${safeName}_$timestamp.billzobak');

    return await createBackup(
      business: business,
      customDestinationPath: autoBackupPath,
      backupType: 'AUTO',
    );
  }

  @override
  Future<List<File>> getLocalBackupFiles() async {
    final backupsDir = Directory(await _pathProvider.getBackupsDirectory());
    if (!backupsDir.existsSync()) return [];

    final files = backupsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.billzobak'))
        .toList();

    // Sort newest first
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }
}
