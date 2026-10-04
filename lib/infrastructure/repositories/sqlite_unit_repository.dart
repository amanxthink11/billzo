import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:billzo/domain/catalog/unit_of_measurement.dart';
import 'package:billzo/domain/catalog/unit_repository.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

/// SQLite implementation of [IUnitRepository].
class SqliteUnitRepository implements IUnitRepository {
  final DatabaseHelper _dbHelper;
  final Uuid _uuid = const Uuid();

  SqliteUnitRepository(this._dbHelper);

  @override
  Future<UnitOfMeasurement> createUnit(UnitOfMeasurement unit) async {
    final trimmedName = unit.name.trim();
    final trimmedShortName = unit.shortName.trim().toUpperCase();

    if (trimmedName.isEmpty) {
      throw ArgumentError('Unit name cannot be empty');
    }
    if (trimmedShortName.isEmpty) {
      throw ArgumentError('Unit short code cannot be empty');
    }

    final db = await _dbHelper.database;

    // Check if unit short code already exists for this business
    final existing = await db.query(
      'units',
      where: 'business_id = ? AND UPPER(code) = ?',
      whereArgs: [unit.businessId, trimmedShortName],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      throw StateError('Unit with code "$trimmedShortName" already exists for this business');
    }

    final id = unit.id.isEmpty ? _uuid.v4() : unit.id;
    final now = DateTime.now().toUtc();

    final toInsert = unit.copyWith(
      id: id,
      name: trimmedName,
      shortName: trimmedShortName,
      createdAt: now,
      updatedAt: now,
    );

    await db.insert('units', toInsert.toMap());
    return toInsert;
  }

  @override
  Future<List<UnitOfMeasurement>> getUnits(String businessId) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'units',
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
      orderBy: 'name ASC',
    );

    final existingCodes = results.map((r) => (r['code'] as String).toUpperCase()).toSet();
    if (!existingCodes.contains('NOS') || !existingCodes.contains('HRS')) {
      await _ensureStandardServiceUnits(db, businessId, existingCodes);
      final refreshed = await db.query(
        'units',
        where: 'business_id = ? AND is_active = 1',
        whereArgs: [businessId],
        orderBy: 'name ASC',
      );
      return refreshed.map(UnitOfMeasurement.fromMap).toList();
    }

    return results.map(UnitOfMeasurement.fromMap).toList();
  }

  Future<void> _ensureStandardServiceUnits(Database db, String businessId, Set<String> existingCodes) async {
    final nowStr = DateTime.now().toUtc().toIso8601String();
    final serviceUnits = [
      {'code': 'NOS', 'name': 'Numbers', 'decimal': 0},
      {'code': 'HRS', 'name': 'Hours', 'decimal': 1},
      {'code': 'DAY', 'name': 'Days', 'decimal': 1},
      {'code': 'MTH', 'name': 'Months', 'decimal': 1},
      {'code': 'JOB', 'name': 'Job Work', 'decimal': 0},
      {'code': 'SRV', 'name': 'Service Unit', 'decimal': 0},
      {'code': 'OTH', 'name': 'Others', 'decimal': 1},
    ];

    for (final unit in serviceUnits) {
      final code = unit['code'] as String;
      if (!existingCodes.contains(code.toUpperCase())) {
        await db.insert('units', {
          'id': _uuid.v4(),
          'business_id': businessId,
          'code': code,
          'name': unit['name'],
          'allow_decimal': unit['decimal'],
          'is_active': 1,
          'created_at': nowStr,
          'updated_at': nowStr,
          'sync_version': 1,
          'sync_status': 'synced',
        });
      }
    }
  }

  @override
  Future<UnitOfMeasurement?> getUnitById(String id) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'units',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return UnitOfMeasurement.fromMap(results.first);
  }

  @override
  Future<UnitOfMeasurement?> getDefaultUnit(String businessId) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'units',
      where: 'business_id = ? AND UPPER(code) = ?',
      whereArgs: [businessId, 'PCS'],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return UnitOfMeasurement.fromMap(results.first);
    }
    final all = await getUnits(businessId);
    return all.isNotEmpty ? all.first : null;
  }
}
