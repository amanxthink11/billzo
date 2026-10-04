import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/domain/backup/backup_record.dart';
import 'package:billzo/domain/backup/backup_repository.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

/// SQLite implementation of [IBackupRepository] persisting backup records into `backup_records`.
class SqliteBackupRepository implements IBackupRepository {
  final DatabaseHelper _dbHelper;

  SqliteBackupRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.getInstance();

  @override
  Future<void> recordBackup(BackupRecord record) async {
    final db = await _dbHelper.database;
    await db.insert(
      'backup_records',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<BackupRecord>> getBackupHistory(String businessId) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'backup_records',
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'created_at DESC',
    );
    return results.map(BackupRecord.fromMap).toList();
  }

  @override
  Future<BackupRecord?> getLatestBackup(String businessId) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'backup_records',
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (results.isEmpty) return null;
    return BackupRecord.fromMap(results.first);
  }

  @override
  Future<void> deleteBackupRecord(String recordId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'backup_records',
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }
}
