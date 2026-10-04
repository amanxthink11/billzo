import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/core/constants/app_constants.dart';
import 'package:billzo/domain/backup/backup_exceptions.dart';
import 'package:billzo/domain/backup/backup_manifest.dart';
import 'package:billzo/domain/backup/restore_result.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

/// Service contract defining the bulletproof restore protocol.
abstract class IRestoreService {
  /// Inspects and rigorously validates a candidate `.billzobak` archive before any
  /// modifications are made to the live system:
  /// 1. Verifies ZIP archive structure and uncompressibility.
  /// 2. Verifies `manifest.json` presence, schema, and required fields.
  /// 3. Validates `format_version` compatibility.
  /// 4. Validates `schema_version` compatibility (rejects future schemas).
  /// 5. Validates SHA-256 hash of `database.sqlite` against manifest hash.
  /// 6. Executes `PRAGMA integrity_check;` on the candidate SQLite database in isolated staging.
  Future<BackupManifest> inspectAndValidateBackup(String backupFilePath);

  /// Executes the atomic restore protocol:
  /// 1. Re-validates the candidate backup.
  /// 2. Performs multi-business validation to prevent accidental cross-business contamination.
  /// 3. Creates a mandatory pre-restore safety snapshot of the active database.
  /// 4. Hot-swaps the database files and restores media assets.
  /// 5. Reopens the database, running pending migrations if the backup is from an earlier schema.
  /// 6. Verifies post-restore database integrity.
  /// 7. Automatically rolls back to the pre-restore safety snapshot if any error occurs.
  Future<RestoreResult> executeRestore({
    required String backupFilePath,
    required String currentBusinessId,
    bool allowCrossBusiness = false,
  });
}

/// Production implementation of [IRestoreService].
class RestoreService implements IRestoreService {
  final DatabaseHelper _dbHelper;
  final IAppPathProvider _pathProvider;
  final DatabaseFactory? _dbFactory;

  RestoreService({
    DatabaseHelper? dbHelper,
    IAppPathProvider? pathProvider,
    this._dbFactory,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.getInstance(),
        _pathProvider = pathProvider ?? ProductionAppPathProvider();

  DatabaseFactory get _effectiveDbFactory => _dbFactory ?? _dbHelper.dbFactory;

  @override
  Future<BackupManifest> inspectAndValidateBackup(String backupFilePath) async {
    final file = File(backupFilePath);
    if (!await file.exists()) {
      throw InvalidBackupException('Backup file not found at: $backupFilePath');
    }

    List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      throw BackupCorruptedException('Unable to read backup file at $backupFilePath', e);
    }

    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw const BackupCorruptedException('Backup file is not a valid zip archive or has been corrupted');
    }

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
      if (archive.isEmpty) {
        throw const BackupCorruptedException('Backup archive is empty or corrupted');
      }
    } catch (e) {
      if (e is BackupException) rethrow;
      throw BackupCorruptedException('Backup file is not a valid zip archive or has been corrupted', e);
    }

    // 1. Locate manifest.json
    final manifestEntry = archive.findFile('manifest.json');
    if (manifestEntry == null) {
      throw const InvalidBackupException('Backup archive is missing required manifest.json');
    }

    final manifestContent = utf8.decode(manifestEntry.content as List<int>);
    Map<String, dynamic> manifestMap;
    try {
      manifestMap = jsonDecode(manifestContent) as Map<String, dynamic>;
    } catch (e) {
      throw InvalidBackupException('manifest.json is malformed or invalid JSON', e);
    }

    final BackupManifest manifest;
    try {
      manifest = BackupManifest.fromMap(manifestMap);
    } catch (e) {
      throw InvalidBackupException('manifest.json structure is invalid: $e', e);
    }

    // 2. Validate format version
    if (manifest.formatVersion != AppConstants.backupFormatVersion) {
      throw UnsupportedBackupVersionException(
        'Backup format version ${manifest.formatVersion} is unsupported. '
        'This version of Billzo supports format version ${AppConstants.backupFormatVersion}.',
      );
    }

    // 3. Validate schema version (reject future schema downgrades)
    if (manifest.schemaVersion > AppConstants.currentSchemaVersion) {
      throw IncompatibleSchemaException(
        'Backup database schema version (${manifest.schemaVersion}) is newer than '
        'this application supports (${AppConstants.currentSchemaVersion}). '
        'Please update Billzo before restoring this backup.',
      );
    }

