import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:billzo/domain/settings/app_settings.dart';
import 'package:billzo/domain/settings/settings_repository.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

/// SQLite implementation of [ISettingsRepository] backed by the `app_settings` table.
class SqliteSettingsRepository implements ISettingsRepository {
  final DatabaseHelper _dbHelper;

  SqliteSettingsRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.getInstance();

  @override
  Future<AppSettings> getSettings() async {
    final db = await _dbHelper.database;
    final rows = await db.query('app_settings');

    final map = <String, String>{};
    for (final row in rows) {
      final k = row['key'] as String;
      final v = row['value'] as String;
      map[k] = v;
    }

    DateTime? lastBackup;
    if (map['last_backup_check'] != null) {
      lastBackup = DateTime.tryParse(map['last_backup_check']!);
    }

    return AppSettings(
      activeBusinessId: map['active_business_id'],
      themeMode: map['theme_mode'] ?? 'light',
      onboardingCompleted: map['onboarding_completed'] == 'true',
      fiscalYear: map['fiscal_year'] ?? '2026-2027',
      lastBackupCheck: lastBackup,
    );
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    final db = await _dbHelper.database;
    final nowStr = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      if (settings.activeBusinessId != null) {
        await txn.insert(
          'app_settings',
          {'key': 'active_business_id', 'value': settings.activeBusinessId!, 'updated_at': nowStr},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await txn.insert(
        'app_settings',
        {'key': 'theme_mode', 'value': settings.themeMode, 'updated_at': nowStr},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'app_settings',
        {'key': 'onboarding_completed', 'value': settings.onboardingCompleted.toString(), 'updated_at': nowStr},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'app_settings',
        {'key': 'fiscal_year', 'value': settings.fiscalYear, 'updated_at': nowStr},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (settings.lastBackupCheck != null) {
        await txn.insert(
          'app_settings',
          {'key': 'last_backup_check', 'value': settings.lastBackupCheck!.toUtc().toIso8601String(), 'updated_at': nowStr},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<String?> getSetting(String key) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  @override
  Future<void> setSetting(String key, String value) async {
    final db = await _dbHelper.database;
    final nowStr = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      'app_settings',
      {'key': key, 'value': value, 'updated_at': nowStr},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
