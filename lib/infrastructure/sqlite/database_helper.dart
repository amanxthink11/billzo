import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/core/constants/app_constants.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/sqlite/database_migrator.dart';

/// Manages the SQLite database connection, PRAGMA configuration, lifecycle, and transactions.
class DatabaseHelper {
  static DatabaseHelper? _instance;
  Database? _database;

  final IAppPathProvider pathProvider;
  final String? customDbPath;
  final DatabaseFactory _dbFactory;

  DatabaseHelper({
    required this.pathProvider,
    this.customDbPath,
    DatabaseFactory? dbFactory,
  }) : _dbFactory = dbFactory ?? databaseFactory;

  /// Returns the singleton instance for application usage.
  static DatabaseHelper getInstance({
    IAppPathProvider? pathProvider,
    String? customDbPath,
    DatabaseFactory? dbFactory,
  }) {
    if (_instance == null || customDbPath != null) {
      _initFfiIfNeeded();
      _instance = DatabaseHelper(
        pathProvider: pathProvider ?? ProductionAppPathProvider(),
        customDbPath: customDbPath,
        dbFactory: dbFactory ?? (kIsWeb ? databaseFactory : databaseFactoryFfi),
      );
    }
    return _instance!;
  }

  /// Factory for testing with isolated or in-memory databases.
  static DatabaseHelper createForTesting({
    required String dbPath,
    required IAppPathProvider pathProvider,
    DatabaseFactory? dbFactory,
  }) {
    _initFfiIfNeeded();
    return DatabaseHelper(
      pathProvider: pathProvider,
      customDbPath: dbPath,
      dbFactory: dbFactory ?? databaseFactoryFfi,
    );
  }

  static void _initFfiIfNeeded() {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  /// The DatabaseFactory used by this helper.
  DatabaseFactory get dbFactory => _dbFactory;

  /// Returns the active SQLite database instance, opening and migrating it if needed.
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final String path = customDbPath ?? await _resolveDatabasePath();

    final db = await _dbFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        onConfigure: (db) async {
          // Enforce relational integrity and high-performance WAL mode
          await db.execute('PRAGMA foreign_keys = ON;');
          
          // In-memory or temporary databases might not support WAL mode
          if (path != inMemoryDatabasePath) {
            await db.execute('PRAGMA journal_mode = WAL;');
          }
          await db.execute('PRAGMA synchronous = NORMAL;');
          await db.execute('PRAGMA busy_timeout = 5000;');
        },
        onOpen: (db) async {
          // Run versioned migrations inside atomic transactions
          await DatabaseMigrator.runPendingMigrations(db);
        },
      ),
    );

    return db;
  }

  /// Returns the resolved filesystem path to the active SQLite database file.
  Future<String> getDatabasePath() async {
    return customDbPath ?? await _resolveDatabasePath();
  }

  Future<String> _resolveDatabasePath() async {
    final dir = await pathProvider.getDatabaseDirectory();
    return p.join(dir, AppConstants.databaseFileName);
  }

  /// Executes a PRAGMA integrity_check to verify database health.
  Future<bool> verifyIntegrity() async {
    final db = await database;
    final results = await db.rawQuery('PRAGMA integrity_check;');
    if (results.isEmpty) return false;
    final firstVal = results.first.values.first;
    return firstVal == 'ok';
  }

  /// Runs an atomic transaction using the database connection.
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return await db.transaction(action);
  }

  /// Safely closes the database connection.
  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }

  /// Resets the instance (primarily for tests).
  static Future<void> resetInstance() async {
    if (_instance != null) {
      await _instance!.close();
      _instance = null;
    }
  }
}