    // 4. Locate database.sqlite
    final dbEntry = archive.findFile('database.sqlite');
    if (dbEntry == null) {
      throw const InvalidBackupException('Backup archive is missing required database.sqlite snapshot');
    }

    final dbBytes = dbEntry.content as List<int>;

    // 5. Cryptographic SHA-256 verification
    final computedSha256 = sha256.convert(dbBytes).toString();
    if (computedSha256 != manifest.databaseSha256) {
      throw BackupCorruptedException(
        'Database integrity check failed: SHA-256 checksum mismatch. '
        'Expected: ${manifest.databaseSha256}, Computed: $computedSha256. '
        'The backup package may be damaged or tampered with.',
      );
    }

    // 6. Test candidate database integrity in isolated staging
    final tempDir = Directory.systemTemp.createTempSync('billzo_candidate_check_');
    final candidateDbPath = p.join(tempDir.path, 'candidate_database.sqlite');
    try {
      await File(candidateDbPath).writeAsBytes(dbBytes, flush: true);

      final candidateDb = await _effectiveDbFactory.openDatabase(
        candidateDbPath,
        options: OpenDatabaseOptions(
          readOnly: true,
          onConfigure: (db) async {
            await db.execute('PRAGMA busy_timeout = 3000;');
          },
        ),
      );

      try {
        final integrityResult = await candidateDb.rawQuery('PRAGMA integrity_check;');
        if (integrityResult.isEmpty || integrityResult.first.values.first != 'ok') {
          throw const BackupCorruptedException('Candidate database failed SQLite integrity check.');
        }
      } finally {
        await candidateDb.close();
      }
    } catch (e) {
      if (e is BackupException) rethrow;
      throw BackupCorruptedException('Candidate database integrity verification failed: $e', e);
    } finally {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }

