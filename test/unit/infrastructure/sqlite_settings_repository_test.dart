import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/domain/settings/app_settings.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_settings_repository.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

class TestPathProvider implements IAppPathProvider {
  final Directory tempDir;
  TestPathProvider(this.tempDir);

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
  late String dbFilePath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_settings_repo_test_');
    dbFilePath = p.join(tempDir.path, 'test_settings.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SqliteSettingsRepository Tests', () {
    test('Default settings returned when table is empty', () async {
      final helper = DatabaseHelper.createForTesting(
        dbPath: dbFilePath,
        pathProvider: TestPathProvider(tempDir),
      );
      final repo = SqliteSettingsRepository(dbHelper: helper);

      final settings = await repo.getSettings();
      expect(settings.themeMode, equals('light'));
      expect(settings.onboardingCompleted, isFalse);
      expect(settings.activeBusinessId, isNull);

      await helper.close();
    });

    test('Persists and retrieves strongly-typed settings', () async {
      final helper = DatabaseHelper.createForTesting(
        dbPath: dbFilePath,
        pathProvider: TestPathProvider(tempDir),
      );
      final repo = SqliteSettingsRepository(dbHelper: helper);

      const customSettings = AppSettings(
        activeBusinessId: 'biz-12345',
        themeMode: 'dark',
        onboardingCompleted: true,
        fiscalYear: '2026-2027',
      );

      await repo.saveSettings(customSettings);

      final loaded = await repo.getSettings();
      expect(loaded.activeBusinessId, equals('biz-12345'));
      expect(loaded.themeMode, equals('dark'));
      expect(loaded.onboardingCompleted, isTrue);
      expect(loaded.fiscalYear, equals('2026-2027'));

      await helper.close();
    });

    test('Settings survive database restart', () async {
      // Session 1: Write
      final helper1 = DatabaseHelper.createForTesting(
        dbPath: dbFilePath,
        pathProvider: TestPathProvider(tempDir),
      );
      final repo1 = SqliteSettingsRepository(dbHelper: helper1);

      await repo1.setSetting('printer_model', 'Epson-TM-T82');
      await repo1.saveSettings(const AppSettings(
        activeBusinessId: 'saved-id',
        themeMode: 'system',
        onboardingCompleted: true,
      ));
      await helper1.close();

      // Session 2: Read
      final helper2 = DatabaseHelper.createForTesting(
        dbPath: dbFilePath,
        pathProvider: TestPathProvider(tempDir),
      );
      final repo2 = SqliteSettingsRepository(dbHelper: helper2);

      final settings = await repo2.getSettings();
      expect(settings.activeBusinessId, equals('saved-id'));
      expect(settings.themeMode, equals('system'));
      expect(settings.onboardingCompleted, isTrue);

      final raw = await repo2.getSetting('printer_model');
      expect(raw, equals('Epson-TM-T82'));

      await helper2.close();
    });
  });
}
