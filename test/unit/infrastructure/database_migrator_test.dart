import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';
import 'package:billzo/infrastructure/sqlite/database_migrator.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';

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

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_migrator_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Database Initialization & Migration Tests', () {
    test('Initializes SQLite database and applies 001_initial_schema cleanly', () async {
      final db = await dbHelper.database;
      expect(db.isOpen, isTrue);

      // Verify PRAGMA foreign_keys = ON
      final fkResult = await db.rawQuery('PRAGMA foreign_keys;');
      expect(fkResult.first.values.first, equals(1));

      // Verify integrity
      final isHealthy = await dbHelper.verifyIntegrity();
      expect(isHealthy, isTrue);

      // Verify schema_migrations table tracks applied migrations (001, 003, 004, 005, and 006)
      final migrations = await DatabaseMigrator.getAppliedMigrations(db);
      expect(migrations.length, equals(5));
      expect(migrations[0].version, equals(1));
      expect(migrations[0].description, equals('001_initial_schema'));
      expect(migrations[0].checksum, isNotEmpty);
      expect(migrations[1].version, equals(3));
      expect(migrations[1].description, equals('003_payments_and_cash_bank'));
      expect(migrations[2].version, equals(4));
      expect(migrations[2].description, equals('004_purchases_and_ap'));
      expect(migrations[3].version, equals(5));
      expect(migrations[3].description, equals('005_expenses_and_reporting'));
      expect(migrations[4].version, equals(6));
      expect(migrations[4].description, contains('006_recurring_enhancements'));

      // Verify columns added by migration 006 exist in recurring_invoice_items
      final tableInfo = await db.rawQuery('PRAGMA table_info(recurring_invoice_items);');
      final columnNames = tableInfo.map((c) => c['name'] as String).toSet();
      expect(columnNames.contains('product_name'), isTrue);
      expect(columnNames.contains('hsn_sac'), isTrue);
    });

    test('Migration execution is strictly idempotent', () async {
      final db = await dbHelper.database;

      // Run pending migrations again manually
      await DatabaseMigrator.runPendingMigrations(db);

      // Migrations count should still be exactly 5
      final migrations = await DatabaseMigrator.getAppliedMigrations(db);
      expect(migrations.length, equals(5));
    });

    test('All documented tables exist in SQLite master catalog', () async {
      final db = await dbHelper.database;

      final tablesResult = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
      );
      final tableNames = tablesResult.map((r) => r['name'] as String).toSet();

      final expectedTables = [
        'schema_migrations',
        'businesses',
        'business_settings',
        'invoice_sequences',
        'tax_rates',
        'units',
        'product_categories',
        'products',
        'customers',
        'suppliers',
        'invoices',
        'invoice_items',
        'estimates',
        'estimate_items',
        'recurring_invoices',
        'recurring_invoice_items',
        'recurring_invoice_executions',
        'payments',
        'payment_allocations',
        'cash_bank_accounts',
        'purchases',
        'purchase_items',
        'sales_returns',
        'sales_return_items',
        'purchase_returns',
        'purchase_return_items',
        'stock_movements',
        'ledger_accounts',
        'ledger_entries',
        'expense_categories',
        'expenses',
        'audit_logs',
        'app_settings',
        'backup_records',
      ];

      for (final table in expectedTables) {
        expect(tableNames.contains(table), isTrue, reason: 'Expected table $table is missing from schema!');
      }
    });
  });
}
