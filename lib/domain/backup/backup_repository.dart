import 'package:billzo/domain/backup/backup_record.dart';

/// Abstract contract for managing persisted backup records in the local SQLite database.
abstract class IBackupRepository {
  /// Inserts a new backup record into the catalog.
  Future<void> recordBackup(BackupRecord record);

  /// Retrieves the history of backups created for a business, sorted descending by creation date.
  Future<List<BackupRecord>> getBackupHistory(String businessId);

  /// Retrieves the most recent backup recorded for a business.
  Future<BackupRecord?> getLatestBackup(String businessId);

  /// Removes a backup record entry by ID.
  Future<void> deleteBackupRecord(String recordId);
}
