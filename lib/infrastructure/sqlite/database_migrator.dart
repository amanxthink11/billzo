import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:billzo/infrastructure/sqlite/migrations/migration_001_initial_schema.dart';
import 'package:billzo/infrastructure/sqlite/migrations/migration_003_payments.dart';
import 'package:billzo/infrastructure/sqlite/migrations/migration_004_purchases.dart';
import 'package:billzo/infrastructure/sqlite/migrations/migration_005_expenses.dart';
import 'package:billzo/infrastructure/sqlite/migrations/migration_006_recurring_enhancements.dart';

/// Represents a single tracked database migration.
class MigrationRecord {
  final int version;
  final String appliedAt;
  final String checksum;
  final String description;

  const MigrationRecord({
    required this.version,
    required this.appliedAt,
    required this.checksum,
    required this.description,
  });

  factory MigrationRecord.fromMap(Map<String, dynamic> map) {
    return MigrationRecord(
      version: map['version'] as int,
      appliedAt: map['applied_at'] as String,
      checksum: map['checksum'] as String,
      description: map['description'] as String,
    );
  }
}

/// Executes and tracks versioned database migrations deterministically and idempotently.
class DatabaseMigrator {
  DatabaseMigrator._();

  static const String migrationsTable = 'schema_migrations';

  /// Ensures the migration tracking table exists.
  static Future<void> ensureMigrationsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $migrationsTable (
          version INTEGER PRIMARY KEY NOT NULL,
          applied_at TEXT NOT NULL,
          checksum TEXT NOT NULL,
          description TEXT NOT NULL
      );
    ''');
  }

  /// Returns list of all applied migrations sorted ascending by version.
  static Future<List<MigrationRecord>> getAppliedMigrations(DatabaseExecutor db) async {
    await ensureMigrationsTable(db);
    final results = await db.query(migrationsTable, orderBy: 'version ASC');
    return results.map(MigrationRecord.fromMap).toList();
  }

  /// Runs all pending migrations inside atomic transactions.
  static Future<void> runPendingMigrations(Database db) async {
    await ensureMigrationsTable(db);

    final applied = await getAppliedMigrations(db);
    final appliedVersions = applied.map((m) => m.version).toSet();

    // Registry of all versioned migrations
    final List<_MigrationDefinition> allMigrations = [
      _MigrationDefinition(
        version: Migration001InitialSchema.version,
        description: Migration001InitialSchema.description,
        statements: Migration001InitialSchema.statements,
      ),
      _MigrationDefinition(
        version: Migration003Payments.version,
        description: Migration003Payments.description,
        statements: Migration003Payments.statements,
      ),
      _MigrationDefinition(
        version: Migration004Purchases.version,
        description: Migration004Purchases.description,
        statements: Migration004Purchases.statements,
      ),
      _MigrationDefinition(
        version: Migration005Expenses.version,
        description: Migration005Expenses.description,
        statements: Migration005Expenses.statements,
      ),
      _MigrationDefinition(
        version: Migration006RecurringEnhancements.version,
        description: Migration006RecurringEnhancements.description,
        statements: Migration006RecurringEnhancements.statements,
      ),
    ];

    for (final migration in allMigrations) {
      final checksum = _computeChecksum(migration.statements);

      if (appliedVersions.contains(migration.version)) {
        // Migration was already applied, verify its checksum integrity
        final record = applied.firstWhere((m) => m.version == migration.version);
        if (record.checksum != checksum) {
          throw StateError(
            'Database migration checksum mismatch for version ${migration.version}! '
            'Expected: $checksum, Found: ${record.checksum}. '
            'Previously applied migrations must never be altered.',
          );
        }
        continue;
      }

      // Execute pending migration inside an atomic transaction
      await db.transaction((txn) async {
        for (final statement in migration.statements) {
          final trimmed = statement.trim();
          if (trimmed.isNotEmpty) {
            await txn.execute(trimmed);
          }
        }

        // Record successful migration
        await txn.insert(migrationsTable, {
          'version': migration.version,
          'applied_at': DateTime.now().toUtc().toIso8601String(),
          'checksum': checksum,
          'description': migration.description,
        });
      });
    }
  }

  static String _computeChecksum(List<String> statements) {
    final buffer = StringBuffer();
    for (final s in statements) {
      buffer.writeln(s.trim());
    }
    final bytes = utf8.encode(buffer.toString());
    return sha256.convert(bytes).toString();
  }
}

class _MigrationDefinition {
  final int version;
  final String description;
  final List<String> statements;

  const _MigrationDefinition({
    required this.version,
    required this.description,
    required this.statements,
  });
}