    return manifest;
  }

  @override
  Future<RestoreResult> executeRestore({
    required String backupFilePath,
    required String currentBusinessId,
    bool allowCrossBusiness = false,
  }) async {
    // Phase 1: Validate Archive Integrity & Schema
    final manifest = await inspectAndValidateBackup(backupFilePath);

    // Multi-Business Safety Verification
    if (manifest.businessId != currentBusinessId && !allowCrossBusiness) {
      throw CrossBusinessRestoreMismatchException(
        backupBusinessId: manifest.businessId,
        currentBusinessId: currentBusinessId,
        message: 'Cross-business restore blocked: Backup belongs to business '
            '"${manifest.businessName}" (${manifest.businessId}), but active business is ($currentBusinessId). '
            'Multi-business safety prevents accidental data overwrite.',
      );
    }

    // Phase 2: Mandatory Pre-Restore Safety Snapshot
    final activeDbPath = await _dbHelper.getDatabasePath();
    final backupsDir = await _pathProvider.getBackupsDirectory();
    final backupsDirectory = Directory(backupsDir);
    if (!await backupsDirectory.exists()) {
      await backupsDirectory.create(recursive: true);
    }

    final timestampStr = DateTime.now().toIso8601String().replaceAll(':', '-');
    final safetySnapshotPath = p.join(backupsDir, 'pre_restore_safety_backup_$timestampStr.db');

    try {
      await _createSafetySnapshot(activeDbPath, safetySnapshotPath);
    } catch (e) {
      throw PreRestoreSafetyBackupFailedException(
        'Mandatory pre-restore safety backup failed. Restore aborted to protect current data: $e',
        e,
      );
    }

    // Verify safety backup file physically exists and has content
    final safetyFile = File(safetySnapshotPath);
    if (!await safetyFile.exists() || await safetyFile.length() == 0) {
      throw const PreRestoreSafetyBackupFailedException(
        'Mandatory pre-restore safety snapshot file was not created or is empty. Restore aborted.',
      );
    }

    // Phase 3: Extract Backup Contents into Staging
    final stagingDir = Directory.systemTemp.createTempSync('billzo_restore_staging_');
    int restoredMediaFilesCount = 0;

    try {
      final archiveBytes = await File(backupFilePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(archiveBytes);

      final dbEntry = archive.findFile('database.sqlite')!;
      final stagingDbFile = File(p.join(stagingDir.path, 'database.sqlite'));
      await stagingDbFile.writeAsBytes(dbEntry.content as List<int>, flush: true);

      // Extract media files to staging
      final stagingMediaDir = Directory(p.join(stagingDir.path, 'media'));
      for (final file in archive.files) {
        if (file.name.startsWith('media/') && !file.name.endsWith('/')) {
          final relativePath = file.name.substring('media/'.length);
          if (relativePath.isNotEmpty) {
            final targetPath = p.join(stagingMediaDir.path, relativePath);
            await Directory(p.dirname(targetPath)).create(recursive: true);
            await File(targetPath).writeAsBytes(file.content as List<int>, flush: true);
          }
        }
      }

      // Phase 4: Atomic Hot Swap
      // Step A: Safely close active SQLite connection pool
      await _dbHelper.close();

      // Step B: Replace active database file
      await stagingDbFile.copy(activeDbPath);

      // Step C: Delete stale -wal and -shm files
      final walFile = File('$activeDbPath-wal');
      if (await walFile.exists()) {
        await walFile.delete();
      }
      final shmFile = File('$activeDbPath-shm');
      if (await shmFile.exists()) {
        await shmFile.delete();
      }

      // Step D: Restore media assets into application media directory
      if (await stagingMediaDir.exists()) {
        final mediaDir = Directory(await _pathProvider.getMediaDirectory());
        if (!await mediaDir.exists()) {
          await mediaDir.create(recursive: true);
        }

        await for (final entity in stagingMediaDir.list(recursive: true)) {
          if (entity is File) {
            final rel = p.relative(entity.path, from: stagingMediaDir.path);
            final dest = p.join(mediaDir.path, rel);
            await Directory(p.dirname(dest)).create(recursive: true);
            await entity.copy(dest);
            restoredMediaFilesCount++;
          }
        }
      }

      // Step E: Reopen connection (DatabaseHelper automatically executes DatabaseMigrator.runPendingMigrations)
      await _dbHelper.database;

      // Step F: Post-restore database integrity check
      final integrityOk = await _dbHelper.verifyIntegrity();
      if (!integrityOk) {
        throw const BackupCorruptedException('Post-restore SQLite database integrity verification failed.');
      }

      return RestoreResult(
        manifest: manifest,
        safetySnapshotPath: safetySnapshotPath,
        restoredAt: DateTime.now(),
        restoredMediaFilesCount: restoredMediaFilesCount,
      );
    } catch (e) {
      // Phase 5: Automatic Rollback to Safety Snapshot
      bool rollbackSucceeded = false;
      try {
        await _dbHelper.close();
        if (await safetyFile.exists()) {
          await safetyFile.copy(activeDbPath);
          final walFile = File('$activeDbPath-wal');
          if (await walFile.exists()) await walFile.delete();
          final shmFile = File('$activeDbPath-shm');
          if (await shmFile.exists()) await shmFile.delete();
          await _dbHelper.database;
          rollbackSucceeded = true;
        }
      } catch (rollbackErr) {
        rollbackSucceeded = false;
      }

      throw RestoreFailedException(
        'Restore execution failed: $e',
        rolledBackSuccessfully: rollbackSucceeded,
        safetySnapshotPath: safetySnapshotPath,
        cause: e,
      );
    } finally {
      if (stagingDir.existsSync()) {
        try {
          stagingDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<void> _createSafetySnapshot(String activeDbPath, String safetySnapshotPath) async {
    final activeFile = File(activeDbPath);
    if (!await activeFile.exists()) {
      // If no active DB file exists yet, create an empty snapshot
      await File(safetySnapshotPath).writeAsBytes([], flush: true);
      return;
    }

    try {
      final db = await _dbHelper.database;
      final targetFile = File(safetySnapshotPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      final escaped = safetySnapshotPath.replaceAll("'", "''");
      await db.execute("VACUUM INTO '$escaped'");
    } catch (_) {
      // Fallback: WAL checkpoint then direct file copy
      try {
        final db = await _dbHelper.database;
        await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE);');
      } catch (_) {}
      await activeFile.copy(safetySnapshotPath);
    }
  }
}
